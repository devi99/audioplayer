import 'package:flutter/material.dart';

import 'models/music_track.dart';
import 'screens/library_screen.dart';

void main() {
  runApp(const AudioPlayerApp());
}

class AudioPlayerApp extends StatelessWidget {
  const AudioPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final tracks = <MusicTrack>[
      const MusicTrack(
        id: '1',
        title: 'Midnight Echo',
        artist: 'Aster',
        album: 'Night Drive',
        durationSeconds: 245,
        rating: 5,
        tags: ['ambient', 'night-drive'],
      ),
      const MusicTrack(
        id: '2',
        title: 'Blue Skies',
        artist: 'Aster',
        album: 'Daylight',
        durationSeconds: 203,
        rating: 4,
        tags: ['ambient', 'uplift'],
      ),
      const MusicTrack(
        id: '3',
        title: 'Static Bloom',
        artist: 'Brazen',
        album: 'Voltage',
        durationSeconds: 367,
        rating: 2,
        tags: ['techno'],
      ),
    ];

    return MaterialApp(
      title: 'AudioPlayer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: LibraryScreen(tracks: tracks),
    );
  }
}
