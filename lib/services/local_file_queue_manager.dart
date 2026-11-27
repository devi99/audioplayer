import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/local_file_queue_item.dart';
import '../models/music_track.dart';
import 'music_library_api.dart';
import 'playback_controller.dart';

/// Singleton manager for LocalFileQueue operations.
/// Manages queue state and playback integration with the API.
class LocalFileQueueManager {
  LocalFileQueueManager._();

  static final LocalFileQueueManager instance = LocalFileQueueManager._();

  MusicLibraryApi? _api;
  final PlaybackController _playbackController = PlaybackController.instance;

  List<LocalFileQueueItem> _queue = [];
  LocalFileQueueItem? _currentItem;
  bool _isLoading = false;

  // Stream controllers for UI updates
  final StreamController<List<LocalFileQueueItem>> _queueController =
      StreamController.broadcast();
  final StreamController<LocalFileQueueItem?> _currentItemController =
      StreamController.broadcast();

  // Track PlaybackController's queue index to keep _currentItem in sync
  StreamSubscription<int>? _playbackQueueIndexSubscription;

  /// Stream that emits when the queue changes
  Stream<List<LocalFileQueueItem>> get onQueueChanged => _queueController.stream;

  /// Stream that emits when the current item changes
  Stream<LocalFileQueueItem?> get onCurrentItemChanged =>
      _currentItemController.stream;

  /// Get the current queue items (immutable)
  List<LocalFileQueueItem> get queue => List.unmodifiable(_queue);

  /// Get the currently playing queue item
  LocalFileQueueItem? get currentItem => _currentItem;

  /// Set the API instance to use for queue operations
  void setApi(MusicLibraryApi api) {
    debugPrint('[QueueManager] setApi: setting API and subscribing to PlaybackController queue index');
    _api = api;
    
    // Subscribe to PlaybackController's queue index changes
    // This ensures we update _currentItem when auto-advance happens
    _playbackQueueIndexSubscription?.cancel();
    _playbackQueueIndexSubscription = _playbackController.onQueueIndexChanged.listen((index) {
      debugPrint('[QueueManager] PlaybackController queue index changed to $index');
      _updateCurrentItemFromPlaybackIndex(index);
    });
  }

  /// Load the queue from the API
  /// If we already have a current item, preserve it unless it's not in the queue anymore
  Future<void> loadQueue({bool forceRefreshCurrent = false}) async {
    if (_api == null) return;
    if (_isLoading) return;

    _isLoading = true;
    debugPrint('[QueueManager] loadQueue called, forceRefreshCurrent=$forceRefreshCurrent, hasCurrent=${_currentItem != null}');
    try {
      final newQueue = await _api!.fetchLocalFileQueue();
      final hasCurrent = _currentItem != null;
      debugPrint('[QueueManager] loadQueue: fetched ${newQueue.length} items, hasCurrent=$hasCurrent');
      
      // Update queue
      _queue = newQueue;
      _queueController.add(List.unmodifiable(_queue));
      debugPrint('[QueueManager] loadQueue: queue updated, _queue.length=${_queue.length}');
      
      // Update current item if needed
      if (forceRefreshCurrent || !hasCurrent) {
        // No local current item, use API's isCurrentlyPlaying flag
        _currentItem = _queue.isNotEmpty
            ? _queue.firstWhere(
                (item) => item.isCurrentlyPlaying, 
                orElse: () => _queue.first,
              )
            : null;
        debugPrint('[QueueManager] loadQueue: setting _currentItem from API, _currentItem=${_currentItem?.id}');
        _currentItemController.add(_currentItem);
      } else if (hasCurrent && !_queue.any((item) => item.id == _currentItem!.id)) {
        // Current item is no longer in queue, clear it
        _currentItem = null;
        debugPrint('[QueueManager] loadQueue: current item not in queue, clearing');
        _currentItemController.add(_currentItem);
      } else {
        debugPrint('[QueueManager] loadQueue: preserving existing _currentItem=${_currentItem?.id}');
        // Still notify so that any new listeners (like QueueScreen just mounted) get the current value
        _currentItemController.add(_currentItem);
      }
      // Otherwise, keep the existing _currentItem
    } catch (error) {
      debugPrint('Failed to load local file queue: $error');
    } finally {
      _isLoading = false;
    }
  }

  /// Add a song to the queue
  /// Note: This does NOT call loadQueue() - the caller should call it if needed
  Future<LocalFileQueueItem?> addToQueue({
    required String fullFilePath,
    String? album,
    String? artist,
    String? title,
  }) async {
    if (_api == null) return null;

    try {
      final item = await _api!.addToLocalFileQueue(
        fullFilePath: fullFilePath,
        album: album,
        artist: artist,
        title: title,
      );
      return item;
    } catch (error) {
      debugPrint('Failed to add to local file queue: $error');
      return null;
    }
  }

