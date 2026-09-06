import 'dart:async';

import 'package:flutter/material.dart';

import '../models/library_entities.dart';
import '../models/music_track.dart';
import '../services/music_library_api.dart';
import '../services/playback_controller.dart';
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
  late final Future<List<SingleTrackSummary>> _singleTracksFuture;

  @override
  void initState() {
    super.initState();
    _albumsFuture = widget.api.fetchArtistAlbums(widget.artist.id);
    _singleTracksFuture = widget.api.fetchArtistSingleTracks(widget.artist.id);
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
          builder: (context, albumsSnapshot) {
            return FutureBuilder<List<SingleTrackSummary>>(
              future: _singleTracksFuture,
              builder: (context, singleTracksSnapshot) {
                if (albumsSnapshot.connectionState == ConnectionState.waiting ||
                    singleTracksSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (albumsSnapshot.hasError) {
                  return LibraryErrorState(
                    message: 'Unable to load albums',
                    details: albumsSnapshot.error.toString(),
                  );
                }

                if (singleTracksSnapshot.hasError) {
                  return LibraryErrorState(
                    message: 'Unable to load single tracks',
                    details: singleTracksSnapshot.error.toString(),
                  );
                }

                final albums = (albumsSnapshot.data ?? const <AlbumSummary>[])
                  .toList(growable: false)
                  ..sort((left, right) => left.title.compareTo(right.title));
                final singleTracks = (singleTracksSnapshot.data ?? const <SingleTrackSummary>[])
                  .toList(growable: false)
                  ..sort((left, right) => left.title.compareTo(right.title));
                
                final summaryParts = <String>[
                  if (albums.isNotEmpty) '${albums.length} albums',
                  if (singleTracks.isNotEmpty) '${singleTracks.length} single tracks',
                ];
                final summary = summaryParts.isNotEmpty 
                    ? '${summaryParts.join(', ')} in your library' 
                    : 'No content in your library';

                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.artist.name,
                        style: theme.textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        summary,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                      if (albums.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          'Albums',
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 300,
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
                      if (singleTracks.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          'Single tracks',
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: ListView.separated(
                            itemCount: singleTracks.length,
                            separatorBuilder: (context, index) => const Divider(
                              height: 1,
                              color: Colors.transparent,
                            ),
                            itemBuilder: (context, index) {
                              return _SingleTrackCard(
                                  singleTrack: singleTracks[index], 
                                  api: widget.api);
                            },
                          ),
                        ),
                      ],
                      if (albums.isEmpty && singleTracks.isEmpty) ...[
                        const SizedBox(height: 20),
                        Center(
                          child: Text(
                            'No albums or single tracks found for this artist',
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        ),
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

class _SingleTrackCard extends StatefulWidget {
  const _SingleTrackCard({required this.singleTrack, required this.api});

  final SingleTrackSummary singleTrack;
  final MusicLibraryApi api;

  @override
  State<_SingleTrackCard> createState() => _SingleTrackCardState();
}

class _SingleTrackCardState extends State<_SingleTrackCard> {
  bool isLoadingTags = false;
  bool isUpdatingTag = false;
  bool isUpdatingTier = false;
  List<String> tags = const [];
  double? currentRankOrder;
  int? currentTier;

  @override
  void initState() {
    super.initState();
    currentRankOrder = widget.singleTrack.rankOrder;
    currentTier = _getTierFromRankOrder(currentRankOrder);
    _loadTags();
  }

  Future<void> _loadTags() async {
    setState(() {
      isLoadingTags = true;
    });
    try {
      final fetchedTags = await widget.api.fetchSingleTrackTags(widget.singleTrack.id);
      if (mounted) {
        setState(() {
          tags = fetchedTags;
          isLoadingTags = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          isLoadingTags = false;
        });
      }
    }
  }

  Future<void> _addTag() async {
    setState(() {
      isUpdatingTag = true;
    });
    try {
      // Get available tags first
      final availableTags = await widget.api.fetchTags();
      if (!mounted || availableTags.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No tags available to add.')),
          );
        }
        return;
      }

      final existingTagNames = tags.map((tag) => tag.trim().toLowerCase()).toSet();

      final selectedTag = await showModalBottomSheet<TagOption>(
        context: context,
        showDragHandle: true,
        builder: (context) {
          final theme = Theme.of(context);
          final sortedTags = availableTags.toList(growable: false)
            ..sort((left, right) => left.name.compareTo(right.name));
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'Add tag to "${widget.singleTrack.title}"',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: sortedTags.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final option = sortedTags[index];
                        final alreadyAssigned =
                            existingTagNames.contains(option.name.toLowerCase());
                        return ListTile(
                          dense: true,
                          enabled: !alreadyAssigned,
                          title: Text(option.name),
                          subtitle: alreadyAssigned
                              ? Text('Already assigned', style: theme.textTheme.bodySmall)
                              : null,
                          trailing: alreadyAssigned
                              ? const Icon(Icons.check_circle_outline_rounded)
                              : const Icon(Icons.add_circle_outline_rounded),
                          onTap: alreadyAssigned ? null : () => Navigator.of(context).pop(option),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

      if (selectedTag == null) return;

      await widget.api.addTagToSingleTrack(
        singleTrackId: widget.singleTrack.id,
        tagId: selectedTag.id,
      );
      await _loadTags();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added tag "${selectedTag.name}".')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to add tag: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isUpdatingTag = false;
        });
      }
    }
  }

  Future<void> _setTier(int tier) async {
    if (isUpdatingTier) return;
    
    setState(() {
      isUpdatingTier = true;
    });
    
    try {
      final rankOrder = _getRankOrderForTier(tier);
      await widget.api.updateSingleTrackRankOrder(
        singleTrackId: widget.singleTrack.id,
        rankOrder: rankOrder,
      );
      
      if (mounted) {
        setState(() {
          currentRankOrder = rankOrder;
          currentTier = tier;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Updated "${widget.singleTrack.title}" to Tier $tier.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to update tier: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isUpdatingTier = false;
        });
      }
    }
  }

  Future<void> _playTrack() async {
    final hasFilePath = (widget.singleTrack.localFilePath ?? '').trim().isNotEmpty;
    if (!hasFilePath) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to play "${widget.singleTrack.title}" — no stream is available.'),
        ),
      );
      return;
    }
    
    try {
      final musicTrack = MusicTrack(
        id: widget.singleTrack.id.toString(),
        title: widget.singleTrack.title,
        artist: widget.singleTrack.artistName,
        album: '', // Empty album for single tracks
        durationSeconds: 0, // Default duration
        rankOrder: widget.singleTrack.rankOrder ?? -1.0,
        tags: tags,
        filePath: widget.singleTrack.localFilePath,
      );
      
      final streamUrl = widget.api.streamSingleTrackUrl(widget.singleTrack.id);
      await PlaybackController.instance.playTrack(
        track: musicTrack,
        streamUrl: streamUrl,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to play "${widget.singleTrack.title}". The stream is unavailable.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFilePath = (widget.singleTrack.localFilePath ?? '').trim().isNotEmpty;
    final selectedTierLabel = currentTier == null ? 'Select rank' : 'Tier $currentTier';

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
                  widget.singleTrack.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.singleTrack.artistName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isLoadingTags
                      ? 'Tags: loading...'
                      : tags.isEmpty
                          ? 'Tags: none'
                          : 'Tags: ${tags.join(', ')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  currentTier == null
                      ? 'Selected tier: Select rank'
                      : 'Selected tier: Tier $currentTier (rankOrder ${currentRankOrder?.toStringAsFixed(2)})',
                  style: theme.textTheme.bodyMedium?.copyWith(
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
                onSelected: _setTier,
                itemBuilder: (context) => <PopupMenuEntry<int>>[
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
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                        ),
                ),
              ),
              IconButton(
                onPressed: isUpdatingTag ? null : _addTag,
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
                  onPressed: _playTrack,
                  icon: const Icon(Icons.play_arrow_rounded),
                  tooltip: 'Play',
                ),
            ],
          ),
        ],
      ),
    );
  }

  int? _getTierFromRankOrder(double? rankOrder) {
    if (rankOrder == null) return null;
    if (rankOrder >= 0 && rankOrder < 1) return 1;
    if (rankOrder >= 1 && rankOrder < 2) return 2;
    if (rankOrder >= 2 && rankOrder < 3) return 3;
    if (rankOrder >= 3 && rankOrder < 4) return 4;
    if (rankOrder >= 4 && rankOrder <= 5) return 5;
    return null;
  }

  double _getRankOrderForTier(int tier) {
    switch (tier) {
      case 1: return 0;
      case 2: return 1;
      case 3: return 2;
      case 4: return 3;
      case 5: return 4;
      default: return 0;
    }
  }
}
