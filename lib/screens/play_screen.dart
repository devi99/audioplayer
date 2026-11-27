import 'dart:async';

import 'package:flutter/material.dart';

import '../models/music_track.dart';
import '../services/music_library_api.dart';
import '../services/local_file_queue_manager.dart';
import 'album_songs_page.dart';
import 'artist_albums_songs_page.dart';

enum PlayFilterMode {
  blacklist,
  whitelist,
}

class PlayScreen extends StatefulWidget {
  const PlayScreen({super.key, required this.api});

  final MusicLibraryApi api;

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  final Map<String, List<String>> _songTagsById = <String, List<String>>{};
  final Set<String> _blacklistedTags = <String>{};
  final Set<String> _whitelistedTags = <String>{};
  final LocalFileQueueManager _queueManager = LocalFileQueueManager.instance;

  List<MusicTrack> _allSongs = const <MusicTrack>[];

  bool _isLoading = true;
  bool _isAddingToQueue = false;
  bool _taggedSongsOnly = false;
  bool _whitelistIncludeUntagged = false;

  Set<int> _selectedTiers = <int>{};
  PlayFilterMode _playFilterMode = PlayFilterMode.blacklist;

  String _normalizeTag(String tag) => tag.trim().toLowerCase();

  List<String> _tagsForSong(MusicTrack song) {
    final loadedTags = _songTagsById[song.id];
    if (loadedTags != null) {
      return loadedTags;
    }
    return song.tags;
  }

  bool _hasLoadedTagsForSong(MusicTrack song) {
    return _songTagsById.containsKey(song.id);
  }

  bool _isSongAllowedByBlacklist(MusicTrack song) {
    if (_blacklistedTags.isEmpty) {
      return true;
    }
    return !_tagsForSong(song)
        .map(_normalizeTag)
        .any(_blacklistedTags.contains);
  }

  bool _isSongAllowedByTaggedOnly(MusicTrack song) {
    if (!_taggedSongsOnly) {
      return true;
    }

    // Keep songs until tags are loaded; they will be filtered accurately after fetch.
    if (!_songTagsById.containsKey(song.id)) {
      return true;
    }

    return _tagsForSong(song).isNotEmpty;
  }

  bool _isSongAllowedByWhitelist(MusicTrack song) {
    if (!_songTagsById.containsKey(song.id)) {
      return false;
    }

    final songTags = _tagsForSong(song).map(_normalizeTag).toSet();
    final hasWhitelistedTag = songTags.any(_whitelistedTags.contains);
    final matchesNone = _whitelistIncludeUntagged && songTags.isEmpty;

    if (_whitelistedTags.isEmpty && !_whitelistIncludeUntagged) {
      return false;
    }

    return hasWhitelistedTag || matchesNone;
  }

  bool _isSongAllowedByActiveFilters(MusicTrack song) {
    if (_playFilterMode == PlayFilterMode.whitelist) {
      return _isSongAllowedByWhitelist(song);
    }

    return _isSongAllowedByBlacklist(song) && _isSongAllowedByTaggedOnly(song);
  }

  Map<String, String> _filteredUniqueTagMap() {
    final filteredSongs = _filteredSongs;
    final tags = <String, String>{};
    for (final song in filteredSongs) {
      for (final tag in _tagsForSong(song)) {
        final trimmedTag = tag.trim();
        if (trimmedTag.isEmpty) {
          continue;
        }
        final normalizedTag = _normalizeTag(trimmedTag);
        tags.putIfAbsent(normalizedTag, () => trimmedTag);
      }
    }
    return tags;
  }

  List<MusicTrack> get _filteredSongs {
    return _songsForTiers(_selectedTiers).where(_isSongAllowedByActiveFilters).toList();
  }

  List<MusicTrack> _songsForTiers(Set<int> tiers) {
    if (tiers.isEmpty) {
      return const <MusicTrack>[];
    }

    return _allSongs
        .where(
          (song) =>
              tiers.any((tier) => _matchesTier(song.rankOrder, tier)) &&
              (song.filePath ?? '').trim().isNotEmpty,
        )
        .toList(growable: false);
  }

