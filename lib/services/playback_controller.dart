import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// Ignore this import, it's used for method channel error handling
// import 'package:flutter/services.dart' as flutter_services;

import '../models/music_track.dart';
import 'song_cache.dart';
import 'youtube_fallback.dart';

class NowPlayingState {
  const NowPlayingState({this.track});

  final MusicTrack? track;

  bool get hasTrack => track != null;
}

class PlaybackController {
  PlaybackController._() {
    _player.onPlayerStateChanged.listen((state) {
      debugPrint('[PlaybackController] onPlayerStateChanged: $state');
      if (state == PlayerState.stopped) {
        _setNowPlaying(null);
      }
    });
    _player.onPlayerComplete.listen((_) {
      debugPrint('[PlaybackController] onPlayerComplete: track finished');
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
  final YouTubeFallback _youtubeFallback = YouTubeFallback();
  final Set<String> _downloadingSongs = {};
  bool _isPlayingTrack = false;

  // Expose YouTube fallback for UI integration
  YouTubeFallback get youtubeFallback => _youtubeFallback;
  final ValueNotifier<Set<String>> downloadingSongs =
      ValueNotifier<Set<String>>({});

  Stream<void> get onPlayerComplete => _player.onPlayerComplete;

  // Queue state
  List<MusicTrack> _queue = [];
  int _currentQueueIndex = -1;
  bool _isQueuePlaying = false;
  
  // YouTube fallback settings - exposed directly as it's a simple field
  bool useYouTubeFallback = true;
  
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
    debugPrint('[PlaybackController] setQueue: queue.length=${queue.length}, startIndex=$startIndex');
    _queue = List.from(queue);
    _currentQueueIndex = startIndex >= 0 && startIndex < _queue.length ? startIndex : -1;
    debugPrint('[PlaybackController] setQueue: _currentQueueIndex set to $_currentQueueIndex');
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
    debugPrint('[PlaybackController] playQueue: _queue.length=${_queue.length}, startIndex=$startIndex');
    if (_queue.isEmpty) {
      debugPrint('[PlaybackController] playQueue: queue is empty, returning');
      return;
    }
    
    if (startIndex < 0 || startIndex >= _queue.length) {
      debugPrint('[PlaybackController] playQueue: adjusting startIndex to 0');
      startIndex = 0;
    }
    
    _currentQueueIndex = startIndex;
    _isQueuePlaying = true;
    debugPrint('[PlaybackController] playQueue: _currentQueueIndex=$_currentQueueIndex, _isQueuePlaying=$_isQueuePlaying');
    _queueIndexController.add(_currentQueueIndex);
    _queuePlayingController.add(_isQueuePlaying);
    
    await _playCurrentQueueTrack();
  }

  // Play the track at the current queue index
  Future<void> _playCurrentQueueTrack() async {
    debugPrint('[PlaybackController] _playCurrentQueueTrack: _currentQueueIndex=$_currentQueueIndex, _queue.length=${_queue.length}');
    
    // Prevent concurrent playback attempts
    if (_isPlayingTrack) {
      debugPrint('[PlaybackController] _playCurrentQueueTrack: Already playing a track, skipping');
      return;
    }
    
    if (_currentQueueIndex < 0 || _currentQueueIndex >= _queue.length) {
      debugPrint('[PlaybackController] _playCurrentQueueTrack: index out of bounds');
      return;
    }
    
    final track = _queue[_currentQueueIndex];
    debugPrint('[PlaybackController] _playCurrentQueueTrack: track=${track.id}, title=${track.title}');
    
    String streamUrl;
    if (_getStreamUrlSync != null) {
      streamUrl = _getStreamUrlSync!(track.id);
      debugPrint('[PlaybackController] _playCurrentQueueTrack: got streamUrl from sync provider: $streamUrl');
    } else if (_getStreamUrlAsync != null) {
      streamUrl = await _getStreamUrlAsync!(track.id);
      debugPrint('[PlaybackController] _playCurrentQueueTrack: got streamUrl from async provider: $streamUrl');
    } else {
      debugPrint('[PlaybackController] _playCurrentQueueTrack: No stream URL provider set for queue playback');
      return;
    }
    
    try {
      _isPlayingTrack = true;
      debugPrint('[PlaybackController] _playCurrentQueueTrack: _isPlayingTrack set to true');
      debugPrint('[PlaybackController] _playCurrentQueueTrack: calling playTrackWithFallback');
      await playTrackWithFallback(track: track, streamUrl: streamUrl);
      debugPrint('[PlaybackController] _playCurrentQueueTrack: playTrackWithFallback completed');
    } catch (e) {
      debugPrint('[PlaybackController] _playCurrentQueueTrack: Failed to play queue track (with fallback): $e');
      // Try to play next track if available
      if (_isQueuePlaying && _currentQueueIndex + 1 < _queue.length) {
        _currentQueueIndex++;
        _queueIndexController.add(_currentQueueIndex);
        unawaited(_playCurrentQueueTrack());
      }
    } finally {
      _isPlayingTrack = false;
      debugPrint('[PlaybackController] _playCurrentQueueTrack: _isPlayingTrack set to false');
    }
  }

  // Handle track completion - play next track automatically
  Future<void> _handleTrackComplete() async {
    debugPrint('[PlaybackController] _handleTrackComplete: START - _isQueuePlaying=$_isQueuePlaying, _currentQueueIndex=$_currentQueueIndex, _queue.length=${_queue.length}');
    if (!_isQueuePlaying) {
      debugPrint('[PlaybackController] _handleTrackComplete: NOT playing queue, returning');
      return;
    }
    
    // Move to next track
    _currentQueueIndex++;
    debugPrint('[PlaybackController] _handleTrackComplete: incremented index from ${_currentQueueIndex - 1} to $_currentQueueIndex');
    
    if (_currentQueueIndex >= _queue.length) {
      // Queue ended
      debugPrint('[PlaybackController] _handleTrackComplete: queue ended');
      _isQueuePlaying = false;
      _currentQueueIndex = -1;
      _queueIndexController.add(_currentQueueIndex);
      _queuePlayingController.add(_isQueuePlaying);
      return;
    }
    
    _queueIndexController.add(_currentQueueIndex);
    debugPrint('[PlaybackController] _handleTrackComplete: calling _playCurrentQueueTrack for index $_currentQueueIndex');
    await _playCurrentQueueTrack();
    debugPrint('[PlaybackController] _handleTrackComplete: COMPLETE');
  }

  // Manually play next track
  Future<void> playNext() async {
    debugPrint('[PlaybackController] playNext: START - _isQueuePlaying=$_isQueuePlaying, _queue.length=${_queue.length}, _currentQueueIndex=$_currentQueueIndex');
    if (!_isQueuePlaying && _queue.isNotEmpty) {
      debugPrint('[PlaybackController] playNext: not currently playing, starting from current position');
      // If not currently playing, start from beginning or current position
      if (_currentQueueIndex < 0) {
        _currentQueueIndex = 0;
        debugPrint('[PlaybackController] playNext: _currentQueueIndex was < 0, set to 0');
      }
      _isQueuePlaying = true;
      _queuePlayingController.add(_isQueuePlaying);
    }
    
    if (_isQueuePlaying && _currentQueueIndex + 1 < _queue.length) {
      debugPrint('[PlaybackController] playNext: incrementing _currentQueueIndex from $_currentQueueIndex to ${_currentQueueIndex + 1}');
      _currentQueueIndex++;
      _queueIndexController.add(_currentQueueIndex);
      await _playCurrentQueueTrack();
      debugPrint('[PlaybackController] playNext: COMPLETE');
    } else if (_isQueuePlaying) {
      // Reached end of queue
      debugPrint('[PlaybackController] playNext: reached end of queue');
      _isQueuePlaying = false;
      _queuePlayingController.add(_isQueuePlaying);
    } else {
      debugPrint('[PlaybackController] playNext: Queue is empty or not playing');
    }
    debugPrint('[PlaybackController] playNext: FINISHED');
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

  /// Play a track with YouTube fallback support.
  /// If the provided streamUrl fails, this will attempt to find and play
  /// a matching YouTube video (if YouTube fallback is enabled).
  Future<void> playTrackWithFallback({
    required MusicTrack track,
    required String streamUrl,
  }) async {
    debugPrint('[PlaybackController] playTrackWithFallback: START for track ${track.id}');
    try {
      await playTrack(track: track, streamUrl: streamUrl);
      debugPrint('[PlaybackController] playTrackWithFallback: SUCCESS for track ${track.id}');
    } catch (e) {
      debugPrint('[PlaybackController] playTrackWithFallback: FAILED for track ${track.id}, error: $e');
      
      // Try YouTube fallback when local file is unavailable
      if (!useYouTubeFallback) {
        debugPrint('[PlaybackController] playTrackWithFallback: YouTube fallback disabled, rethrowing');
        rethrow;
      }
      
      debugPrint('[PlaybackController] playTrackWithFallback: Attempting YouTube fallback for ${track.artist} - ${track.title}');
      
      try {
        // Search YouTube for a matching video and play it
        final youtubeUrl = await _youtubeFallback.searchAndPlay(
          track.artist,
          track.title,
        );
        
        if (youtubeUrl != null) {
          debugPrint('[PlaybackController] playTrackWithFallback: YouTube fallback SUCCESS for ${track.artist} - ${track.title}');
          // Consider the fallback successful - YouTube is now playing
          return; // Success
        } else {
          debugPrint('[PlaybackController] playTrackWithFallback: YouTube fallback - No matching video found for ${track.artist} - ${track.title}');
        }
      } catch (e) {
        debugPrint('[PlaybackController] playTrackWithFallback: YouTube fallback FAILED: $e');
      }
      
      // If YouTube fallback also fails, rethrow the original error
      debugPrint('[PlaybackController] playTrackWithFallback: All fallback options exhausted, rethrowing');
      rethrow;
    }
  }

  Future<void> playTrack({
    required MusicTrack track,
    required String streamUrl,
  }) async {
    debugPrint('[PlaybackController] playTrack: START, track.id=${track.id}, track.title=${track.title}');
    
    // Stop current playback to ensure clean state before setting new source
    debugPrint('[PlaybackController] playTrack: Stopping current playback');
    try {
      await _player.stop();
      debugPrint('[PlaybackController] playTrack: Player stopped');
    } catch (e) {
      debugPrint('[PlaybackController] playTrack: stop() error: $e');
    }
    
    // Critical delay to allow GStreamer to fully release the old source on Linux
    debugPrint('[PlaybackController] playTrack: Waiting 500ms for GStreamer cleanup');
    await Future.delayed(const Duration(milliseconds: 500));
    debugPrint('[PlaybackController] playTrack: GStreamer cleanup complete');
    
    // Check if song is cached
    final cachedPath = await _cache.getCachedFilePath(track.id);
    debugPrint('[PlaybackController] playTrack: cachedPath=$cachedPath');
    
    if (cachedPath != null) {
      // Verify cached file is valid (non-empty) before attempting to play
      final cachedFile = File(cachedPath);
      final exists = await cachedFile.exists();
      final length = await cachedFile.length();
      debugPrint('[PlaybackController] playTrack: cached file exists=$exists, length=$length');
      
      if (exists && length > 0) {
        // Play from cache - explicitly set source then resume
        debugPrint('[PlaybackController] playTrack: Playing from cache: $cachedPath');
        await _player.setSource(DeviceFileSource(cachedPath));
        await _player.resume();
        // Set now playing state immediately after playback starts
        _setNowPlaying(track);
        // Show notification (don't await, as it may fail on non-Android platforms)
        unawaited(_showNotification(track));
        return;
      } else {
        // Cached file is empty/invalid, treat as not cached
        debugPrint('[PlaybackController] playTrack: Cached file for ${track.id} is empty or invalid, will re-download');
        // Remove from cache
        await _cache.removeFromCache(track.id);
      }
    }
    
    // On Linux and other non-mobile platforms, UrlSource doesn't work reliably
    // So we need to download first, then play
    final isMobile = Platform.isAndroid || Platform.isIOS;
    
    if (!isMobile) {
      // For Linux, Windows, macOS, Web: download first, then play
      debugPrint('[PlaybackController] playTrack: Downloading track ${track.id} before playback');
      // Download and cache synchronously before playing
      final downloadedPath = await _cache.downloadAndCache(track.id, streamUrl);
      final downloadedFile = File(downloadedPath);
      if (await downloadedFile.exists() && await downloadedFile.length() > 0) {
        debugPrint('[PlaybackController] playTrack: Download complete, playing from: $downloadedPath');
        await _player.setSource(DeviceFileSource(downloadedPath));
        await _player.resume();
        // Set now playing state immediately after playback starts
        _setNowPlaying(track);
        // Show notification (don't await, as it may fail on non-Android platforms)
        unawaited(_showNotification(track));
        return;
      } else {
        // Download failed, clean up and fall through to error
        debugPrint('[PlaybackController] playTrack: Download failed, removing from cache');
        await _cache.removeFromCache(track.id);
        throw Exception('Downloaded file for ${track.id} is empty or invalid');
      }
    }
    
    // For Android and iOS: start streaming and download in background
    debugPrint('[PlaybackController] playTrack: Streaming from URL: $streamUrl');
    await _player.setSource(UrlSource(streamUrl));
    await _player.resume();
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
    debugPrint('[PlaybackController] stop: Stopping playback');
    await _player.stop();
    debugPrint('[PlaybackController] stop: Player stopped');
    // Hide notification (don't await, as it may fail on non-Android platforms)
    unawaited(_hideNotification());
    _setNowPlaying(null);
    debugPrint('[PlaybackController] stop: Now playing set to null');
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
  
  /// Dispose of resources, including YouTube fallback client.
  /// Call this when the controller is no longer needed.
  void dispose() {
    _youtubeFallback.dispose();
    _player.dispose();
    _queueController.close();
    _queueIndexController.close();
    _queuePlayingController.close();
  }
}
