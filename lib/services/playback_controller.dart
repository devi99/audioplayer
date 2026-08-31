import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../models/music_track.dart';

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

  final AudioPlayer _player = AudioPlayer();
  final ValueNotifier<NowPlayingState> nowPlaying =
      ValueNotifier<NowPlayingState>(const NowPlayingState());

  Stream<void> get onPlayerComplete => _player.onPlayerComplete;

  Future<void> playTrack({
    required MusicTrack track,
    required String streamUrl,
  }) async {
    await _player.stop();
    await _player.play(UrlSource(streamUrl));
    _setNowPlaying(track);
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
}
