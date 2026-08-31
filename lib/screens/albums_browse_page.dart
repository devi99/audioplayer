import 'package:flutter/material.dart';

import '../models/library_entities.dart';
import '../models/music_track.dart';
import '../services/music_library_api.dart';
import '../services/playback_controller.dart';
import 'shared_library_widgets.dart';

class AlbumsBrowsePage extends StatelessWidget {
  const AlbumsBrowsePage({super.key, required this.api});

  final MusicLibraryApi api;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<List<AlbumSummary>>(
      future: api.fetchAlbums(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return LibraryErrorState(
            message: 'Unable to load albums',
            details: snapshot.error.toString(),
          );
        }

        final albums = snapshot.data ?? const <AlbumSummary>[];

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Albums',
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                '${albums.length} albums in your library',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 240,
                    mainAxisExtent: 300,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                  ),
                  itemCount: albums.length,
                  itemBuilder: (context, index) {
                    return _AlbumCard(album: albums[index], api: api);
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

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album, required this.api});

  final AlbumSummary album;
  final MusicLibraryApi api;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: theme.colorScheme.surface.withValues(alpha: 0.88),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => AlbumSongsPage(album: album, api: api),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: FutureBuilder<String?>(
                  future: api.lookupAlbumImage(album),
                  builder: (context, snapshot) {
                    return LibraryArtworkFrame(
                      imageUrl: snapshot.data,
                      fallbackIcon: Icons.album_rounded,
                      gradient: const LinearGradient(
                        colors: <Color>[Color(0xFF6E4F2B), Color(0xFF1D1720)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              Text(
                album.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                album.artistName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AlbumSongsPage extends StatefulWidget {
  const AlbumSongsPage({super.key, required this.album, required this.api});

  final AlbumSummary album;
  final MusicLibraryApi api;

  @override
  State<AlbumSongsPage> createState() => _AlbumSongsPageState();
}

class _AlbumSongsPageState extends State<AlbumSongsPage> {
  late final Future<List<MusicTrack>> _songsFuture;

  @override
  void initState() {
    super.initState();
    _songsFuture = widget.api.fetchAlbumSongs(widget.album.id);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
        ),
        title: Text(widget.album.title),
      ),
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
        child: FutureBuilder<List<MusicTrack>>(
          future: _songsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return LibraryErrorState(
                message: 'Unable to load album songs',
                details: snapshot.error.toString(),
              );
            }

            final songs = snapshot.data ?? const <MusicTrack>[];

            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Album songs',
                              style: theme.textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${widget.album.artistName} • ${songs.length} tracks',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FutureBuilder<String?>(
                        future: widget.api.lookupAlbumImage(widget.album),
                        builder: (context, imageSnapshot) {
                          return SizedBox(
                            width: 64,
                            height: 64,
                            child: LibraryArtworkFrame(
                              imageUrl: imageSnapshot.data,
                              fallbackIcon: Icons.album_rounded,
                              gradient: const LinearGradient(
                                colors: <Color>[Color(0xFF6E4F2B), Color(0xFF1D1720)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView.separated(
                      itemCount: songs.length,
                      separatorBuilder: (context, index) => const Divider(
                        height: 1,
                        color: Colors.transparent,
                      ),
                      itemBuilder: (context, index) {
                        final song = songs[index];
                        final hasFilePath = (song.filePath ?? '').trim().isNotEmpty;

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
                                  ],
                                ),
                              ),
                              if (hasFilePath)
                                IconButton(
                                  onPressed: () => _playSong(song),
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  tooltip: 'Play',
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
        ),
      ),
    );
  }
}