  /// Find a song by its file path using the API endpoint
  Future<MusicTrack?> _findSongByFilePath(String filePath) async {
    try {
      return await _api!.fetchSongByFilePath(filePath);
    } catch (e) {
      debugPrint('Failed to find song by filePath: $e');
      return null;
    }
  }

  /// Add a song to the queue and start playing if the queue was empty
  Future<void> addAndPlayIfEmpty(MusicTrack song) async {
    debugPrint('[QueueManager] addAndPlayIfEmpty: START, song.title=${song.title}, song.id=${song.id}, _api != null: ${_api != null}');
    if (_api == null) {
      debugPrint('[QueueManager] addAndPlayIfEmpty: _api is null, returning');
      return;
    }

    debugPrint('[QueueManager] addAndPlayIfEmpty: previousLength=${_queue.length}');
    final previousLength = _queue.length;
    debugPrint('[QueueManager] addAndPlayIfEmpty: calling addToQueue for song.filePath=${song.filePath}');
    final item = await addToQueue(
      fullFilePath: song.filePath!,
      album: song.album,
      artist: song.artist,
      title: song.title,
    );
    debugPrint('[QueueManager] addAndPlayIfEmpty: added item ${item?.id}');

    if (item == null) {
      debugPrint('[QueueManager] addAndPlayIfEmpty: item is null, returning');
      return;
    }

    // Reload queue to get the new item
    debugPrint('[QueueManager] addAndPlayIfEmpty: calling loadQueue');
    await loadQueue();
    debugPrint('[QueueManager] addAndPlayIfEmpty: loadQueue complete, _queue.length=${_queue.length}');

    // Always sync to PlaybackController so it knows about all queued items
    debugPrint('[QueueManager] addAndPlayIfEmpty: calling _syncQueueToPlaybackController');
    await _syncQueueToPlaybackController();

    // If queue was empty before adding, start playing
    if (previousLength == 0) {
      debugPrint('[QueueManager] addAndPlayIfEmpty: queue was empty, setting current item');
      // Find the item in the queue (it should be there after loadQueue)
      // If not found, fall back to the response item
      final queueItem = _queue.firstWhere((i) => i.id == item.id, orElse: () => item);
      debugPrint('[QueueManager] addAndPlayIfEmpty: found queueItem ${queueItem.id}');
      _currentItem = queueItem;
      debugPrint('[QueueManager] addAndPlayIfEmpty: _currentItem set to ${_currentItem?.id}');
      _currentItemController.add(_currentItem);
      
      // Set current item in API
      debugPrint('[QueueManager] addAndPlayIfEmpty: calling _setCurrentItemInApi');
      await _setCurrentItemInApi(item.id);

      // Start playing
      debugPrint('[QueueManager] addAndPlayIfEmpty: calling _playbackController.playQueue(startIndex: 0)');
      await _playbackController.playQueue(startIndex: 0);
      debugPrint('[QueueManager] addAndPlayIfEmpty: COMPLETE');
    } else {
      debugPrint('[QueueManager] addAndPlayIfEmpty: queue was not empty (previousLength=$previousLength), only synced to PlaybackController');
    }
  }

  /// Remove a song from the queue by its ID
  Future<bool> removeFromQueue(int queueItemId) async {
    if (_api == null) return false;

    try {
      await _api!.removeFromLocalFileQueue(queueItemId);
      await loadQueue();
      return true;
    } catch (error) {
      debugPrint('Failed to remove from local file queue: $error');
      return false;
    }
  }

  /// Clear all items from the queue
  Future<void> clearQueue() async {
    if (_api == null) return;

    try {
      await _api!.clearLocalFileQueue();
      _queue.clear();
      _currentItem = null;
      _queueController.add(List.unmodifiable(_queue));
      _currentItemController.add(_currentItem);
    } catch (error) {
      debugPrint('Failed to clear local file queue: $error');
    }
  }

  /// Set the currently playing item in the queue
  /// This updates the API but does NOT reload the queue - the caller is responsible
  /// for updating the local state
  Future<void> _setCurrentItemInApi(int queueItemId) async {
    if (_api == null) return;

    try {
      await _api!.setLocalFileQueueCurrentlyPlaying(queueItemId);
    } catch (error) {
      debugPrint('Failed to set current queue item in API: $error');
    }
  }

