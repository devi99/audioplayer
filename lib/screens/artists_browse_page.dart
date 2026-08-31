import 'package:flutter/material.dart';

import '../models/library_entities.dart';
import '../services/music_library_api.dart';
import 'shared_library_widgets.dart';

class ArtistsBrowsePage extends StatelessWidget {
  const ArtistsBrowsePage({super.key, required this.api});

  final MusicLibraryApi api;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<List<ArtistSummary>>(
      future: api.fetchArtists(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return LibraryErrorState(
            message: 'Unable to load artists',
            details: snapshot.error.toString(),
          );
        }

        final artists = snapshot.data ?? const <ArtistSummary>[];

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Artists',
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                '${artists.length} artists in your library',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 260,
                    mainAxisExtent: 290,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                  ),
                  itemCount: artists.length,
                  itemBuilder: (context, index) {
                    return _ArtistCard(artist: artists[index], api: api);
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

class _ArtistCard extends StatelessWidget {
  const _ArtistCard({required this.artist, required this.api});

  final ArtistSummary artist;
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
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: FutureBuilder<String?>(
                  future: api.lookupArtistImage(artist.name),
                  builder: (context, snapshot) {
                    return LibraryArtworkFrame(
                      imageUrl: snapshot.data,
                      fallbackIcon: Icons.person_rounded,
                      gradient: const LinearGradient(
                        colors: <Color>[Color(0xFF294661), Color(0xFF0F1E2F)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              Text(
                artist.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '${artist.albumCount} albums',
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
