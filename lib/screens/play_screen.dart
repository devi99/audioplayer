import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/music_track.dart';
import '../services/music_library_api.dart';
import '../services/playback_controller.dart';
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
  final Random _random = Random();
  final Map<String, List<String>> _songTagsById = <String, List<String>>{};
  final Set<String> _blacklistedTags = <String>{};
  final Set<String> _whitelistedTags = <String>{};
  final PlaybackController _playbackController = PlaybackController.instance;

  StreamSubscription<void>? _completionSubscription;
  StreamSubscription<List<MusicTrack>>? _queueSubscription;
  StreamSubscription<int>? _queueIndexSubscription;
  StreamSubscription<bool>? _queuePlayingSubscription;

  List<MusicTrack> _allSongs = const <MusicTrack>[];
  List<MusicTrack> _queue = const <MusicTrack>[];

  bool _isLoading = true;
  bool _isPlayingQueue = false;
  bool _taggedSongsOnly = false;
  bool _whitelistIncludeUntagged = false;

  Set<int> _selectedTiers = <int>{};
  int _currentQueueIndex = -1;
  PlayFilterMode _playFilterMode = PlayFilterMode.blacklist;

  MusicTrack? get _currentlyPlaying {
    if (!_isPlayingQueue ||
        _currentQueueIndex < 0 ||
        _currentQueueIndex >= _queue.length) {
      return null;
    }
    return _queue[_currentQueueIndex];
  }

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

  Map<String, String> _queuedUniqueTagMap() {
    final tags = <String, String>{};
    for (final song in _queue) {
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
    
    // Set the stream URL provider for the playback controller
    _playbackController.setStreamUrlProviderSync((trackId) => widget.api.streamSongUrl(trackId));
    
    // Listen to queue state changes from the controller
    _queueSubscription = _playbackController.onQueueChanged.listen((queue) {
      if (mounted) {
        setState(() {
          _queue = queue;
        });
      }
    });
    
    _queueIndexSubscription = _playbackController.onQueueIndexChanged.listen((index) {
      if (mounted) {
        setState(() {
          _currentQueueIndex = index;
          _isPlayingQueue = _playbackController.isQueuePlaying;
        });
      }
    });
    
    _queuePlayingSubscription = _playbackController.onQueuePlayingChanged.listen((isPlaying) {
      if (mounted) {
        setState(() {
          _isPlayingQueue = isPlaying;
        });
      }
    });
    
    _loadSongs();
  }

  @override
  void dispose() {
    _completionSubscription?.cancel();
    _queueSubscription?.cancel();
    _queueIndexSubscription?.cancel();
    _queuePlayingSubscription?.cancel();
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
        _currentQueueIndex = -1;
        _isPlayingQueue = false;
      });
      
      // Update the controller's queue with the filtered queue
      final filteredQueue = _buildTierQueue(_selectedTiers);
      _playbackController.setQueue(filteredQueue, startIndex: -1);

      if (_playFilterMode == PlayFilterMode.whitelist) {
        unawaited(_ensureTagsForSongs(_songsForTiers(_selectedTiers)));
      } else {
        unawaited(_ensureTagsForSongs(_queue));
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _allSongs = const <MusicTrack>[];
        _isLoading = false;
        _currentQueueIndex = -1;
        _isPlayingQueue = false;
      });
      
      // Update the controller's queue
      _playbackController.setQueue(const [], startIndex: -1);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to load songs for Play queue: $error'),
        ),
      );
    }
  }

  List<MusicTrack> _buildTierQueue(Set<int> tiers) {
    return _songsForTiers(tiers).where(_isSongAllowedByActiveFilters).toList();
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

    if (_playFilterMode == PlayFilterMode.whitelist) {
      if (!mounted) {
        return;
      }

      // Update the controller's queue with the filtered queue
      final newQueue = _buildTierQueue(_selectedTiers);
      _playbackController.setQueue(newQueue, startIndex: -1);
      return;
    }

    if (_blacklistedTags.isNotEmpty || _taggedSongsOnly) {
      await _applyBlacklistToCurrentQueue();
    }
  }

  Future<void> _applyBlacklistToCurrentQueue() async {
    final currentSongId = _currentlyPlaying?.id;
    final oldQueue = List<MusicTrack>.from(_queue);
    final filteredQueue = oldQueue.where(_isSongAllowedByActiveFilters).toList();

    if (filteredQueue.isEmpty) {
      await _stopQueuePlayback();
      // Update controller's queue
      _playbackController.setQueue(filteredQueue, startIndex: -1);
      return;
    }

    var nextIndex = filteredQueue.indexWhere((song) => song.id == currentSongId);
    final currentSongWasRemoved = currentSongId != null && nextIndex < 0;

    if (nextIndex < 0) {
      nextIndex = _currentQueueIndex.clamp(0, filteredQueue.length - 1);
    }

    // Update the controller's queue with the filtered queue
    _playbackController.setQueue(filteredQueue, startIndex: nextIndex);

    if (currentSongWasRemoved && _isPlayingQueue) {
      await _playbackController.skipToIndex(nextIndex);
    } else if (_isPlayingQueue) {
      // Just update the index if we're still playing
      await _playbackController.skipToIndex(nextIndex);
    }
  }

  Future<void> _toggleTagBlacklist(String normalizedTag, bool shouldBlacklist) async {
    setState(() {
      if (shouldBlacklist) {
        _blacklistedTags.add(normalizedTag);
      } else {
        _blacklistedTags.remove(normalizedTag);
      }
    });

    await _applyBlacklistToCurrentQueue();
  }

  Future<void> _clearTagBlacklist() async {
    if (_blacklistedTags.isEmpty) {
      return;
    }

    final currentSongId = _currentlyPlaying?.id;

    setState(() {
      _blacklistedTags.clear();
    });

    final restoredQueue = _buildTierQueue(_selectedTiers);

    if (restoredQueue.isEmpty) {
      await _stopQueuePlayback();
      _playbackController.setQueue(restoredQueue, startIndex: -1);
      return;
    }

    var restoredIndex = restoredQueue.indexWhere((song) => song.id == currentSongId);
    final currentSongMissing = currentSongId != null && restoredIndex < 0;

    if (restoredIndex < 0) {
      restoredIndex = _currentQueueIndex.clamp(0, restoredQueue.length - 1);
    }

    // Update the controller's queue
    _playbackController.setQueue(restoredQueue, startIndex: restoredIndex);

    if (currentSongMissing && _isPlayingQueue) {
      await _playbackController.skipToIndex(restoredIndex);
    } else if (_isPlayingQueue) {
      await _playbackController.skipToIndex(restoredIndex);
    }
  }

  Future<void> _setPlayFilterMode(PlayFilterMode mode) async {
    if (_playFilterMode == mode) {
      return;
    }

    setState(() {
      _playFilterMode = mode;
      _currentQueueIndex = -1;
      _isPlayingQueue = false;
    });

    await _playbackController.stopQueue();

    if (!mounted) {
      return;
    }

    if (mode == PlayFilterMode.whitelist) {
      final tierSongs = _songsForTiers(_selectedTiers);
      unawaited(_ensureTagsForSongs(tierSongs));
      // Update the controller's queue with the new filter
      final newQueue = _buildTierQueue(_selectedTiers);
      _playbackController.setQueue(newQueue, startIndex: -1);
      return;
    }

    // Update the controller's queue with the new filter
    final newQueue = _buildTierQueue(_selectedTiers);
    _playbackController.setQueue(newQueue, startIndex: -1);
    unawaited(_ensureTagsForSongs(newQueue));
  }

  void _toggleWhitelistTag(String normalizedTag, bool selected) {
    setState(() {
      if (selected) {
        _whitelistedTags.add(normalizedTag);
      } else {
        _whitelistedTags.remove(normalizedTag);
      }

      _currentQueueIndex = -1;
      _isPlayingQueue = false;
    });

    unawaited(_playbackController.stopQueue());
    // Update the controller's queue with the new filter
    final newQueue = _buildTierQueue(_selectedTiers);
    _playbackController.setQueue(newQueue, startIndex: -1);
  }

  void _toggleWhitelistNone(bool selected) {
    setState(() {
      _whitelistIncludeUntagged = selected;
      _currentQueueIndex = -1;
      _isPlayingQueue = false;
    });

    unawaited(_playbackController.stopQueue());
    // Update the controller's queue with the new filter
    final newQueue = _buildTierQueue(_selectedTiers);
    _playbackController.setQueue(newQueue, startIndex: -1);
  }

  void _clearWhitelistSelection() {
    if (_whitelistedTags.isEmpty && !_whitelistIncludeUntagged) {
      return;
    }

    setState(() {
      _whitelistedTags.clear();
      _whitelistIncludeUntagged = false;
      _currentQueueIndex = -1;
      _isPlayingQueue = false;
    });

    unawaited(_playbackController.stopQueue());
    // Update the controller's queue with the new filter
    final newQueue = _buildTierQueue(_selectedTiers);
    _playbackController.setQueue(newQueue, startIndex: -1);
  }

  void _setTaggedSongsOnly(bool enabled) {
    setState(() {
      _taggedSongsOnly = enabled;
      _currentQueueIndex = -1;
      _isPlayingQueue = false;
    });

    unawaited(_playbackController.stopQueue());
    // Update the controller's queue with the new filter
    final newQueue = _buildTierQueue(_selectedTiers);
    _playbackController.setQueue(newQueue, startIndex: -1);
    unawaited(_ensureTagsForSongs(newQueue));
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

  Future<void> _startQueuePlayback() async {
    if (_queue.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _selectedTiers.isEmpty
                ? 'Select one or more tiers to build a queue.'
                : 'Queue is empty for the selected tiers.',
          ),
        ),
      );
      return;
    }

    // Use the controller to start queue playback
    await _playbackController.playQueue(startIndex: 0);
  }



  Future<void> _stopQueuePlayback() async {
    await _playbackController.stopQueue();
  }

  Future<void> _nextTrack() async {
    if (_queue.isEmpty) {
      return;
    }

    // Use the controller to handle next track
    await _playbackController.playNext();
  }

  void _shuffleQueue() {
    if (_queue.length <= 1) {
      return;
    }

    final shuffled = List<MusicTrack>.from(_queue);
    for (var index = shuffled.length - 1; index > 0; index--) {
      final swapIndex = _random.nextInt(index + 1);
      final current = shuffled[index];
      shuffled[index] = shuffled[swapIndex];
      shuffled[swapIndex] = current;
    }

    // Update the controller's queue
    final wasPlaying = _isPlayingQueue;
    _playbackController.setQueue(shuffled, startIndex: wasPlaying ? 0 : -1);

    if (wasPlaying) {
      unawaited(_playbackController.playQueue(startIndex: 0));
    }
  }

  Future<void> _removeFromQueue(int index) async {
    if (index < 0 || index >= _queue.length) {
      return;
    }

    final isRemovingCurrent = index == _currentQueueIndex;
    final updatedQueue = List<MusicTrack>.from(_queue)..removeAt(index);

    if (updatedQueue.isEmpty) {
      await _stopQueuePlayback();
      return;
    }

    var updatedCurrentIndex = _currentQueueIndex;
    if (index < _currentQueueIndex) {
      updatedCurrentIndex -= 1;
    }

    if (isRemovingCurrent) {
      updatedCurrentIndex =
          index >= updatedQueue.length ? updatedQueue.length - 1 : index;
    }

    // Update the controller's queue
    _playbackController.setQueue(updatedQueue, startIndex: updatedCurrentIndex);

    if (isRemovingCurrent && _isPlayingQueue) {
      await _playbackController.skipToIndex(updatedCurrentIndex);
    } else {
      // Just update the queue without playing if we're not removing the current track
      _playbackController.setQueue(updatedQueue, startIndex: _currentQueueIndex);
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
    final newQueue = _buildTierQueue(nextSelectedTiers);

    setState(() {
      _selectedTiers = nextSelectedTiers;
      _currentQueueIndex = -1;
      _isPlayingQueue = false;
    });

    // Stop playback and update the controller's queue
    unawaited(_playbackController.stopQueue());
    _playbackController.setQueue(newQueue, startIndex: -1);

    if (_playFilterMode == PlayFilterMode.whitelist) {
      unawaited(_ensureTagsForSongs(tierSongs));
      return;
    }

    unawaited(_ensureTagsForSongs(newQueue));
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
    final modeTagMap = _playFilterMode == PlayFilterMode.whitelist
      ? _tierUniqueTagMap(_selectedTiers)
      : _queuedUniqueTagMap();
    final sortedTagKeys = modeTagMap.keys.toList()..sort();
    final tagLoadingSongs = _playFilterMode == PlayFilterMode.whitelist
      ? tierSongs
      : _queue;
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
            'Play',
            style: theme.textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Select one or more tiers to build your playback queue',
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
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: <Widget>[
              FilledButton.icon(
                onPressed: _startQueuePlayback,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play Queue'),
              ),
              OutlinedButton.icon(
                onPressed: _shuffleQueue,
                icon: const Icon(Icons.shuffle_rounded),
                label: const Text('Shuffle'),
              ),
              OutlinedButton.icon(
                onPressed: _nextTrack,
                icon: const Icon(Icons.skip_next_rounded),
                label: const Text('Next'),
              ),
              OutlinedButton.icon(
                onPressed: _stopQueuePlayback,
                icon: const Icon(Icons.stop_rounded),
                label: const Text('Stop'),
              ),
            ],
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
              (_queue.isNotEmpty ||
                  sortedTagKeys.isNotEmpty ||
                  _blacklistedTags.isNotEmpty))
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Queue tags (toggle to blacklist)',
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
              '${_queue.length} queued songs',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _queue.isEmpty
              ? Center(
                  child: Text(
                    _selectedTiers.isEmpty
                        ? 'Select one or more tiers to build queue.'
                        : _playFilterMode == PlayFilterMode.whitelist &&
                                _whitelistedTags.isEmpty &&
                                !_whitelistIncludeUntagged
                            ? 'Select one or more whitelist tags (or None) to build queue.'
                            : 'No songs in the selected tiers.',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _queue.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                      final song = _queue[index];
                      final isCurrent =
                          _isPlayingQueue && index == _currentQueueIndex;
                      final songTags = _tagsForSong(song);
                      final hasLoadedTags = _hasLoadedTagsForSong(song);

                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? theme.colorScheme.primaryContainer
                                  .withValues(alpha: 0.55)
                              : theme.colorScheme.surface
                                  .withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              isCurrent
                                  ? Icons.volume_up_rounded
                                  : Icons.music_note_rounded,
                              color: isCurrent
                                  ? theme.colorScheme.onPrimaryContainer
                                  : theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  if (isCurrent)
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
                                    )
                                  else
                                    Text(
                                      song.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
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
                            IconButton(
                              onPressed: () => _removeFromQueue(index),
                              icon: const Icon(Icons.delete_outline_rounded),
                              tooltip: 'Delete from queue',
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
