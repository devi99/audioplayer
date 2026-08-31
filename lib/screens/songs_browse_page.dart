import 'package:flutter/material.dart';

import '../models/music_track.dart';
import '../services/music_library_api.dart';
import '../services/playback_controller.dart';
import 'shared_library_widgets.dart';

class SongsBrowsePage extends StatefulWidget {
  const SongsBrowsePage({super.key, required this.api});

  final MusicLibraryApi api;

  @override
  State<SongsBrowsePage> createState() => _SongsBrowsePageState();
}

class _SongsBrowsePageState extends State<SongsBrowsePage> {
  static const int _pageSize = 20;

  late final Future<List<MusicTrack>> _songsFuture;
  int _pageNumber = 1;

  @override
  void initState() {
    super.initState();
    _songsFuture = widget.api.fetchSongs(pageSize: 0);
  }

  Future<void> _playSong(MusicTrack song) async {
    final hasPlayableSource = (song.filePath ?? '').trim().isNotEmpty;
    if (!hasPlayableSource) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to play "${song.title}" — no stream is available.'),
        ),
      );
      return;
    }

    try {
      await PlaybackController.instance.playTrack(
        track: song,
        streamUrl: widget.api.streamSongUrl(song.id),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to play "${song.title}". The stream is unavailable.'),
        ),
      );
    }
  }

  void _loadPage(int nextPage) {
    setState(() {
      _pageNumber = nextPage;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<List<MusicTrack>>(
      future: _songsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return LibraryErrorState(
            message: 'Unable to load songs',
            details: snapshot.error.toString(),
          );
        }

        final songs = snapshot.data ?? const <MusicTrack>[];
        final totalPages = (songs.length / _pageSize).ceil();
        final startIndex = (_pageNumber - 1) * _pageSize;
        final currentSongs = songs
            .skip(startIndex)
            .take(_pageSize)
            .toList(growable: false);

        if (_pageNumber > totalPages && totalPages > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _pageNumber = totalPages);
            }
          });
        }

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Songs',
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                '${songs.length} songs in your library',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              if (songs.length > _pageSize)
                Row(
                  children: <Widget>[
                    TextButton.icon(
                      onPressed: _pageNumber > 1
                          ? () => _loadPage(_pageNumber - 1)
                          : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                      label: const Text('Previous'),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          'Page $_pageNumber of $totalPages',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _pageNumber < totalPages
                          ? () => _loadPage(_pageNumber + 1)
                          : null,
                      icon: const Icon(Icons.chevron_right_rounded),
                      label: const Text('Next'),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: currentSongs.length,
                  separatorBuilder: (context, index) => const Divider(
                    height: 1,
                    color: Colors.transparent,
                  ),
                  itemBuilder: (context, index) {
                    final song = currentSongs[index];
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: <Widget>[
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.music_note_rounded,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  song.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  song.starDisplay(),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: (song.filePath ?? '').trim().isEmpty
                                ? null
                                : () => _playSong(song),
                            icon: const Icon(Icons.play_arrow_rounded),
                            tooltip: (song.filePath ?? '').trim().isEmpty
                                ? 'Unavailable'
                                : 'Play',
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
