import 'dart:async';

import 'package:flutter/material.dart';

import '../models/library_entities.dart';
import '../services/music_library_api.dart';
import 'album_songs_page.dart';
import 'shared_library_widgets.dart';

class ArtistAlbumsSongsPage extends StatefulWidget {
  const ArtistAlbumsSongsPage(
      {super.key, required this.artist, required this.api});

  final ArtistSummary artist;
  final MusicLibraryApi api;

  @override
  State<ArtistAlbumsSongsPage> createState() => _ArtistAlbumsSongsPageState();
}

class _ArtistAlbumsSongsPageState extends State<ArtistAlbumsSongsPage> {
  late final Future<List<AlbumSummary>> _albumsFuture;

  @override
  void initState() {
    super.initState();
    _albumsFuture = widget.api.fetchArtistAlbums(widget.artist.id);
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
        title: Text(widget.artist.name),
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
        child: FutureBuilder<List<AlbumSummary>>(
          future: _albumsFuture,
          builder: (context, snapshot) {
          return FutureBuilder<List<AlbumSummary>>(
              future: _albumsFuture,
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

                final albums = (snapshot.data ?? const <AlbumSummary>[])
                  .toList(growable: false)
                  ..sort((left, right) => left.title.compareTo(right.title));
                final summaryParts = <String>[
                  '${albums.length} albums',
                ];
                final summary = '${summaryParts.join(' ')} in your library';

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
                        summary,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 20),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          return const SizedBox.shrink();
                        },
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 240,
                            mainAxisExtent: 300,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                          ),
                          itemCount: albums.length,
                          itemBuilder: (context, index) {
                            return _AlbumCard(
                                album: albums[index], api: widget.api);
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
          );}
        )
      ),
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
