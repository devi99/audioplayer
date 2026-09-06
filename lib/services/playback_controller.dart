import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

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
      _setNowPlaying(track);
      return;
    }
    
    // Not cached - start streaming and download in background
    await _player.stop();
    await _player.play(UrlSource(streamUrl));
    _setNowPlaying(track);
    
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
    _setNowPlaying(null);
  }

  void _setNowPlaying(MusicTrack? track) {
    final currentTrackId = nowPlaying.value.track?.id;
    final nextTrackId = track?.id;
    if (currentTrackId == nextTrackId) {
      return;
    }
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
