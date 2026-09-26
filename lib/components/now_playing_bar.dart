import 'dart:async';

import 'package:flutter/material.dart';

import '../models/local_file_queue_item.dart';
import '../models/music_track.dart';
import '../screens/album_songs_page.dart';
import '../screens/artist_albums_songs_page.dart';
import '../services/local_file_queue_manager.dart';
import '../services/music_library_api.dart';
import '../services/playback_controller.dart';

class NowPlayingBar extends StatefulWidget {
  const NowPlayingBar({super.key, required this.api});

  final MusicLibraryApi api;

  @override
  State<NowPlayingBar> createState() => _NowPlayingBarState();
}

class _NowPlayingBarState extends State<NowPlayingBar> {
  final LocalFileQueueManager _queueManager = LocalFileQueueManager.instance;
  final PlaybackController _playbackController = PlaybackController.instance;

  LocalFileQueueItem? _currentItem;
  MusicTrack? _currentTrack;
  bool _isPlaying = false;
  bool _isLoading = true;
  bool _isCheckingCache = true;
  bool _isCached = false;

  StreamSubscription<LocalFileQueueItem?>? _currentItemSubscription;
  StreamSubscription<bool>? _playingSubscription;

  @override
  void initState() {
    super.initState();
    debugPrint('[NowPlayingBar] initState: setting API');
    _queueManager.setApi(widget.api);
    _setupSubscriptions();
    _loadInitialState();
  }

