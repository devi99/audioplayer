import 'dart:async';

import 'package:flutter/material.dart';

import '../models/music_track.dart';
import '../services/music_library_api.dart';
import '../services/playback_controller.dart';
import 'albums_browse_page.dart';
import 'artists_browse_page.dart';
import 'library_navigation_pane.dart';
import 'play_screen.dart';
import 'songs_browse_page.dart';

class LibraryScreen extends StatefulWidget {
  LibraryScreen({super.key, MusicLibraryApi? api})
      : api = api ?? MusicLibraryApi();

  final MusicLibraryApi api;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  static const double _collapsedPaneWidth = 84;
  static const double _expandedPaneWidth = 252;

  double _paneWidth = _expandedPaneWidth;
  LibrarySection _selectedSection = LibrarySection.artists;

  bool get _collapsed => _paneWidth <= 108;

  void _selectSection(LibrarySection section) {
    setState(() {
      _selectedSection = section;
    });
  }

  void _updatePaneWidth(double delta) {
    setState(() {
      _paneWidth =
          (_paneWidth + delta).clamp(_collapsedPaneWidth, _expandedPaneWidth);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color(0xFF09111D),
              Color(0xFF0B1726),
              Color(0xFF111826),
            ],
          ),
        ),
        child: SafeArea(
          child: Row(
            children: <Widget>[
              LibraryNavigationPane(
                paneWidth: _paneWidth,
                selectedSection: _selectedSection,
                collapsed: _collapsed,
                onSelectSection: _selectSection,
                onResize: (details) => _updatePaneWidth(details.delta.dx),
              ),
              Expanded(
                child: Column(
                  children: <Widget>[
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: switch (_selectedSection) {
                          LibrarySection.artists => ArtistsBrowsePage(
                              key: const ValueKey('artists'),
                              api: widget.api,
                            ),
                          LibrarySection.albums => AlbumsBrowsePage(
                              key: const ValueKey('albums'),
                              api: widget.api,
                            ),
                          LibrarySection.songs => SongsBrowsePage(
                              key: const ValueKey('songs'),
                              api: widget.api,
                            ),
                          LibrarySection.play => PlayScreen(
                              key: const ValueKey('play'),
                              api: widget.api,
                            ),
                        },
                      ),
                    ),
                    ValueListenableBuilder<NowPlayingState>(
                      valueListenable: PlaybackController.instance.nowPlaying,
                      builder: (context, nowPlayingState, _) {
                        final track = nowPlayingState.track;
                        if (track == null) {
                          return const SizedBox.shrink();
                        }
                        return _NowPlayingBar(track: track);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NowPlayingBar extends StatelessWidget {
  const _NowPlayingBar({required this.track});

  final MusicTrack track;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = PlaybackController.instance;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        children: <Widget>[
          IconButton.filled(
            onPressed: () {
              unawaited(controller.stop());
            },
            icon: const Icon(Icons.stop_rounded),
            tooltip: 'Stop',
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${track.artist} — ${track.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
