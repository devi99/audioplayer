import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../models/music_track.dart';
import '../services/music_library_api.dart';

class PlayScreen extends StatefulWidget {
  const PlayScreen({super.key, required this.api});

  final MusicLibraryApi api;

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  final AudioPlayer _player = AudioPlayer();
  final Random _random = Random();

  StreamSubscription<void>? _completionSubscription;

  List<MusicTrack> _allSongs = const <MusicTrack>[];
  List<MusicTrack> _queue = const <MusicTrack>[];

  bool _isLoading = true;
  bool _isPlayingQueue = false;

  int _selectedTier = 1;
  int _currentQueueIndex = -1;

  MusicTrack? get _currentlyPlaying {
    if (!_isPlayingQueue ||
        _currentQueueIndex < 0 ||
        _currentQueueIndex >= _queue.length) {
      return null;
    }
    return _queue[_currentQueueIndex];
  }

  @override
  void initState() {
    super.initState();
    _completionSubscription = _player.onPlayerComplete.listen((_) {
      _playNextInQueue();
    });
    _loadSongs();
  }

  @override
  void dispose() {
    _completionSubscription?.cancel();
    _player.dispose();
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
        _queue = _buildTierQueue(_selectedTier);
        _isLoading = false;
        _currentQueueIndex = -1;
        _isPlayingQueue = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _allSongs = const <MusicTrack>[];
        _queue = const <MusicTrack>[];
        _isLoading = false;
        _currentQueueIndex = -1;
        _isPlayingQueue = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to load songs for Play queue: $error'),
        ),
      );
    }
  }

  List<MusicTrack> _buildTierQueue(int tier) {
    return _allSongs
        .where(
          (song) =>
              _matchesTier(song.rankOrder, tier) &&
              (song.filePath ?? '').trim().isNotEmpty,
        )
        .toList();
  }

  bool _matchesTier(double rankOrder, int tier) {
    switch (tier) {
      case 1:
        return rankOrder < 0;
      case 2:
        return rankOrder >= 0 && rankOrder < 1;
      case 3:
        return rankOrder >= 1 && rankOrder < 2;
      case 4:
        return rankOrder >= 2 && rankOrder < 3;
      case 5:
        return rankOrder >= 3 && rankOrder <= 4;
      default:
        return false;
    }
  }

  Future<void> _startQueuePlayback() async {
    if (_queue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Queue is empty for the selected tier.')),
      );
      return;
    }

    setState(() {
      _isPlayingQueue = true;
      _currentQueueIndex = 0;
    });

    await _playCurrentTrack();
  }

  Future<void> _playCurrentTrack() async {
    if (!_isPlayingQueue ||
        _currentQueueIndex < 0 ||
        _currentQueueIndex >= _queue.length) {
      await _stopQueuePlayback();
      return;
    }

    final track = _queue[_currentQueueIndex];

    try {
      await _player.stop();
      await _player.play(UrlSource(widget.api.streamSongUrl(track.id)));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Skipping unavailable track: ${track.title}')),
      );
      _playNextInQueue();
    }
  }

  void _playNextInQueue() {
    if (!_isPlayingQueue) {
      return;
    }

    final nextIndex = _currentQueueIndex + 1;
    if (nextIndex >= _queue.length) {
      _stopQueuePlayback();
      return;
    }

    setState(() {
      _currentQueueIndex = nextIndex;
    });

    _playCurrentTrack();
  }

  Future<void> _stopQueuePlayback() async {
    await _player.stop();
    if (!mounted) {
      return;
    }

    setState(() {
      _isPlayingQueue = false;
      _currentQueueIndex = -1;
    });
  }

  Future<void> _nextTrack() async {
    if (_queue.isEmpty) {
      return;
    }

    if (!_isPlayingQueue) {
      setState(() {
        _isPlayingQueue = true;
        _currentQueueIndex = 0;
      });
      await _playCurrentTrack();
      return;
    }

    final nextIndex = _currentQueueIndex + 1;
    if (nextIndex >= _queue.length) {
      await _stopQueuePlayback();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reached end of queue.')),
      );
      return;
    }

    setState(() {
      _currentQueueIndex = nextIndex;
    });
    await _playCurrentTrack();
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

    setState(() {
      _queue = shuffled;
      _currentQueueIndex = _isPlayingQueue ? 0 : -1;
    });

    if (_isPlayingQueue) {
      _playCurrentTrack();
    }
  }

  Future<void> _removeFromQueue(int index) async {
    if (index < 0 || index >= _queue.length) {
      return;
    }

    final isRemovingCurrent = index == _currentQueueIndex;
    final updatedQueue = List<MusicTrack>.from(_queue)..removeAt(index);

    if (updatedQueue.isEmpty) {
      setState(() {
        _queue = updatedQueue;
      });
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

    setState(() {
      _queue = updatedQueue;
      _currentQueueIndex = _isPlayingQueue ? updatedCurrentIndex : -1;
    });

    if (isRemovingCurrent && _isPlayingQueue) {
      await _playCurrentTrack();
    }
  }

  void _onTierChanged(int tier) {
    setState(() {
      _selectedTier = tier;
      _queue = _buildTierQueue(tier);
      _currentQueueIndex = -1;
      _isPlayingQueue = false;
    });

    _player.stop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
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
            _currentlyPlaying == null
                ? 'Now Playing: Nothing currently playing'
                : 'Now Playing: ${_currentlyPlaying!.title} — ${_currentlyPlaying!.artist}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Select a tier to build your playback queue',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              for (var tier = 1; tier <= 5; tier++)
                ChoiceChip(
                  label: Text('Tier $tier'),
                  selected: _selectedTier == tier,
                  onSelected: (_) => _onTierChanged(tier),
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
          Expanded(
            child: _queue.isEmpty
                ? Center(
                    child: Text(
                      'No songs in this tier.',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _queue.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final song = _queue[index];
                      final isCurrent =
                          _isPlayingQueue && index == _currentQueueIndex;

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
          ),
        ],
      ),
    );
  }
}
