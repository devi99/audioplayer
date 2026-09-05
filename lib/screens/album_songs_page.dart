import 'dart:async';

import 'package:flutter/material.dart';

import '../models/library_entities.dart';
import '../models/music_track.dart';
import '../services/music_library_api.dart';
import 'shared_library_widgets.dart';
import 'song_management_mixin.dart';

class AlbumSongsPage extends StatefulWidget {
  const AlbumSongsPage({super.key, required this.album, required this.api});

  final AlbumSummary album;
  final MusicLibraryApi api;

  @override
  State<AlbumSongsPage> createState() => _AlbumSongsPageState();
}

class _AlbumSongsPageState extends State<AlbumSongsPage> with SongManagementMixin {
  late final Future<List<MusicTrack>> _songsFuture;

  @override
  MusicLibraryApi get api => widget.api;

  @override
  void initState() {
    super.initState();
    _songsFuture = api.fetchAlbumSongs(widget.album.id);
    unawaited(primeTagsCatalog());
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

            WidgetsBinding.instance.addPostFrameCallback((_) {
              unawaited(ensureSongTagsLoaded(songs));
            });

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
                        future: api.lookupAlbumImage(widget.album),
                        builder: (context, imageSnapshot) {
                          return SizedBox(
                            width: 64,
                            height: 64,
                            child: LibraryArtworkFrame(
                              imageUrl: imageSnapshot.data,
                              fallbackIcon: Icons.album_rounded,
                              gradient: const LinearGradient(
                                colors: <Color>[
                                  Color(0xFF6E4F2B),
                                  Color(0xFF1D1720)
                                ],
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
                        final hasFilePath =
                            (song.filePath ?? '').trim().isNotEmpty;
                        final songTags = tagsForSong(song);
                        final rankOrder = rankOrderForSong(song);
                        final selectedTier = tierFromRankOrder(rankOrder);
                        final selectedTierLabel = selectedTier == null
                          ? 'Select rank'
                          : 'Tier $selectedTier';
                        final isUpdatingTag =
                            updatingTagsForSongIds.contains(song.id);
                        final isUpdatingTier =
                            updatingRankForSongIds.contains(song.id);
                        final hasLoadedTags =
                            songTagsById.containsKey(song.id);
                        final isLoadingSongTags =
                            loadingTagsForSongIds.contains(song.id);

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 12,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface
                                .withValues(alpha: 0.82),
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
                                          ?.copyWith(
                                              fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      song.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      !hasLoadedTags && isLoadingSongTags
                                          ? 'Tags: loading...'
                                          : songTags.isEmpty
                                              ? 'Tags: none'
                                              : 'Tags: ${songTags.join(', ')}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      selectedTier == null
                                          ? 'Selected tier: Select rank'
                                          : 'Selected tier: Tier $selectedTier (rankOrder ${rankOrder.toStringAsFixed(2)})',
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: <Widget>[
                                  PopupMenuButton<int>(
                                    enabled: !isUpdatingTier,
                                    tooltip: 'Set tier',
                                    onSelected: (tier) {
                                      unawaited(setSongTier(song, tier));
                                    },
                                    itemBuilder: (context) =>
                                        <PopupMenuEntry<int>>[
                                      for (var tier = 1; tier <= 5; tier++)
                                        PopupMenuItem<int>(
                                          value: tier,
                                          child: Text('Tier $tier'),
                                        ),
                                    ],
                                    child: Chip(
                                      label: Text(selectedTierLabel),
                                      avatar: isUpdatingTier
                                          ? SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color:
                                                    theme.colorScheme.primary,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.keyboard_arrow_down_rounded,
                                              size: 18,
                                            ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: isUpdatingTag
                                        ? null
                                        : () {
                                            unawaited(addTagToSong(song));
                                          },
                                    tooltip: 'Add tag',
                                    icon: isUpdatingTag
                                        ? SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: theme.colorScheme.primary,
                                            ),
                                          )
                                        : const Icon(Icons.sell_outlined),
                                  ),
                                  if (hasFilePath)
                                    IconButton(
                                      onPressed: () => playSong(song),
                                      icon:
                                          const Icon(Icons.play_arrow_rounded),
                                      tooltip: 'Play',
                                    ),
                                ],
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
