import 'dart:async';

import 'package:flutter/material.dart';

import '../models/library_entities.dart';
import '../models/music_track.dart';
import '../services/music_library_api.dart';
import '../services/playback_controller.dart';
import 'shared_library_widgets.dart';

class AlbumSongsPage extends StatefulWidget {
  const AlbumSongsPage({super.key, required this.album, required this.api});

  final AlbumSummary album;
  final MusicLibraryApi api;

  @override
  State<AlbumSongsPage> createState() => _AlbumSongsPageState();
}

class _AlbumSongsPageState extends State<AlbumSongsPage> {
  late final Future<List<MusicTrack>> _songsFuture;
  List<TagOption> _availableTags = const <TagOption>[];
  bool _isLoadingAvailableTags = false;
  final Set<String> _updatingTagsForSongIds = <String>{};
  final Set<String> _updatingRankForSongIds = <String>{};
  final Set<String> _loadingTagsForSongIds = <String>{};
  final Map<String, List<String>> _songTagsById = <String, List<String>>{};
  final Map<String, double> _rankOrderBySongId = <String, double>{};

  @override
  void initState() {
    super.initState();
    _songsFuture = widget.api.fetchAlbumSongs(widget.album.id);
    unawaited(_primeTagsCatalog());
  }

  Future<void> _primeTagsCatalog() async {
    try {
      final tags = await widget.api.fetchTags();
      if (!mounted) {
        return;
      }

      setState(() {
        _availableTags = tags;
      });
    } catch (_) {
      // Ignore warm-up failures; explicit actions will show a user-facing message.
    }
  }

  Future<bool> _ensureTagsCatalogLoaded() async {
    if (_availableTags.isNotEmpty) {
      return true;
    }

    if (_isLoadingAvailableTags) {
      return false;
    }

    setState(() {
      _isLoadingAvailableTags = true;
    });

    try {
      final tags = await widget.api.fetchTags();
      if (!mounted) {
        return false;
      }

      setState(() {
        _availableTags = tags;
      });
      return tags.isNotEmpty;
    } catch (error) {
      if (!mounted) {
        return false;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to load available tags: $error')),
      );
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAvailableTags = false;
        });
      }
    }
  }

  List<String> _tagsForSong(MusicTrack song) {
    return _songTagsById[song.id] ?? song.tags;
  }

  Future<void> _ensureSongTagsLoaded(Iterable<MusicTrack> songs) async {
    final missingSongIds = songs
        .map((song) => song.id)
        .where(
          (songId) =>
              songId.isNotEmpty &&
              !_songTagsById.containsKey(songId) &&
              !_loadingTagsForSongIds.contains(songId),
        )
        .toList(growable: false);

    if (missingSongIds.isEmpty || !mounted) {
      return;
    }

    setState(() {
      _loadingTagsForSongIds.addAll(missingSongIds);
    });

    for (final songId in missingSongIds) {
      List<String> tags;
      try {
        tags = await widget.api.fetchSongTags(songId);
      } catch (_) {
        tags = const <String>[];
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _songTagsById[songId] = tags;
        _loadingTagsForSongIds.remove(songId);
      });
    }
  }

  double _rankOrderForSong(MusicTrack song) {
    return _rankOrderBySongId[song.id] ?? song.rankOrder;
  }

  int? _tierFromRankOrder(double rankOrder) {
    if (rankOrder >= 0 && rankOrder < 1) {
      return 1;
    }
    if (rankOrder >= 1 && rankOrder < 2) {
      return 2;
    }
    if (rankOrder >= 2 && rankOrder < 3) {
      return 3;
    }
    if (rankOrder >= 3 && rankOrder < 4) {
      return 4;
    }
    if (rankOrder >= 4 && rankOrder <= 5) {
      return 5;
    }
    return null;
  }

  double _rankOrderForTier(int tier) {
    switch (tier) {
      case 1:
        return 0;
      case 2:
        return 1;
      case 3:
        return 2;
      case 4:
        return 3;
      case 5:
        return 4;
      default:
        return 0;
    }
  }

  Future<void> _addTagToSong(MusicTrack song) async {
    if (_updatingTagsForSongIds.contains(song.id)) {
      return;
    }

    final loaded = await _ensureTagsCatalogLoaded();
    if (!loaded || _availableTags.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tags available to add.')),
      );
      return;
    }

    final existingTagNames =
        _tagsForSong(song).map((tag) => tag.trim().toLowerCase()).toSet();

    final selectedTag = await showModalBottomSheet<TagOption>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        final sortedTags = _availableTags.toList(growable: false)
          ..sort((left, right) => left.name.compareTo(right.name));

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Add tag to "${song.title}"',
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
                            ? Text(
                                'Already assigned',
                                style: theme.textTheme.bodySmall,
                              )
                            : null,
                        trailing: alreadyAssigned
                            ? const Icon(Icons.check_circle_outline_rounded)
                            : const Icon(Icons.add_circle_outline_rounded),
                        onTap: alreadyAssigned
                            ? null
                            : () => Navigator.of(context).pop(option),
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

    if (selectedTag == null) {
      return;
    }

    setState(() {
      _updatingTagsForSongIds.add(song.id);
    });

    try {
      await widget.api.addTagToSong(songId: song.id, tagId: selectedTag.id);
      final updatedTags = await widget.api.fetchSongTags(song.id);
      if (!mounted) {
        return;
      }

      setState(() {
        _songTagsById[song.id] = updatedTags;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added tag "${selectedTag.name}".')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to add tag: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updatingTagsForSongIds.remove(song.id);
        });
      }
    }
  }

  Future<void> _setSongTier(MusicTrack song, int tier) async {
    if (_updatingRankForSongIds.contains(song.id)) {
      return;
    }

    setState(() {
      _updatingRankForSongIds.add(song.id);
    });

    try {
      final rankOrder = _rankOrderForTier(tier);
      await widget.api
          .updateSongRankOrder(songId: song.id, rankOrder: rankOrder);
      if (!mounted) {
        return;
      }

      setState(() {
        _rankOrderBySongId[song.id] = rankOrder;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated "${song.title}" to Tier $tier.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to update tier: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updatingRankForSongIds.remove(song.id);
        });
      }
    }
  }

  Future<void> _playSong(MusicTrack song) async {
    final hasPlayableSource = (song.filePath ?? '').trim().isNotEmpty;
    if (!hasPlayableSource) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Unable to play "${song.title}" — no stream is available.'),
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
          content: Text(
              'Unable to play "${song.title}". The stream is unavailable.'),
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

            WidgetsBinding.instance.addPostFrameCallback((_) {
              unawaited(_ensureSongTagsLoaded(songs));
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
                        future: widget.api.lookupAlbumImage(widget.album),
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
                        final songTags = _tagsForSong(song);
                        final rankOrder = _rankOrderForSong(song);
                        final selectedTier = _tierFromRankOrder(rankOrder);
                        final selectedTierLabel = selectedTier == null
                          ? 'Select rank'
                          : 'Tier $selectedTier';
                        final isUpdatingTag =
                            _updatingTagsForSongIds.contains(song.id);
                        final isUpdatingTier =
                            _updatingRankForSongIds.contains(song.id);
                        final hasLoadedTags =
                            _songTagsById.containsKey(song.id);
                        final isLoadingSongTags =
                            _loadingTagsForSongIds.contains(song.id);

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
                                      unawaited(_setSongTier(song, tier));
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
                                            unawaited(_addTagToSong(song));
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
                                      onPressed: () => _playSong(song),
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
