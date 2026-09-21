import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// Ignore this import, it's used for method channel error handling
// import 'package:flutter/services.dart' as flutter_services;

import '../models/music_track.dart';
import 'song_cache.dart';

class NowPlayingState {
  const NowPlayingState({this.track});

  final MusicTrack? track;

  bool get hasTrack => track != null;
}

class PlaybackController {
  PlaybackController._() {
    _player.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.stopped) {
        _setNowPlaying(null);
      }
    });
    _player.onPlayerComplete.listen((_) {
      _setNowPlaying(null);
      // When a track completes, automatically play the next one if we have a queue
      unawaited(_handleTrackComplete());
    });
    
    // Set up media action listener for notification controls
    _mediaChannel.setMethodCallHandler((call) async {
      try {
        switch (call.method) {
          case 'next':
            await playNext();
            return 'next handled';
          case 'previous':
            await playPrevious();
            return 'previous handled';
          case 'play':
            if (_isQueuePlaying && _currentQueueIndex >= 0 && _currentQueueIndex < _queue.length) {
              // Resume current track
              await _playCurrentQueueTrack();
            } else if (_queue.isNotEmpty) {
              // Start playing queue
              await playQueue();
            }
            return 'play handled';
          case 'pause':
            await stop();
            return 'pause handled';
          default:
            throw PlatformException(code: 'unimplemented', message: 'Unknown media action: ${call.method}');
        }
      } catch (e) {
        debugPrint('Failed to handle media action ${call.method}: $e');
        return null;
      }
    });
  }

  static final PlaybackController instance = PlaybackController._();
  static const MethodChannel _channel = MethodChannel('com.example.audioplayer/notification');
  static const MethodChannel _mediaChannel = MethodChannel('com.example.audioplayer/media');

  final AudioPlayer _player = AudioPlayer()
    ..setReleaseMode(ReleaseMode.stop);
  final ValueNotifier<NowPlayingState> nowPlaying =
      ValueNotifier<NowPlayingState>(const NowPlayingState());
  final SongCache _cache = SongCache();
  final Set<String> _downloadingSongs = {};
  final ValueNotifier<Set<String>> downloadingSongs =
      ValueNotifier<Set<String>>({});

  Stream<void> get onPlayerComplete => _player.onPlayerComplete;

  // Queue state
  List<MusicTrack> _queue = [];
  int _currentQueueIndex = -1;
  bool _isQueuePlaying = false;
  
  // Callback for getting stream URLs (set by the UI)
  String Function(String trackId)? _getStreamUrlSync;
  Future<String> Function(String trackId)? _getStreamUrlAsync;

  // Stream for queue state changes
  final StreamController<List<MusicTrack>> _queueController = StreamController.broadcast();
  final StreamController<int> _queueIndexController = StreamController.broadcast();
  final StreamController<bool> _queuePlayingController = StreamController.broadcast();

  Stream<List<MusicTrack>> get onQueueChanged => _queueController.stream;
  Stream<int> get onQueueIndexChanged => _queueIndexController.stream;
  Stream<bool> get onQueuePlayingChanged => _queuePlayingController.stream;

  List<MusicTrack> get currentQueue => List.unmodifiable(_queue);
  int get currentQueueIndex => _currentQueueIndex;
  bool get isQueuePlaying => _isQueuePlaying;

  // Set the stream URL provider (called by UI to provide API access)
  void setStreamUrlProviderSync(String Function(String trackId) provider) {
    _getStreamUrlSync = provider;
  }
  
  void setStreamUrlProviderAsync(Future<String> Function(String trackId) provider) {
    _getStreamUrlAsync = provider;
  }

  // Set up a queue for playback
  void setQueue(List<MusicTrack> queue, {int startIndex = 0}) {
    _queue = List.from(queue);
    _currentQueueIndex = startIndex >= 0 && startIndex < _queue.length ? startIndex : -1;
    _queueController.add(List.unmodifiable(_queue));
    _queueIndexController.add(_currentQueueIndex);
  }

  // Clear the current queue
  void clearQueue() {
    _queue.clear();
    _currentQueueIndex = -1;
    _isQueuePlaying = false;
    _queueController.add(List.unmodifiable(_queue));
    _queueIndexController.add(_currentQueueIndex);
    _queuePlayingController.add(_isQueuePlaying);
  }

  // Start playing the queue
  Future<void> playQueue({int startIndex = 0}) async {
    if (_queue.isEmpty) return;
    
    if (startIndex < 0 || startIndex >= _queue.length) {
      startIndex = 0;
    }
    
    _currentQueueIndex = startIndex;
    _isQueuePlaying = true;
    _queueIndexController.add(_currentQueueIndex);
    _queuePlayingController.add(_isQueuePlaying);
    
    await _playCurrentQueueTrack();
  }

  // Play the track at the current queue index
  Future<void> _playCurrentQueueTrack() async {
    if (_currentQueueIndex < 0 || _currentQueueIndex >= _queue.length) {
      return;
    }
    
    final track = _queue[_currentQueueIndex];
    
    String streamUrl;
    if (_getStreamUrlSync != null) {
      streamUrl = _getStreamUrlSync!(track.id);
    } else if (_getStreamUrlAsync != null) {
      streamUrl = await _getStreamUrlAsync!(track.id);
    } else {
      debugPrint('No stream URL provider set for queue playback');
      return;
    }
    
    try {
      await playTrack(track: track, streamUrl: streamUrl);
    } catch (e) {
      debugPrint('Failed to play queue track: $e');
      // Try to play next track if available
      if (_isQueuePlaying && _currentQueueIndex + 1 < _queue.length) {
        _currentQueueIndex++;
        _queueIndexController.add(_currentQueueIndex);
        unawaited(_playCurrentQueueTrack());
      }
    }
  }

  // Handle track completion - play next track automatically
  Future<void> _handleTrackComplete() async {
    if (!_isQueuePlaying) return;
    
    // Move to next track
    _currentQueueIndex++;
    
    if (_currentQueueIndex >= _queue.length) {
      // Queue ended
      _isQueuePlaying = false;
      _currentQueueIndex = -1;
      _queueIndexController.add(_currentQueueIndex);
      _queuePlayingController.add(_isQueuePlaying);
      return;
    }
    
    _queueIndexController.add(_currentQueueIndex);
    await _playCurrentQueueTrack();
  }

  // Manually play next track
  Future<void> playNext() async {
    if (!_isQueuePlaying && _queue.isNotEmpty) {
      // If not currently playing, start from beginning or current position
      if (_currentQueueIndex < 0) {
        _currentQueueIndex = 0;
      }
      _isQueuePlaying = true;
      _queuePlayingController.add(_isQueuePlaying);
    }
    
    if (_isQueuePlaying && _currentQueueIndex + 1 < _queue.length) {
      _currentQueueIndex++;
      _queueIndexController.add(_currentQueueIndex);
      await _playCurrentQueueTrack();
    } else if (_isQueuePlaying) {
      // Reached end of queue
      _isQueuePlaying = false;
      _queuePlayingController.add(_isQueuePlaying);
    }
  }

  // Manually play previous track
  Future<void> playPrevious() async {
    if (!_isQueuePlaying || _queue.isEmpty) return;
    
    if (_currentQueueIndex > 0) {
      _currentQueueIndex--;
      _queueIndexController.add(_currentQueueIndex);
      await _playCurrentQueueTrack();
    } else {
      // At beginning of queue, restart current track or stop
      await _playCurrentQueueTrack();
    }
  }

  // Stop queue playback
  Future<void> stopQueue() async {
    _isQueuePlaying = false;
    _currentQueueIndex = -1;
    _queuePlayingController.add(_isQueuePlaying);
    _queueIndexController.add(_currentQueueIndex);
    await stop();
  }

  // Skip to a specific track in the queue
  Future<void> skipToIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;
    
    _currentQueueIndex = index;
    _queueIndexController.add(_currentQueueIndex);
    
    if (!_isQueuePlaying) {
      _isQueuePlaying = true;
      _queuePlayingController.add(_isQueuePlaying);
    }
    
    await _playCurrentQueueTrack();
  }

  Future<void> playTrack({
    required MusicTrack track,
    required String streamUrl,
  }) async {
    // Check if song is cached
    final cachedPath = await _cache.getCachedFilePath(track.id);
    
    if (cachedPath != null) {
      // Play from cache
      await _player.stop();
      await _player.play(DeviceFileSource(cachedPath));
      // Set now playing state immediately after playback starts
      _setNowPlaying(track);
      // Show notification (don't await, as it may fail on non-Android platforms)
      unawaited(_showNotification(track));
      return;
    }
    
    // On Linux and other non-mobile platforms, UrlSource doesn't work reliably
    // So we need to download first, then play
    final isMobile = Platform.isAndroid || Platform.isIOS;
    
    if (!isMobile) {
      // For Linux, Windows, macOS, Web: download first, then play
      await _player.stop();
      // Download and cache synchronously before playing
      final downloadedPath = await _cache.downloadAndCache(track.id, streamUrl);
      await _player.play(DeviceFileSource(downloadedPath));
      // Set now playing state immediately after playback starts
      _setNowPlaying(track);
      // Show notification (don't await, as it may fail on non-Android platforms)
      unawaited(_showNotification(track));
      return;
    }
    
    // For Android and iOS: start streaming and download in background
    await _player.stop();
    await _player.play(UrlSource(streamUrl));
    // Set now playing state immediately after playback starts
    _setNowPlaying(track);
    // Show notification (may fail on some platforms, but don't let it block)
    unawaited(_showNotification(track));
    
    // Download for future playback
    _downloadForCache(track.id, streamUrl);
  }
  
  Future<void> _downloadForCache(String songId, String streamUrl) async {
    if (_downloadingSongs.contains(songId)) return;
    
    _downloadingSongs.add(songId);
    downloadingSongs.value = Set<String>.from(_downloadingSongs);
    
    try {
      await _cache.downloadAndCache(songId, streamUrl);
    } catch (e) {
      // Log error, but don't interrupt playback
      debugPrint('Failed to cache song $songId: $e');
    } finally {
      _downloadingSongs.remove(songId);
      downloadingSongs.value = Set<String>.from(_downloadingSongs);
    }
  }

  Future<void> stop() async {
    await _player.stop();
    // Hide notification (don't await, as it may fail on non-Android platforms)
    unawaited(_hideNotification());
    _setNowPlaying(null);
  }

  Future<void> _showNotification(MusicTrack track) async {
    // Notifications are only supported on Android
    if (!Platform.isAndroid) return;
    
    try {
      await _channel.invokeMethod('showNotification', {
        'title': track.title,
        'artist': track.artist,
        'isPlaying': true,
      });
    } catch (e) {
      // On Android, notifications might still fail
      debugPrint('Failed to show notification: $e');
    }
  }

  Future<void> _hideNotification() async {
    // Notifications are only supported on Android
    if (!Platform.isAndroid) return;
    
    try {
      await _channel.invokeMethod('hideNotification');
    } catch (e) {
      // On Android, notifications might still fail
      debugPrint('Failed to hide notification: $e');
    }
  }

  void _setNowPlaying(MusicTrack? track) {
    // Always update the state to ensure UI consistency
    nowPlaying.value = NowPlayingState(track: track);
  }
  
  // Cache management methods exposed for UI
  Future<bool> isSongCached(String songId) async {
    return await _cache.isCached(songId);
  }
  
  Future<void> clearCache() async {
    await _cache.clearCache();
  }
  
  Future<int> getCacheSize() async {
    return await _cache.getCacheSize();
  }
  
  Future<List<String>> getCachedSongIds() async {
    return await _cache.getCachedSongIds();
  }
  
  Future<void> removeFromCache(String songId) async {
    await _cache.removeFromCache(songId);
  }
}
