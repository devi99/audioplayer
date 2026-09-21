import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

/// A small floating YouTube player widget that can be shown when playing YouTube videos.
/// 
/// This widget appears as a small window that can be positioned near the play button.
/// It includes the YouTube player and a close button.
class YoutubeFloatingPlayer extends StatefulWidget {
  const YoutubeFloatingPlayer({
    super.key,
    required this.controller,
    required this.videoTitle,
    required this.onDismiss,
    this.initialPosition,
  });

  final YoutubePlayerController controller;
  final String videoTitle;
  final VoidCallback onDismiss;
  final Offset? initialPosition;

  @override
  State<YoutubeFloatingPlayer> createState() => _YoutubeFloatingPlayerState();
}

class _YoutubeFloatingPlayerState extends State<YoutubeFloatingPlayer> {
  Offset _position = const Offset(20, 20);
  bool _isDragging = false;
  Offset? _dragStartPosition;

  @override
  void initState() {
    super.initState();
    if (widget.initialPosition != null) {
      _position = widget.initialPosition!;
    }
  }

  @override
  void dispose() {
    widget.controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanStart: (details) {
          setState(() {
            _isDragging = true;
            _dragStartPosition = details.globalPosition;
          });
        },
        onPanUpdate: (details) {
          if (_isDragging && _dragStartPosition != null) {
            final delta = details.globalPosition - _dragStartPosition!;
            setState(() {
              _position += delta;
              _dragStartPosition = details.globalPosition;
            });
          }
        },
        onPanEnd: (details) {
          setState(() {
            _isDragging = false;
            _dragStartPosition = null;
          });
        },
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 300,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with title and close button
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.videoTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        tooltip: 'Close',
                        onPressed: () {
                          widget.controller.pauseVideo();
                          widget.onDismiss();
                        },
                        style: IconButton.styleFrom(
                          padding: const EdgeInsets.all(4),
                        ),
                      ),
                    ],
                  ),
                ),
                // YouTube player
                SizedBox(
                  height: 200,
                  width: 300,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(12),
                    ),
                    child: YoutubePlayer(
                      controller: widget.controller,
                      aspectRatio: 16 / 9,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
