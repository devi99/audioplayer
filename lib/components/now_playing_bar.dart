import 'dart:async';

import '../models/music_track.dart';
import '../services/music_library_api.dart';
import '../services/playback_controller.dart';
import 'package:flutter/material.dart';
import '../screens/album_songs_page.dart';
import '../screens/artist_albums_songs_page.dart';

class NowPlayingBar extends StatefulWidget {
  const NowPlayingBar({super.key, required this.track, required this.api});

  final MusicTrack track;
  final MusicLibraryApi api;

  @override
  State<NowPlayingBar> createState() => _NowPlayingBarState();
}

class _NowPlayingBarState extends State<NowPlayingBar> {
  bool _isCached = false;
  bool _isCheckingCache = true;

  @override
  void initState() {
    super.initState();
    _checkCacheStatus();
  }

  @override
  void didUpdateWidget(NowPlayingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) {
      _checkCacheStatus();
    }
  }

  Future<void> _checkCacheStatus() async {
    final controller = PlaybackController.instance;
    final isCached = await controller.isSongCached(widget.track.id);
    if (mounted) {
      setState(() {
        _isCached = isCached;
        _isCheckingCache = false;
      });
    }
  }

  Future<void> _showSongDetails() async {
    final controller = PlaybackController.instance;
    
    // Get the most up-to-date cache size
    final cacheSizeBytes = await controller.getCacheSize();
    final cacheSizeMb = cacheSizeBytes / (1024 * 1024);
    final cachedSongIds = await controller.getCachedSongIds();
    
    if (!mounted) return;
    
    final theme = Theme.of(context);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.track.title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Artist: ${widget.track.artist}', style: theme.textTheme.bodyLarge),
              const SizedBox(height: 8),
              Text('Album: ${widget.track.album}', style: theme.textTheme.bodyLarge),
              const SizedBox(height: 8),
              Text('Duration: ${_formatDuration(widget.track.durationSeconds)}', style: theme.textTheme.bodyLarge),
              const SizedBox(height: 8),
              Text('Rank: ${widget.track.starDisplay()}', style: theme.textTheme.bodyLarge),
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
              if (widget.track.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Divider(height: 20),
                Text('Tags: ${widget.track.tags.join(", ")}', style: theme.textTheme.bodyMedium),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          if (!_isCached)
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                // Force re-check cache status
                await _checkCacheStatus();
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
    if (widget.track.album.isNotEmpty) {
      // Song belongs to an album - navigate to album page
      try {
        final album = await widget.api.findAlbumByName(widget.track.album);
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
            SnackBar(content: Text('Could not find album: ${widget.track.album}')),
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
        final artist = await widget.api.findArtistByName(widget.track.artist);
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
            SnackBar(content: Text('Could not find artist: ${widget.track.artist}')),
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
    final controller = PlaybackController.instance;

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
          IconButton.filled(
            onPressed: () {
              unawaited(controller.stop());
            },
            icon: const Icon(Icons.stop_rounded),
            tooltip: 'Stop',
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () => unawaited(_navigateToSongSource()),
              child: Text(
                '${widget.track.artist} — ${widget.track.title}',
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