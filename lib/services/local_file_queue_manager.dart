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
    _api = api;
  }

  /// Load the queue from the API
  /// If we already have a current item, preserve it unless it's not in the queue anymore
  Future<void> loadQueue({bool forceRefreshCurrent = false}) async {
    if (_api == null) return;
    if (_isLoading) return;

    _isLoading = true;
    try {
      final newQueue = await _api!.fetchLocalFileQueue();
      final hasCurrent = _currentItem != null;
      
      // Update queue
      _queue = newQueue;
      _queueController.add(List.unmodifiable(_queue));
      
      // Update current item if needed
      if (forceRefreshCurrent || !hasCurrent) {
        // No local current item, use API's isCurrentlyPlaying flag
        _currentItem = _queue.isNotEmpty
            ? _queue.firstWhere(
                (item) => item.isCurrentlyPlaying, 
                orElse: () => _queue.first,
              )
            : null;
        _currentItemController.add(_currentItem);
      } else if (hasCurrent && !_queue.any((item) => item.id == _currentItem!.id)) {
        // Current item is no longer in queue, clear it
        _currentItem = null;
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
      await loadQueue();
      return item;
    } catch (error) {
      debugPrint('Failed to add to local file queue: $error');
      return null;
    }
  }

  /// Find a song by its file path
  Future<MusicTrack?> _findSongByFilePath(String filePath) async {
    try {
      // Fetch all songs and find the one with matching filePath
      final allSongs = await _api!.fetchAllSongs();
      try {
        return allSongs.firstWhere(
          (song) => song.filePath == filePath,
        );
      } catch (e) {
        // No matching song found
        return null;
      }
    } catch (e) {
      debugPrint('Failed to find song by filePath: $e');
      return null;
    }
  }

  /// Add a song to the queue and start playing if the queue was empty
  Future<void> addAndPlayIfEmpty(MusicTrack song) async {
    if (_api == null) return;

    final previousLength = _queue.length;
    final item = await addToQueue(
      fullFilePath: song.filePath!,
      album: song.album,
      artist: song.artist,
      title: song.title,
    );

    if (item == null) return;

    // If queue was empty before adding, start playing
    if (previousLength == 0) {
      // Set current item in API and update local state
      await setCurrentItem(item.id);

      // Play using the original song's ID (we have it available here)
      await _playbackController.playTrack(
        track: song,
        streamUrl: _api!.streamSongUrl(song.id),
      );
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

    try {
      // Find the item in our queue
      LocalFileQueueItem? item;
      try {
        item = _queue.firstWhere((i) => i.id == queueItemId);
      } catch (e) {
        // Not found
        item = null;
      }
      
      if (item != null) {
        _currentItem = item;
        _currentItemController.add(_currentItem);
      }
      
      // Update in API (don't reload, just persist)
      await _setCurrentItemInApi(queueItemId);
    } catch (error) {
      debugPrint('Failed to set current queue item: $error');
    }
  }

  /// Play a specific queue item
  Future<void> playItem(LocalFileQueueItem item) async {
    if (_api == null) return;

    try {
      // Update current item immediately for UI responsiveness
      _currentItem = item;
      _currentItemController.add(_currentItem);

      // Set current item in API (without reloading queue)
      await _setCurrentItemInApi(item.id);

      // Find the song by filePath and play it
      final song = await _findSongByFilePath(item.fullFilePath);
      if (song != null) {
        await _playbackController.playTrack(
          track: song,
          streamUrl: _api!.streamSongUrl(song.id),
        );
      } else {
        debugPrint('Could not find song for filePath: ${item.fullFilePath}');
        throw Exception('Could not find song for filePath: ${item.fullFilePath}');
      }
    } catch (error) {
      debugPrint('Failed to play queue item: $error');
      rethrow;
    }
  }

  /// Play the next item in the queue
  Future<void> playNext() async {
    if (_api == null) return;

    try {
      final nextItem = await _api!.getNextLocalFileQueueTrack();
      if (nextItem != null) {
        await playItem(nextItem);
      } else {
        // Queue is empty
        await _playbackController.stop();
      }
    } catch (error) {
      debugPrint('Failed to play next queue item: $error');
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

  /// Dispose of stream controllers
  void dispose() {
    _queueController.close();
    _currentItemController.close();
  }
}
