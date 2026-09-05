import 'dart:async';

import 'package:flutter/material.dart';

import '../models/music_track.dart';
import '../services/music_library_api.dart';
import 'shared_library_widgets.dart';
import 'song_management_mixin.dart';

class SongsBrowsePage extends StatefulWidget {
  const SongsBrowsePage({super.key, required this.api});

  final MusicLibraryApi api;

  @override
  State<SongsBrowsePage> createState() => _SongsBrowsePageState();
}

class _SongsBrowsePageState extends State<SongsBrowsePage> with SongManagementMixin {
  static const int _pageSize = 20;
  static const Duration _searchDebounceDuration = Duration(milliseconds: 500);

  late final Future<List<MusicTrack>> _songsFuture;
  late final TextEditingController _songFieldController;
  late final FocusNode _songFieldFocusNode;

  int _pageNumber = 1;
  String _searchQuery = '';
  List<MusicTrack> _searchResults = const <MusicTrack>[];
  bool _isSearching = false;
  Timer? _searchDebounceTimer;

  @override
  MusicLibraryApi get api => widget.api;

  @override
  void initState() {
    super.initState();
    _songsFuture = api.fetchSongs(pageSize: 0);
    unawaited(primeTagsCatalog());
    _songFieldController = TextEditingController(text: '');
    _songFieldFocusNode = FocusNode();
    _songFieldController.addListener(_onSearchTextChanged);
    //_artistsFuture = api.fetchArtists();
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
      final results = await api.fetchSearchSongTitles(query);
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
          unawaited(ensureSongTagsLoaded(currentSongs));
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
                    final hasLoadedTags = songTagsById.containsKey(song.id);
                    final isLoadingSongTags =
                        loadingTagsForSongIds.contains(song.id);
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
                                  unawaited(setSongTier(song, tier));
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
                              IconButton(
                                onPressed:
                                    hasStream ? () => playSong(song) : null,
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
