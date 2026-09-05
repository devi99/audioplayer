import 'dart:async';

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
  static const Duration _searchDebounceDuration = Duration(milliseconds: 500);

  late final Future<List<MusicTrack>> _songsFuture;
  late final TextEditingController _songFieldController;
  late final FocusNode _songFieldFocusNode;

  int _pageNumber = 1;
  List<TagOption> _availableTags = const <TagOption>[];
  bool _isLoadingAvailableTags = false;
  final Set<String> _updatingTagsForSongIds = <String>{};
  final Set<String> _updatingRankForSongIds = <String>{};
  final Set<String> _loadingTagsForSongIds = <String>{};
  final Map<String, List<String>> _songTagsById = <String, List<String>>{};
  final Map<String, double> _rankOrderBySongId = <String, double>{};

  String _searchQuery = '';
  List<MusicTrack> _searchResults = const <MusicTrack>[];
  bool _isSearching = false;
  Timer? _searchDebounceTimer;

  @override
  void initState() {
    super.initState();
    _songsFuture = widget.api.fetchSongs(pageSize: 0);
    unawaited(_primeTagsCatalog());
    _songFieldController = TextEditingController(text: '');
    _songFieldFocusNode = FocusNode();
    _songFieldController.addListener(_onSearchTextChanged);
    //_artistsFuture = widget.api.fetchArtists();
    //_reloadAlbums();
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _songFieldController.removeListener(_onSearchTextChanged);
    _songFieldController.dispose();
    _songFieldFocusNode.dispose();
    super.dispose();
  }

  void _onSearchTextChanged() {
    final query = _songFieldController.text;
    if (query == _searchQuery) {
      return;
    }

    _searchDebounceTimer?.cancel();

    if (query.isEmpty || query.length < 3) {
      setState(() {
        _searchQuery = query;
        _searchResults = const <MusicTrack>[];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _searchQuery = query;
      _isSearching = true;
    });

    _searchDebounceTimer = Timer(_searchDebounceDuration, () {
      unawaited(_performSearch(query));
    });
  }

  Future<void> _performSearch(String query) async {
    try {
      final results = await widget.api.fetchSearchSongTitles(query);
      if (!mounted) {
        return;
      }

      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _searchResults = const <MusicTrack>[];
        _isSearching = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search failed: $error')),
      );
    }
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
      // Ignore warm-up failures; explicit user actions will show a message.
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
      await widget.api.updateSongRankOrder(
        songId: song.id,
        rankOrder: rankOrder,
      );

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

        final allSongs = snapshot.data ?? const <MusicTrack>[];

        // Use search results when available, otherwise use all songs
        final songs = _searchQuery.isEmpty || _searchQuery.length < 3
            ? allSongs
            : _searchResults;
        final totalPages = (songs.length / _pageSize).ceil();
        final startIndex = (_pageNumber - 1) * _pageSize;
        final currentSongs =
            songs.skip(startIndex).take(_pageSize).toList(growable: false);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_ensureSongTagsLoaded(currentSongs));
        });

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
                _searchQuery.isEmpty
                    ? '${allSongs.length} songs in your library'
                    : _searchQuery.length < 3
                        ? 'Type at least 3 characters to search'
                        : '${songs.length} songs matching "$_searchQuery"',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _songFieldController,
                focusNode: _songFieldFocusNode,
                decoration: InputDecoration(
                  labelText: 'Search song titles',
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  suffixIcon: _isSearching
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        )
                      : _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                _songFieldController.clear();
                              },
                            )
                          : null,
                ),
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
                    final hasLoadedTags = _songTagsById.containsKey(song.id);
                    final isLoadingSongTags =
                        _loadingTagsForSongIds.contains(song.id);
                    final hasStream = (song.filePath ?? '').trim().isNotEmpty;

                    return Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color:
                            theme.colorScheme.surface.withValues(alpha: 0.82),
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
                                  !hasLoadedTags && isLoadingSongTags
                                      ? 'Tags: loading...'
                                      : songTags.isEmpty
                                          ? 'Tags: none'
                                          : 'Tags: ${songTags.join(', ')}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  selectedTier == null
                                      ? 'Selected tier: Select rank'
                                      : 'Selected tier: Tier $selectedTier (rankOrder ${rankOrder.toStringAsFixed(2)})',
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
                                onSelected: (tier) {
                                  unawaited(_setSongTier(song, tier));
                                },
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
                              IconButton(
                                onPressed:
                                    hasStream ? () => _playSong(song) : null,
                                icon: const Icon(Icons.play_arrow_rounded),
                                tooltip: hasStream ? 'Play' : 'Unavailable',
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
    );
  }
}
