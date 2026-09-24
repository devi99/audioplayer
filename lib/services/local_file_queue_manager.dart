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
  Future<void> loadQueue() async {
    if (_api == null) return;
    if (_isLoading) return;

    _isLoading = true;
    try {
      _queue = await _api!.fetchLocalFileQueue();
      _currentItem = _queue.isNotEmpty
          ? _queue.firstWhere((item) => item.isCurrentlyPlaying, orElse: () => _queue.first)
          : null;
      _queueController.add(List.unmodifiable(_queue));
      _currentItemController.add(_currentItem);
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

    await loadQueue();

    // If queue was empty before adding, start playing
    if (previousLength == 0) {
      await playItem(item);
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
  Future<void> setCurrentItem(int queueItemId) async {
    if (_api == null) return;

    try {
      await _api!.setLocalFileQueueCurrentlyPlaying(queueItemId);
      await loadQueue();
    } catch (error) {
      debugPrint('Failed to set current queue item: $error');
    }
  }

  /// Play a specific queue item
  Future<void> playItem(LocalFileQueueItem item) async {
    if (_api == null) return;

    try {
      await setCurrentItem(item.id);

      final track = MusicTrack(
        id: item.id.toString(),
        title: item.title ?? 'Unknown',
        artist: item.artist ?? 'Unknown',
        album: item.album ?? '',
        durationSeconds: 0,
        rankOrder: -1,
        tags: const [],
        filePath: item.fullFilePath,
      );

      await _playbackController.playTrack(
        track: track,
        streamUrl: _api!.streamSongUrl(item.id.toString()),
      );
    } catch (error) {
      debugPrint('Failed to play queue item: $error');
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
