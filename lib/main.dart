import 'package:flutter/material.dart';

import 'screens/library_screen.dart';
import 'services/music_library_api.dart';

void main() {
  runApp(const AudioPlayerApp());
}

class AudioPlayerApp extends StatelessWidget {
  const AudioPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AudioPlayer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3C8DAD),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF07111C),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: false),
      ),
      home: LibraryScreen(api: MusicLibraryApi()),
    );
  }
}
