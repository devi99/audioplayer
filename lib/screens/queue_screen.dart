import 'package:flutter/material.dart';

import '../models/local_file_queue_item.dart';
import '../models/mpd_queue_item.dart';
import '../services/local_file_queue_manager.dart';
import '../services/mpd_queue_manager.dart';
import '../services/music_library_api.dart';

/// Modes of the queue screen: the app's local file queue, or a mirror of the
/// queue on the remote MPD player.
enum QueueScreenMode { local, mpd }

/// Screen for viewing and managing the local file queue or the MPD queue.
class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key, required this.api});

  final MusicLibraryApi api;

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  final LocalFileQueueManager _queueManager = LocalFileQueueManager.instance;
  final MpdQueueManager _mpdManager = MpdQueueManager.instance;

  QueueScreenMode _mode = QueueScreenMode.local;

  @override
  void initState() {
    super.initState();
    debugPrint('[QueueScreen] initState: setting API and loading queue');
    _queueManager.setApi(widget.api);
    _queueManager.loadQueue();
    _mpdManager.setApi(widget.api);
    if (_mode == QueueScreenMode.mpd) {
      _mpdManager.startPolling();
    }
  }

  @override
  void dispose() {
    _mpdManager.stopPolling();
    super.dispose();
  }

  void _setMode(QueueScreenMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
    });
    switch (mode) {
      case QueueScreenMode.local:
        _mpdManager.stopPolling();
        _queueManager.loadQueue();
      case QueueScreenMode.mpd:
        _mpdManager.startPolling();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            switch (_mode) {
              QueueScreenMode.local => 'Local File Queue',
              QueueScreenMode.mpd => 'MPD Queue',
            },
            style: theme.textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          SegmentedButton<QueueScreenMode>(
            segments: const [
              ButtonSegment(
                value: QueueScreenMode.local,
                icon: Icon(Icons.library_music_rounded),
                label: Text('Local'),
              ),
              ButtonSegment(
                value: QueueScreenMode.mpd,
                icon: Icon(Icons.speaker_rounded),
                label: Text('MPD'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (selection) => _setMode(selection.first),
          ),
          const SizedBox(height: 8),
          switch (_mode) {
            QueueScreenMode.local => _buildLocalQueue(theme),
            QueueScreenMode.mpd => _buildMpdQueue(theme),
          },
        ],
      ),
    );
  }

  Widget _buildLocalQueue(ThemeData theme) {
    return StreamBuilder<List<LocalFileQueueItem>>(
      stream: _queueManager.onQueueChanged,
      initialData: const [],
      builder: (context, queueSnapshot) {
        final queue = queueSnapshot.data ?? [];

        return StreamBuilder<LocalFileQueueItem?>(
          stream: _queueManager.onCurrentItemChanged,
          initialData: null,
          builder: (context, currentSnapshot) {
            final currentItemId = currentSnapshot.data?.id;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  '${queue.length} songs in queue',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                if (queue.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Text(
                        'Your queue is empty. Play a local file to add it to the queue.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                if (queue.isNotEmpty)
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: queue.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = queue[index];
                      final isCurrent = item.id == currentItemId;

                      return _buildQueueItemCard(
                        theme: theme,
                        isCurrent: isCurrent,
                        title: item.title ?? 'Unknown',
                        subtitle:
                            '${item.artist ?? 'Unknown'} • ${item.album ?? 'Unknown'}',
                        onPlay: isCurrent
                            ? null
                            : () async {
                                debugPrint('[QueueScreen] Play button pressed for item ${item.id} at index $index');
                                await _queueManager.playItem(item);
                              },
                        onDelete: () async {
                          debugPrint('[QueueScreen] Delete button pressed for item ${item.id}');
                          await _queueManager.removeFromQueue(item.id);
                        },
                      );
                    },
                  ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        await _queueManager.clearQueue();
                      },
                      icon: const Icon(Icons.clear_rounded),
                      label: const Text('Clear Queue'),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildMpdQueue(ThemeData theme) {
    return StreamBuilder<List<MpdQueueItem>>(
      stream: _mpdManager.onQueueChanged,
      initialData: _mpdManager.queue,
      builder: (context, queueSnapshot) {
        final queue = queueSnapshot.data ?? const <MpdQueueItem>[];

        return StreamBuilder<MpdStatus?>(
          stream: _mpdManager.onStatusChanged,
          initialData: _mpdManager.status,
          builder: (context, statusSnapshot) {
            final status = statusSnapshot.data;
            final currentFile = status?.currentSong?.file;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                _buildMpdStatusBar(theme, status),
                const SizedBox(height: 16),
                if (queue.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Text(
                        'The MPD queue is empty.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                if (queue.isNotEmpty)
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: queue.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = queue[index];
                      final isCurrent = item.file == currentFile;

                      return _buildQueueItemCard(
                        theme: theme,
                        isCurrent: isCurrent,
                        title: item.title ?? item.fileName,
                        subtitle:
                            '${item.artist ?? 'Unknown'} • ${item.album ?? 'Unknown'}',
                        onPlay: () async {
                          debugPrint('[QueueScreen] MPD play button pressed for ${item.file}');
                          await _mpdManager.playQueueItem(item);
                        },
                        onDelete: null,
                      );
                    },
                  ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        await _mpdManager.clearQueue();
                      },
                      icon: const Icon(Icons.clear_rounded),
                      label: const Text('Clear Queue'),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Connection state, playback state and transport controls for MPD
  Widget _buildMpdStatusBar(ThemeData theme, MpdStatus? status) {
    return StreamBuilder<bool>(
      stream: _mpdManager.onConnectedChanged,
      initialData: _mpdManager.connected,
      builder: (context, connectedSnapshot) {
        final connected = connectedSnapshot.data ?? false;

        final stateLabel = !connected
            ? 'Disconnected'
            : switch (status?.state) {
                'play' => 'Playing',
                'pause' => 'Paused',
                'stop' => 'Stopped',
                _ => 'Unknown',
              };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.circle_rounded,
                  size: 12,
                  color: connected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Text(
                  stateLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '${_mpdManager.queue.length} songs in queue',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  onPressed: () => _mpdManager.previous(),
                  icon: const Icon(Icons.skip_previous_rounded),
                  tooltip: 'Previous',
                ),
                IconButton(
                  onPressed: () =>
                      status?.isPlaying == true ? _mpdManager.pause() : _mpdManager.play(),
                  icon: Icon(
                    status?.isPlaying == true
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  tooltip: status?.isPlaying == true ? 'Pause' : 'Play',
                ),
                IconButton(
                  onPressed: () => _mpdManager.next(),
                  icon: const Icon(Icons.skip_next_rounded),
                  tooltip: 'Next',
                ),
              ],
            ),
            StreamBuilder<String?>(
              stream: _mpdManager.onErrorChanged,
              initialData: _mpdManager.error,
              builder: (context, errorSnapshot) {
                final error = errorSnapshot.data;
                if (error == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  /// Shared card layout for a queue item, used by both modes
  Widget _buildQueueItemCard({
    required ThemeData theme,
    required bool isCurrent,
    required String title,
    required String subtitle,
    VoidCallback? onPlay,
    VoidCallback? onDelete,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: isCurrent
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
            : theme.colorScheme.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            isCurrent ? Icons.volume_up_rounded : Icons.music_note_rounded,
            color: isCurrent
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (!isCurrent && onPlay != null)
            IconButton(
              onPressed: onPlay,
              icon: const Icon(Icons.play_arrow_rounded),
              tooltip: 'Play this song',
            ),
          if (onDelete != null)
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Remove from queue',
            ),
        ],
      ),
    );
  }
}
