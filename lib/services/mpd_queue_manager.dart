import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/mpd_queue_item.dart';
import 'music_library_api.dart';

/// Singleton manager that mirrors the MPD queue on the remote player.
///
/// MPD has no push notifications, so this manager polls the API for the queue
/// and playback status while at least one listener is active.
class MpdQueueManager {
  MpdQueueManager._();

  static final MpdQueueManager instance = MpdQueueManager._();

  static const Duration pollInterval = Duration(seconds: 2);

  MusicLibraryApi? _api;
  Timer? _pollTimer;
  bool _isPolling = false;
  bool _isRefreshing = false;

  List<MpdQueueItem> _queue = [];
  MpdStatus? _status;
  bool _connected = false;
  String? _error;

  final StreamController<List<MpdQueueItem>> _queueController =
      StreamController.broadcast();
  final StreamController<MpdStatus?> _statusController =
      StreamController.broadcast();
  final StreamController<bool> _connectedController =
      StreamController.broadcast();
  final StreamController<String?> _errorController = StreamController.broadcast();

  /// Stream that emits when the MPD queue changes
  Stream<List<MpdQueueItem>> get onQueueChanged => _queueController.stream;

  /// Stream that emits when the MPD playback status changes
  Stream<MpdStatus?> get onStatusChanged => _statusController.stream;

  /// Stream that emits when the MPD connection state changes
  Stream<bool> get onConnectedChanged => _connectedController.stream;

  /// Stream that emits when the last error changes (null when resolved)
  Stream<String?> get onErrorChanged => _errorController.stream;

  List<MpdQueueItem> get queue => List.unmodifiable(_queue);

  MpdStatus? get status => _status;

  bool get connected => _connected;

  String? get error => _error;

  /// The currently playing queue item, matched by file path or position
  MpdQueueItem? get currentItem {
    final current = _status?.currentSong;
    if (current == null) return null;
    return _queue.firstWhere(
      (item) => item.file == current.file,
      orElse: () => current,
    );
  }

  void setApi(MusicLibraryApi api) {
    _api = api;
  }

  /// Start polling the MPD state. Safe to call multiple times.
  void startPolling() {
    if (_isPolling) return;
    _isPolling = true;
    debugPrint('[MpdQueueManager] startPolling');
    unawaited(refresh());
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) => unawaited(refresh()));
  }

  /// Stop polling when no screen is watching the MPD queue
  void stopPolling() {
    if (!_isPolling) return;
    _isPolling = false;
    debugPrint('[MpdQueueManager] stopPolling');
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Fetch the latest queue and status from the API
  Future<void> refresh() async {
    if (_api == null || _isRefreshing) return;
    _isRefreshing = true;
    try {
      final newQueue = await _api!.fetchMpdQueue();
      MpdStatus? newStatus;
      var newConnected = false;
      try {
        newStatus = await _api!.fetchMpdStatus();
        newConnected = await _api!.fetchMpdConnected();
      } on Exception catch (e) {
        debugPrint('[MpdQueueManager] status/ping failed: $e');
      }

      _error = null;
      _errorController.add(_error);
      _connected = newConnected;
      _connectedController.add(_connected);

      _status = newStatus;
      _statusController.add(_status);

      _queue = newQueue;
      _queueController.add(List.unmodifiable(_queue));
    } catch (e) {
      debugPrint('[MpdQueueManager] refresh failed: $e');
      if (_connected) {
        _connected = false;
        _connectedController.add(_connected);
      }
      _error = 'Failed to reach MPD: $e';
      _errorController.add(_error);
    } finally {
      _isRefreshing = false;
    }
  }

  /// Run an MPD action, then refresh state
  Future<void> _runAction(String name, Future<void> Function() action) async {
    if (_api == null) return;
    try {
      await action();
      await refresh();
    } catch (e) {
      debugPrint('[MpdQueueManager] $name failed: $e');
      _error = 'Failed to $name: $e';
      _errorController.add(_error);
    }
  }

  Future<void> play() => _runAction('play', () => _api!.mpdPlay());

  Future<void> pause() => _runAction('pause', () => _api!.mpdPause());

  Future<void> stop() => _runAction('stop', () => _api!.mpdStop());

  Future<void> next() => _runAction('next', () => _api!.mpdNext());

  Future<void> previous() => _runAction('previous', () => _api!.mpdPrevious());

  Future<void> clearQueue() =>
      _runAction('clear queue', () => _api!.clearMpdQueue());

  Future<void> playQueueItem(MpdQueueItem item) => _runAction(
        'play queue item',
        () => _api!.playMpdFileInQueue(item.file),
      );

  void dispose() {
    stopPolling();
    _queueController.close();
    _statusController.close();
    _connectedController.close();
    _errorController.close();
  }
}