  /// Set the currently playing item in the queue and update local state
  Future<void> setCurrentItem(int queueItemId) async {
    if (_api == null) return;

    debugPrint('[QueueManager] setCurrentItem: queueItemId=$queueItemId');
    try {
      // Find the item in our queue
      LocalFileQueueItem? item;
      try {
        item = _queue.firstWhere((i) => i.id == queueItemId);
      } catch (e) {
        // Not found
        debugPrint('[QueueManager] setCurrentItem: item not found in queue');
        item = null;
      }
      
      if (item != null) {
        _currentItem = item;
        debugPrint('[QueueManager] setCurrentItem: _currentItem set to ${item.id}');
        _currentItemController.add(_currentItem);
      } else {
        debugPrint('[QueueManager] setCurrentItem: item is null, not updating _currentItem');
      }
      
      // Update in API (don't reload, just persist)
      await _setCurrentItemInApi(queueItemId);
    } catch (error) {
      debugPrint('Failed to set current queue item: $error');
    }
  }

  /// Play a specific queue item
  Future<void> playItem(LocalFileQueueItem item) async {
    debugPrint('[QueueManager] playItem: START, item.id=${item.id}, filePath=${item.fullFilePath}, _api != null: ${_api != null}');
    if (_api == null) {
      debugPrint('[QueueManager] playItem: _api is null, returning');
      return;
    }

    try {
      // Update current item immediately for UI responsiveness
      _currentItem = item;
      debugPrint('[QueueManager] playItem: _currentItem set to ${item.id}');
      _currentItemController.add(_currentItem);

      // Set current item in API (without reloading queue)
      debugPrint('[QueueManager] playItem: calling _setCurrentItemInApi');
      await _setCurrentItemInApi(item.id);

      // Sync the queue to PlaybackController
      debugPrint('[QueueManager] playItem: calling _syncQueueToPlaybackController');
      await _syncQueueToPlaybackController();
      
      // Find the index of this item in the queue and play it
      final index = getIndexOfItem(item.id);
      debugPrint('[QueueManager] playItem: index=$index');
      if (index >= 0) {
        debugPrint('[QueueManager] playItem: skipping to index $index');
        await _playbackController.skipToIndex(index);
      } else {
        // Item not found in queue, fall back to direct play
        debugPrint('[QueueManager] playItem: item not in queue, playing directly');
        final song = await _findSongByFilePath(item.fullFilePath);
        if (song != null) {
          debugPrint('[QueueManager] playItem: found song ${song.id}, calling playTrack');
          await _playbackController.playTrack(
            track: song,
            streamUrl: _api!.streamSongUrl(song.id),
          );
        } else {
          debugPrint('[QueueManager] playItem: Could not find song for filePath: ${item.fullFilePath}');
          throw Exception('Could not find song for filePath: ${item.fullFilePath}');
        }
      }
      debugPrint('[QueueManager] playItem: COMPLETE');
    } catch (error) {
      debugPrint('[QueueManager] playItem: Failed to play queue item: $error');
      rethrow;
    }
  }

  /// Play the next item in the queue
  Future<void> playNext() async {
    debugPrint('[QueueManager] playNext: START, _api != null: ${_api != null}');
    if (_api == null) {
      debugPrint('[QueueManager] playNext: _api is null, returning');
      return;
    }

    try {
      // Don't resync the entire queue here - it's already synced and can cause race conditions
      // Just delegate to PlaybackController
      debugPrint('[QueueManager] playNext: calling _playbackController.playNext');
      await _playbackController.playNext();
      
      // The _updateCurrentItemFromPlaybackIndex subscription will handle updating _currentItem
      // when PlaybackController emits the new index
      debugPrint('[QueueManager] playNext: COMPLETE');
    } catch (error) {
      debugPrint('[QueueManager] playNext: Failed to play next queue item: $error');
    }
  }

  /// Get the index of a queue item by its ID
  int getIndexOfItem(int itemId) {
    for (var i = 0; i < _queue.length; i++) {
      if (_queue[i].id == itemId) {
        return i;
      }
    }
    return -1;
  }

  /// Get the next item in the queue after the current one
  LocalFileQueueItem? getNextItem() {
    if (_queue.isEmpty) return null;

    final currentIndex = _currentItem != null
        ? getIndexOfItem(_currentItem!.id)
        : -1;

    final nextIndex = currentIndex + 1;
    if (nextIndex < _queue.length) {
      return _queue[nextIndex];
    }

    return null;
  }