  @override
  void didUpdateWidget(NowPlayingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api) {
      debugPrint('[NowPlayingBar] didUpdateWidget: API changed, reloading');
      _queueManager.setApi(widget.api);
      _loadInitialState();
    }
  }

  void _setupSubscriptions() {
    debugPrint('[NowPlayingBar] _setupSubscriptions');
    
    // Subscribe to current item changes
    _currentItemSubscription = _queueManager.onCurrentItemChanged.listen((item) {
      debugPrint('[NowPlayingBar] onCurrentItemChanged: ${item?.id}');
      _updateCurrentItem(item);
    });

    // Subscribe to playback state changes
    _playingSubscription = _playbackController.onQueuePlayingChanged.listen((isPlaying) {
      debugPrint('[NowPlayingBar] onQueuePlayingChanged: $isPlaying');
      if (mounted) {
        setState(() {
          _isPlaying = isPlaying;
        });
      }
    });
  }

  Future<void> _loadInitialState() async {
    debugPrint('[NowPlayingBar] _loadInitialState: loading queue');
    await _queueManager.loadQueue();
    
    // Check current playback state first
    final isPlaying = _playbackController.isQueuePlaying;
    debugPrint('[NowPlayingBar] _loadInitialState: isQueuePlaying=$isPlaying');
    
    // Get current item and track
    final currentItem = _queueManager.currentItem;
    debugPrint('[NowPlayingBar] _loadInitialState: currentItem=${currentItem?.id}');
    
    if (mounted) {
      setState(() {
        _isPlaying = isPlaying;
      });
    }
    
    if (currentItem != null) {
      await _updateCurrentItem(currentItem);
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateCurrentItem(LocalFileQueueItem? item) async {
    debugPrint('[NowPlayingBar] _updateCurrentItem: item=${item?.id}');
    
    if (item == null) {
      if (mounted) {
        setState(() {
          _currentItem = null;
          _currentTrack = null;
          _isLoading = false;
          _isPlaying = false;
        });
      }
      return;
    }

    // Find the MusicTrack for this queue item
    try {
      final track = await widget.api.fetchSongByFilePath(item.fullFilePath);
      debugPrint('[NowPlayingBar] _updateCurrentItem: found track ${track?.id}');
      
      if (mounted) {
        setState(() {
          _currentItem = item;
          _currentTrack = track;
          _isLoading = false;
        });
        
        // Check cache status for the track
        if (track != null) {
          await _checkCacheStatus(track);
        }
      }
    } catch (e) {
      debugPrint('[NowPlayingBar] _updateCurrentItem: Failed to fetch track: $e');
      if (mounted) {
        setState(() {
          _currentItem = item;
          _currentTrack = null;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _checkCacheStatus(MusicTrack track) async {
    try {
      final isCached = await _playbackController.isSongCached(track.id);
      if (mounted) {
        setState(() {
          _isCached = isCached;
          _isCheckingCache = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCached = false;
          _isCheckingCache = false;
        });
      }
    }
  }

  Future<void> _handlePlay() async {
    debugPrint('[NowPlayingBar] _handlePlay');
    if (_currentItem == null && _queueManager.queue.isNotEmpty) {
      // No current item but queue has items - play first item
      debugPrint('[NowPlayingBar] _handlePlay: no current item, playing first in queue');
      await _queueManager.playItem(_queueManager.queue.first);
    } else if (_currentItem != null) {
      // Current item exists - play it
      debugPrint('[NowPlayingBar] _handlePlay: playing current item ${_currentItem?.id}');
      await _queueManager.playItem(_currentItem!);
    }
  }

  Future<void> _handleStop() async {
    debugPrint('[NowPlayingBar] _handleStop');
    await _playbackController.stop();
    await _queueManager.loadQueue();
  }

  Future<void> _handleNext() async {
    debugPrint('[NowPlayingBar] _handleNext');
    await _queueManager.playNext();
  }

  Future<void> _showSongDetails() async {
    if (_currentTrack == null) return;

    final controller = PlaybackController.instance;
    
    // Get the most up-to-date cache size
    int cacheSizeBytes = 0;
    List<String> cachedSongIds = [];
    try {
      cacheSizeBytes = await controller.getCacheSize();
      cachedSongIds = await controller.getCachedSongIds();
    } catch (e) {
      // If getting cache info fails, use defaults
    }
    final cacheSizeMb = cacheSizeBytes / (1024 * 1024);
    
    if (!mounted) return;
    
    final theme = Theme.of(context);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_currentTrack!.title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Artist: ${_currentTrack!.artist}', style: theme.textTheme.bodyLarge),
              const SizedBox(height: 8),
              Text('Album: ${_currentTrack!.album}', style: theme.textTheme.bodyLarge),
              const SizedBox(height: 8),
              Text('Duration: ${_formatDuration(_currentTrack!.durationSeconds)}', style: theme.textTheme.bodyLarge),
              const SizedBox(height: 8),
              Text('Rank: ${_currentTrack!.starDisplay()}', style: theme.textTheme.bodyLarge),
              const Divider(height: 20),
              Text(
                'Cache Status: ${_isCached ? 'Cached' : 'Not Cached'}',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: _isCached ? Colors.green : Colors.orange,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Total Cache Size: ${cacheSizeMb.toStringAsFixed(2)} MB',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Cached Songs: ${cachedSongIds.length}',
                style: theme.textTheme.bodyMedium,
              ),
              if (_currentTrack!.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Divider(height: 20),
                Text('Tags: ${_currentTrack!.tags.join(", ")}', style: theme.textTheme.bodyMedium),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          if (_isCached && _currentTrack != null)
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await controller.removeFromCache(_currentTrack!.id);
                await _checkCacheStatus(_currentTrack!);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete from Cache'),
            ),
          if (!_isCached && _currentTrack != null)
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _checkCacheStatus(_currentTrack!);
              },
              child: const Text('Refresh'),
            ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Future<void> _navigateToSongSource() async {
    if (_currentTrack == null) return;
    
    if (_currentTrack!.album.isNotEmpty) {
      // Song belongs to an album - navigate to album page
      try {
        final album = await widget.api.findAlbumByName(_currentTrack!.album);
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
            SnackBar(content: Text('Could not find album: ${_currentTrack!.album}')),
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
        final artist = await widget.api.findArtistByName(_currentTrack!.artist);
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
            SnackBar(content: Text('Could not find artist: ${_currentTrack!.artist}')),
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
  void dispose() {
    _currentItemSubscription?.cancel();
    _playingSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Show loading state
    if (_isLoading) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Loading queue...'),
          ],
        ),
      );
    }

    // No current track
    if (_currentTrack == null && _currentItem == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        children: <Widget>[
          // Play or Stop button
          if (_isPlaying)
            IconButton.filled(
              onPressed: _handleStop,
              icon: const Icon(Icons.stop_rounded),
              tooltip: 'Stop',
            ),
          if (!_isPlaying)
            IconButton.filled(
              onPressed: _handlePlay,
              icon: const Icon(Icons.play_arrow_rounded),
              tooltip: 'Play',
            ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: _navigateToSongSource,
              child: Text(
                _currentTrack != null
                    ? '${_currentTrack!.artist} — ${_currentTrack!.title}'
                    : _currentItem?.title ?? 'Unknown',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: _handleNext,
            icon: const Icon(Icons.skip_next_rounded),
            tooltip: 'Next in queue',
          ),
          IconButton(
            onPressed: _showSongDetails,
            icon: Icon(
              _isCheckingCache ? Icons.refresh_rounded : Icons.info_outline_rounded,
              color: _isCached ? Colors.green : theme.colorScheme.onSurfaceVariant,
            ),
            tooltip: 'Song details and cache status',
          ),
        ],
      ),
    );
  }
}