  Map<String, String> _tierUniqueTagMap(Set<int> tiers) {
    final tags = <String, String>{};
    for (final song in _songsForTiers(tiers)) {
      if (!_songTagsById.containsKey(song.id)) {
        continue;
      }

      for (final tag in _tagsForSong(song)) {
        final trimmedTag = tag.trim();
        if (trimmedTag.isEmpty) {
          continue;
        }

        final normalizedTag = _normalizeTag(trimmedTag);
        tags.putIfAbsent(normalizedTag, () => trimmedTag);
      }
    }

    return tags;
  }

  @override
  void initState() {
    super.initState();
    _queueManager.setApi(widget.api);
    _loadSongs();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadSongs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final songs = await widget.api.fetchSongs(pageSize: 0);
      if (!mounted) {
        return;
      }

      setState(() {
        _allSongs = songs;
        _isLoading = false;
      });

      if (_playFilterMode == PlayFilterMode.whitelist) {
        unawaited(_ensureTagsForSongs(_songsForTiers(_selectedTiers)));
      } else {
        unawaited(_ensureTagsForSongs(_filteredSongs));
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _allSongs = const <MusicTrack>[];
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to load songs: $error'),
        ),
      );
    }
  }

  Future<void> _ensureTagsForSongs(
    List<MusicTrack> songs,
  ) async {
    final missingIds = songs
        .map((song) => song.id)
        .where((id) => id.isNotEmpty && !_songTagsById.containsKey(id))
        .toSet()
        .toList(growable: false);

    if (missingIds.isEmpty) {
      return;
    }

    await Future.wait(
      missingIds.map((songId) async {
        List<String> songTags;
        try {
          songTags = await widget.api.fetchSongTags(songId);
        } catch (_) {
          songTags = const <String>[];
        }

        if (!mounted) {
          return;
        }

        setState(() {
          _songTagsById[songId] = songTags;
        });
      }),
    );
  }

  Future<void> _toggleTagBlacklist(String normalizedTag, bool shouldBlacklist) async {
    setState(() {
      if (shouldBlacklist) {
        _blacklistedTags.add(normalizedTag);
      } else {
        _blacklistedTags.remove(normalizedTag);
      }
    });
  }

  Future<void> _clearTagBlacklist() async {
    if (_blacklistedTags.isEmpty) {
      return;
    }

    setState(() {
      _blacklistedTags.clear();
    });
  }

  Future<void> _setPlayFilterMode(PlayFilterMode mode) async {
    if (_playFilterMode == mode) {
      return;
    }

    setState(() {
      _playFilterMode = mode;
    });

    if (!mounted) {
      return;
    }

    if (mode == PlayFilterMode.whitelist) {
      final tierSongs = _songsForTiers(_selectedTiers);
      unawaited(_ensureTagsForSongs(tierSongs));
      return;
    }

    unawaited(_ensureTagsForSongs(_filteredSongs));
  }

  void _toggleWhitelistTag(String normalizedTag, bool selected) {
    setState(() {
      if (selected) {
        _whitelistedTags.add(normalizedTag);
      } else {
        _whitelistedTags.remove(normalizedTag);
      }
    });
  }

  void _toggleWhitelistNone(bool selected) {
    setState(() {
      _whitelistIncludeUntagged = selected;
    });
  }

  void _clearWhitelistSelection() {
    if (_whitelistedTags.isEmpty && !_whitelistIncludeUntagged) {
      return;
    }

    setState(() {
      _whitelistedTags.clear();
      _whitelistIncludeUntagged = false;
    });
  }

  void _setTaggedSongsOnly(bool enabled) {
    setState(() {
      _taggedSongsOnly = enabled;
    });
    unawaited(_ensureTagsForSongs(_filteredSongs));
  }

  bool _matchesTier(double rankOrder, int tier) {
    switch (tier) {
      case 1:
        return rankOrder >= 0 && rankOrder < 1;
      case 2:
        return rankOrder >= 1 && rankOrder < 2;
      case 3:
        return rankOrder >= 2 && rankOrder < 3;
      case 4:
        return rankOrder >= 3 && rankOrder < 4;
      case 5:
        return rankOrder >= 4 && rankOrder <= 5;
      default:
        return false;
    }
  }

  Future<void> _addFilteredSongsToQueue() async {
    final filteredSongs = _filteredSongs;
    
    if (filteredSongs.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _selectedTiers.isEmpty
                ? 'Select one or more tiers to filter songs.'
                : _playFilterMode == PlayFilterMode.whitelist &&
                        _whitelistedTags.isEmpty &&
                        !_whitelistIncludeUntagged
                    ? 'Select one or more whitelist tags (or None) to filter songs.'
                    : 'No songs match the current filters.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _isAddingToQueue = true;
    });

    try {
      int addedCount = 0;
      for (final song in filteredSongs) {
        // Check if this song is already in the queue
        final existingItems = _queueManager.queue;
        final isAlreadyInQueue = existingItems.any(
          (item) => item.fullFilePath == song.filePath,
        );
        
        if (!isAlreadyInQueue) {
          await _queueManager.addToQueue(
            fullFilePath: song.filePath!,
            album: song.album,
            artist: song.artist,
            title: song.title,
          );
          addedCount++;
        }
      }

      // Reload the queue to show the new items
      await _queueManager.loadQueue();

      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added $addedCount songs to the local file queue'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error adding songs to queue: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAddingToQueue = false;
        });
      }
    }
  }

  void _onTierChanged(int tier, bool selected) {
    final nextSelectedTiers = Set<int>.from(_selectedTiers);
    if (selected) {
      nextSelectedTiers.add(tier);
    } else {
      nextSelectedTiers.remove(tier);
    }

    final tierSongs = _songsForTiers(nextSelectedTiers);

    setState(() {
      _selectedTiers = nextSelectedTiers;
    });

    if (_playFilterMode == PlayFilterMode.whitelist) {
      unawaited(_ensureTagsForSongs(tierSongs));
      return;
    }

    unawaited(_ensureTagsForSongs(_filteredSongs));
  }

  Future<void> _navigateToSongSource(MusicTrack song) async {
    if (song.album.isNotEmpty) {
      // Song belongs to an album - navigate to album page
      try {
        final album = await widget.api.findAlbumByName(song.album);
        if (album != null) {
          if (!mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => AlbumSongsPage(album: album, api: widget.api),
            ),
          );
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not find album: ${song.album}')),
          );
        }
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error finding album: $error')),
        );
      }
    } else {
      // Single track song - navigate to artist page
      try {
        final artist = await widget.api.findArtistByName(song.artist);
        if (artist != null) {
          if (!mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => ArtistAlbumsSongsPage(artist: artist, api: widget.api),
            ),
          );
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not find artist: ${song.artist}')),
          );
        }
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error finding artist: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tierSongs = _songsForTiers(_selectedTiers);
    final filteredSongs = _filteredSongs;
    final modeTagMap = _playFilterMode == PlayFilterMode.whitelist
      ? _tierUniqueTagMap(_selectedTiers)
      : _filteredUniqueTagMap();
    final sortedTagKeys = modeTagMap.keys.toList()..sort();
    final tagLoadingSongs = _playFilterMode == PlayFilterMode.whitelist
      ? tierSongs
      : filteredSongs;
    final tagLoadingTotal = tagLoadingSongs.length;
    final loadedTagCount =
      tagLoadingSongs.where(_hasLoadedTagsForSong).length;
    final hasPendingTagLoads =
      tagLoadingTotal > 0 && loadedTagCount < tagLoadingTotal;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Filter Songs',
            style: theme.textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Select tiers and apply filters, then add matching songs to the local file queue',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              ChoiceChip(
                label: const Text('Blacklist'),
                selected: _playFilterMode == PlayFilterMode.blacklist,
                onSelected: (_) {
                  unawaited(_setPlayFilterMode(PlayFilterMode.blacklist));
                },
              ),
              ChoiceChip(
                label: const Text('Whitelist'),
                selected: _playFilterMode == PlayFilterMode.whitelist,
                onSelected: (_) {
                  unawaited(_setPlayFilterMode(PlayFilterMode.whitelist));
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              for (var tier = 1; tier <= 5; tier++)
                ChoiceChip(
                  label: Text('T$tier'),
                  selected: _selectedTiers.contains(tier),
                  onSelected: (selected) => _onTierChanged(tier, selected),
                ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _isAddingToQueue ? null : _addFilteredSongsToQueue,
            icon: _isAddingToQueue
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.onPrimary,
                    ),
                  )
                : const Icon(Icons.add_rounded),
            label: _isAddingToQueue
                ? const Text('Adding...')
                : Text('Add ${filteredSongs.length} Songs to Queue'),
          ),
          const SizedBox(height: 10),
          if (hasPendingTagLoads)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Loading song tags... $loadedTagCount/$tagLoadingTotal',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          if (_playFilterMode == PlayFilterMode.blacklist &&
              (filteredSongs.isNotEmpty ||
                  sortedTagKeys.isNotEmpty ||
                  _blacklistedTags.isNotEmpty))
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Filtered songs tags (toggle to blacklist)',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (_blacklistedTags.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          unawaited(_clearTagBlacklist());
                        },
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Clear blacklist'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                FilterChip(
                  label: const Text('Tagged songs only'),
                  selected: _taggedSongsOnly,
                  onSelected: _setTaggedSongsOnly,
                ),
                if (sortedTagKeys.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final normalizedTag in sortedTagKeys)
                        FilterChip(
                          label: Text(modeTagMap[normalizedTag]!),
                          selected: _blacklistedTags.contains(normalizedTag),
                          onSelected: (selected) async {
                            await _toggleTagBlacklist(normalizedTag, selected);
                          },
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
              ],
            ),
          if (_playFilterMode == PlayFilterMode.whitelist &&
              (tierSongs.isNotEmpty ||
                  sortedTagKeys.isNotEmpty ||
                  _whitelistedTags.isNotEmpty ||
                  _whitelistIncludeUntagged))
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Selected tier tags (select to whitelist)',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (_whitelistedTags.isNotEmpty || _whitelistIncludeUntagged)
                      TextButton(
                        onPressed: _clearWhitelistSelection,
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Clear whitelist'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilterChip(
                      label: const Text('None (no tags)'),
                      selected: _whitelistIncludeUntagged,
                      onSelected: _toggleWhitelistNone,
                    ),
                    for (final normalizedTag in sortedTagKeys)
                      FilterChip(
                        label: Text(modeTagMap[normalizedTag]!),
                        selected: _whitelistedTags.contains(normalizedTag),
                        onSelected: (selected) {
                          _toggleWhitelistTag(normalizedTag, selected);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${filteredSongs.length} filtered songs',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 16),
          filteredSongs.isEmpty
              ? Center(
                  child: Text(
                    _selectedTiers.isEmpty
                        ? 'Select one or more tiers to filter songs.'
                        : _playFilterMode == PlayFilterMode.whitelist &&
                                _whitelistedTags.isEmpty &&
                                !_whitelistIncludeUntagged
                            ? 'Select one or more whitelist tags (or None) to filter songs.'
                            : 'No songs match the current filters.',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredSongs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                      final song = filteredSongs[index];
                      final songTags = _tagsForSong(song);
                      final hasLoadedTags = _hasLoadedTagsForSong(song);

                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface
                              .withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              Icons.music_note_rounded,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  GestureDetector(
                                    onTap: () => unawaited(_navigateToSongSource(song)),
                                    child: Text(
                                      song.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        decoration: TextDecoration.underline,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${song.artist} • rankOrder ${song.rankOrder.toStringAsFixed(2)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  if (!hasLoadedTags)
                                    Row(
                                      children: <Widget>[
                                        SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'Loading tags...',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: theme
                                                  .colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  else
                                    Text(
                                      songTags.isEmpty
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
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
        ],
      ),
    );
  }
}