  /// Sync the API queue to PlaybackController's internal queue
  /// This ensures auto-advance works correctly by fetching the actual MusicTrack
  /// objects from the API based on file paths
  Future<void> _syncQueueToPlaybackController() async {
    debugPrint('[QueueManager] _syncQueueToPlaybackController: START, _api != null: ${_api != null}, _queue.length=${_queue.length}');
    if (_api == null) {
      debugPrint('[QueueManager] _syncQueueToPlaybackController: _api is null, returning');
      return;
    }

    debugPrint('[QueueManager] _syncQueueToPlaybackController: syncing ${_queue.length} items');
    
    // Find the current item index in our queue
    int startIndex = 0;
    if (_currentItem != null) {
      startIndex = getIndexOfItem(_currentItem!.id);
      debugPrint('[QueueManager] _syncQueueToPlaybackController: current item index=$startIndex');
    }
    
    // Fetch actual MusicTrack objects for each queue item
    // We need to do this because PlaybackController works with MusicTrack
    final musicTracks = <MusicTrack>[];
    for (final item in _queue) {
      debugPrint('[QueueManager] _syncQueueToPlaybackController: processing item ${item.id}, filePath=${item.fullFilePath}');
      try {
        final song = await _findSongByFilePath(item.fullFilePath);
        if (song != null) {
          debugPrint('[QueueManager] _syncQueueToPlaybackController: found song ${song.id} for item ${item.id}');
          musicTracks.add(song);
        } else {
          debugPrint('[QueueManager] _syncQueueToPlaybackController: could not find song for filePath ${item.fullFilePath}');
          // Create a placeholder track - this shouldn't happen in normal operation
          musicTracks.add(MusicTrack(
            id: 'unknown_${item.id}',
            title: item.title ?? 'Unknown',
            artist: item.artist ?? 'Unknown',
            album: item.album ?? '',
            durationSeconds: 0,
            rankOrder: 0,
            tags: const [],
            filePath: item.fullFilePath,
          ));
        }
      } catch (e) {
        debugPrint('[QueueManager] _syncQueueToPlaybackController: error fetching song: $e');
        // Create a placeholder track
        musicTracks.add(MusicTrack(
          id: 'error_${item.id}',
          title: item.title ?? 'Unknown',
          artist: item.artist ?? 'Unknown',
          album: item.album ?? '',
          durationSeconds: 0,
          rankOrder: 0,
          tags: const [],
          filePath: item.fullFilePath,
        ));
      }
    }
    
    debugPrint('[QueueManager] _syncQueueToPlaybackController: fetched ${musicTracks.length} tracks, setting queue in PlaybackController with startIndex=$startIndex');
    
    // Set the queue in PlaybackController
    _playbackController.setQueue(musicTracks, startIndex: startIndex);
    
    // Ensure the stream URL provider is set
    // This should already be set by the UI, but set it here as a fallback
    if (_api != null) {
      debugPrint('[QueueManager] _syncQueueToPlaybackController: setting stream URL provider');
      _playbackController.setStreamUrlProviderSync((trackId) => _api!.streamSongUrl(trackId));
    }
    debugPrint('[QueueManager] _syncQueueToPlaybackController: COMPLETE');
  }

  /// Update _currentItem based on PlaybackController's queue index
  /// This keeps our current item in sync when PlaybackController auto-advances
  void _updateCurrentItemFromPlaybackIndex(int playbackIndex) {
    debugPrint('[QueueManager] _updateCurrentItemFromPlaybackIndex: playbackIndex=$playbackIndex, _queue.length=${_queue.length}');
    
    // If our queue is empty or index is invalid, clear current item
    if (_queue.isEmpty || playbackIndex < 0 || playbackIndex >= _queue.length) {
      if (playbackIndex < 0) {
        debugPrint('[QueueManager] _updateCurrentItemFromPlaybackIndex: playbackIndex < 0 or queue empty, clearing current item');
      } else {
        debugPrint('[QueueManager] _updateCurrentItemFromPlaybackIndex: playbackIndex=$playbackIndex >= _queue.length=${_queue.length}, clearing current item');
      }
      final oldCurrentId = _currentItem?.id;
      _currentItem = null;
      if (oldCurrentId != null) {
        _currentItemController.add(_currentItem);
      }
      return;
    }
    
    // Find the corresponding queue item
    final newCurrentItem = _queue[playbackIndex];
    final oldCurrentId = _currentItem?.id;
    
    // Only update if the current item is actually changing
    if (oldCurrentId != newCurrentItem.id) {
      debugPrint('[QueueManager] _updateCurrentItemFromPlaybackIndex: changing _currentItem from $oldCurrentId to ${newCurrentItem.id}');
      _currentItem = newCurrentItem;
      _currentItemController.add(_currentItem);
      
      // Update in API
      unawaited(_setCurrentItemInApi(newCurrentItem.id));
    } else {
      debugPrint('[QueueManager] _updateCurrentItemFromPlaybackIndex: current item unchanged ($oldCurrentId)');
    }
  }

  /// Dispose of stream controllers
  void dispose() {
    _playbackQueueIndexSubscription?.cancel();
    _queueController.close();
    _currentItemController.close();
  }
}
