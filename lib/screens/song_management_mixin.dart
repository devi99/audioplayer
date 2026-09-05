import 'package:flutter/material.dart';

import '../models/music_track.dart';
import '../services/music_library_api.dart';
import '../services/playback_controller.dart';

/// A mixin that provides shared song management functionality.
///
/// Shared state variables (all public for access by state classes):
/// - availableTags, isLoadingAvailableTags
/// - updatingTagsForSongIds, updatingRankForSongIds
/// - loadingTagsForSongIds, songTagsById, rankOrderBySongId
///
/// Shared methods:
/// - primeTagsCatalog(), ensureTagsCatalogLoaded()
/// - tagsForSong(), ensureSongTagsLoaded()
/// - rankOrderForSong(), tierFromRankOrder(), rankOrderForTier()
/// - addTagToSong(), setSongTier(), playSong()
///
/// Usage:
///   class _MyState extends State<MyWidget> with SongManagementMixin {
///     @override
///     MusicLibraryApi get api => widget.api;
///   }
mixin SongManagementMixin<T extends StatefulWidget> on State<T> {
  // Abstract getter to access the API from the widget
  MusicLibraryApi get api;

  // State for tags management
  List<TagOption> availableTags = const <TagOption>[];
  bool isLoadingAvailableTags = false;
  final Set<String> updatingTagsForSongIds = <String>{};
  final Set<String> updatingRankForSongIds = <String>{};
  final Set<String> loadingTagsForSongIds = <String>{};
  final Map<String, List<String>> songTagsById = <String, List<String>>{};
  final Map<String, double> rankOrderBySongId = <String, double>{};

  Future<void> primeTagsCatalog() async {
    try {
      final tags = await api.fetchTags();
      if (!mounted) {
        return;
      }
      setState(() {
        availableTags = tags;
      });
    } catch (_) {
      // Ignore warm-up failures
    }
  }

  Future<bool> ensureTagsCatalogLoaded() async {
    if (availableTags.isNotEmpty) {
      return true;
    }
    if (isLoadingAvailableTags) {
      return false;
    }
    setState(() {
      isLoadingAvailableTags = true;
    });
    try {
      final tags = await api.fetchTags();
      if (!mounted) {
        return false;
      }
      setState(() {
        availableTags = tags;
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
          isLoadingAvailableTags = false;
        });
      }
    }
  }

  List<String> tagsForSong(MusicTrack song) {
    return songTagsById[song.id] ?? song.tags;
  }

  Future<void> ensureSongTagsLoaded(Iterable<MusicTrack> songs) async {
    final missingSongIds = songs
        .map((song) => song.id)
        .where(
          (songId) =>
              songId.isNotEmpty &&
              !songTagsById.containsKey(songId) &&
              !loadingTagsForSongIds.contains(songId),
        )
        .toList(growable: false);

    if (missingSongIds.isEmpty || !mounted) {
      return;
    }

    setState(() {
      loadingTagsForSongIds.addAll(missingSongIds);
    });

    for (final songId in missingSongIds) {
      List<String> tags;
      try {
        tags = await api.fetchSongTags(songId);
      } catch (_) {
        tags = const <String>[];
      }
      if (!mounted) {
        return;
      }
      setState(() {
        songTagsById[songId] = tags;
        loadingTagsForSongIds.remove(songId);
      });
    }
  }

  double rankOrderForSong(MusicTrack song) {
    return rankOrderBySongId[song.id] ?? song.rankOrder;
  }

  int? tierFromRankOrder(double rankOrder) {
    if (rankOrder >= 0 && rankOrder < 1) return 1;
    if (rankOrder >= 1 && rankOrder < 2) return 2;
    if (rankOrder >= 2 && rankOrder < 3) return 3;
    if (rankOrder >= 3 && rankOrder < 4) return 4;
    if (rankOrder >= 4 && rankOrder <= 5) return 5;
    return null;
  }

  double rankOrderForTier(int tier) {
    switch (tier) {
      case 1: return 0;
      case 2: return 1;
      case 3: return 2;
      case 4: return 3;
      case 5: return 4;
      default: return 0;
    }
  }

  Future<void> addTagToSong(MusicTrack song) async {
    if (updatingTagsForSongIds.contains(song.id)) {
      return;
    }
    final loaded = await ensureTagsCatalogLoaded();
    if (!loaded || availableTags.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tags available to add.')),
      );
      return;
    }
    final existingTagNames =
        tagsForSong(song).map((tag) => tag.trim().toLowerCase()).toSet();

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

    setState(() {
      updatingTagsForSongIds.add(song.id);
    });
    try {
      await api.addTagToSong(songId: song.id, tagId: selectedTag.id);
      final updatedTags = await api.fetchSongTags(song.id);
      if (!mounted) return;
      setState(() {
        songTagsById[song.id] = updatedTags;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added tag "${selectedTag.name}".')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to add tag: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          updatingTagsForSongIds.remove(song.id);
        });
      }
    }
  }

  Future<void> setSongTier(MusicTrack song, int tier) async {
    if (updatingRankForSongIds.contains(song.id)) {
      return;
    }
    setState(() {
      updatingRankForSongIds.add(song.id);
    });
    try {
      final rankOrder = rankOrderForTier(tier);
      await api.updateSongRankOrder(songId: song.id, rankOrder: rankOrder);
      if (!mounted) return;
      setState(() {
        rankOrderBySongId[song.id] = rankOrder;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated "${song.title}" to Tier $tier.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to update tier: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          updatingRankForSongIds.remove(song.id);
        });
      }
    }
  }

  Future<void> playSong(MusicTrack song) async {
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
        streamUrl: api.streamSongUrl(song.id),
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
}
