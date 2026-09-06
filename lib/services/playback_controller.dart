import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
    });
  }

  static final PlaybackController instance = PlaybackController._();
  static const MethodChannel _channel = MethodChannel('com.example.audioplayer/notification');

  final AudioPlayer _player = AudioPlayer()
    ..setReleaseMode(ReleaseMode.stop);
  final ValueNotifier<NowPlayingState> nowPlaying =
      ValueNotifier<NowPlayingState>(const NowPlayingState());
  final SongCache _cache = SongCache();
  final Set<String> _downloadingSongs = {};
  final ValueNotifier<Set<String>> downloadingSongs =
      ValueNotifier<Set<String>>({});

  Stream<void> get onPlayerComplete => _player.onPlayerComplete;

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
    try {
      await _channel.invokeMethod('showNotification', {
        'title': track.title,
        'artist': track.artist,
        'isPlaying': true,
      });
    } catch (e) {
      // On non-Android platforms, notifications are not supported
      debugPrint('Failed to show notification: $e');
    }
  }

  Future<void> _hideNotification() async {
    try {
      await _channel.invokeMethod('hideNotification');
    } catch (e) {
      // On non-Android platforms, notifications are not supported
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
