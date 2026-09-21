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

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _TagEditorBottomSheet(
        song: song,
        availableTags: availableTags,
        existingTags: tagsForSong(song),
        onTagsAdded: () async {
          // Refresh song tags after dialog closes
          if (!mounted) return;
          try {
            final updatedTags = await api.fetchSongTags(song.id);
            if (!mounted) return;
            setState(() {
              songTagsById[song.id] = updatedTags;
            });
          } catch (_) {
            // If refresh fails, the UI will still show the existing cached tags
          }
        },
        api: api,
        onUpdateState: () {
          if (mounted) {
            setState(() {});
          }
        },
      ),
    );
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

/// Stateful bottom sheet for adding multiple tags to a song.
class _TagEditorBottomSheet extends StatefulWidget {
  final MusicTrack song;
  final List<TagOption> availableTags;
  final List<String> existingTags;
  final VoidCallback onTagsAdded;
  final MusicLibraryApi api;
  final VoidCallback onUpdateState;

  const _TagEditorBottomSheet({
    required this.song,
    required this.availableTags,
    required this.existingTags,
    required this.onTagsAdded,
    required this.api,
    required this.onUpdateState,
  });

  @override
  State<_TagEditorBottomSheet> createState() => _TagEditorBottomSheetState();
}

class _TagEditorBottomSheetState extends State<_TagEditorBottomSheet> {
  final Set<int> _addedTagIds = <int>{};
  final Set<int> _addingTagIds = <int>{};
  List<String> _currentSongTags = [];

  @override
  void initState() {
    super.initState();
    _currentSongTags = List.from(widget.existingTags);
  }

  Set<String> get _allAssignedTagNames => _currentSongTags
      .map((tag) => tag.trim().toLowerCase())
      .toSet();

  Future<void> _addTag(TagOption tagOption) async {
    final tagNameLower = tagOption.name.toLowerCase();
    
    if (_allAssignedTagNames.contains(tagNameLower) || 
        _addedTagIds.contains(tagOption.id)) {
      return;
    }

    if (!mounted) return;
    setState(() {
      _addingTagIds.add(tagOption.id);
    });

    try {
      await widget.api.addTagToSong(songId: widget.song.id, tagId: tagOption.id);
      
      if (!mounted) return;
      setState(() {
        _addedTagIds.add(tagOption.id);
        _currentSongTags.add(tagOption.name);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added tag "${tagOption.name}".')),
      );
      
      widget.onUpdateState();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to add tag: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _addingTagIds.remove(tagOption.id);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sortedTags = widget.availableTags.toList(growable: false)
      ..sort((left, right) => left.name.compareTo(right.name));

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Add tags to "${widget.song.title}"',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                TextButton(
                  onPressed: () {
                    widget.onTagsAdded();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Done'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: sortedTags.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final option = sortedTags[index];
                  final isAssigned = _allAssignedTagNames.contains(option.name.toLowerCase());
                  final isAdding = _addingTagIds.contains(option.id);
                  final isNewlyAdded = _addedTagIds.contains(option.id);
                  final isDisabled = isAssigned || isAdding || isNewlyAdded;

                  return ListTile(
                    dense: true,
                    enabled: !isDisabled,
                    title: Text(option.name),
                    subtitle: isAssigned
                        ? Text('Already assigned', style: theme.textTheme.bodySmall)
                        : isNewlyAdded
                            ? Text('Added', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary))
                            : null,
                    trailing: isAdding
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : isAssigned || isNewlyAdded
                            ? const Icon(Icons.check_circle_outline_rounded)
                            : const Icon(Icons.add_circle_outline_rounded),
                    onTap: isDisabled ? null : () => _addTag(option),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
