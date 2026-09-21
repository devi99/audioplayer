import '../services/music_library_api.dart';

import '../components/now_playing_bar.dart' show NowPlayingBar;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  Widget _buildContent() {
    return Column(
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
            return NowPlayingBar(track: track, api: widget.api);
          },
        ),
      ],
    );
  }

  Widget _buildDesktopNavigation() {
    return Row(
      children: <Widget>[
        LibraryNavigationPane(
          paneWidth: _paneWidth,
          selectedSection: _selectedSection,
          collapsed: _collapsed,
          onSelectSection: _selectSection,
          onResize: (details) => _updatePaneWidth(details.delta.dx),
        ),
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildAndroidBottomNav() {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: _selectedSection.index,
      onTap: (index) => _selectSection(LibrarySection.values[index]),
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outline_rounded),
          activeIcon: Icon(Icons.person_rounded),
          label: '',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.album_outlined),
          activeIcon: Icon(Icons.album_rounded),
          label: '',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.music_note_outlined),
          activeIcon: Icon(Icons.music_note_rounded),
          label: '',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.play_circle_outline_rounded),
          activeIcon: Icon(Icons.play_circle_rounded),
          label: '',
        ),
      ],
      showSelectedLabels: false,
      showUnselectedLabels: false,
      selectedItemColor: Theme.of(context).colorScheme.primary,
      unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
    );
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
          child: _isAndroid ? _buildContent() : _buildDesktopNavigation(),
        ),
      ),
      bottomNavigationBar: _isAndroid ? _buildAndroidBottomNav() : null,
    );
  }
}
