import 'package:flutter/material.dart';

import '../models/local_file_queue_item.dart';
import '../services/local_file_queue_manager.dart';
import '../services/music_library_api.dart';

/// Screen for viewing and managing the local file queue.
class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key, required this.api});

  final MusicLibraryApi api;

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  final LocalFileQueueManager _queueManager = LocalFileQueueManager.instance;

  @override
  void initState() {
    super.initState();
    _queueManager.setApi(widget.api);
    _queueManager.loadQueue();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
            debugPrint('[QueueScreen] currentSnapshot: hasData=${currentSnapshot.hasData}, data=${currentSnapshot.data?.id}');

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Local File Queue',
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
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
                    debugPrint('[QueueScreen] item ${item.id}: isCurrent=$isCurrent, currentItemId=$currentItemId');

                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? theme.colorScheme.primaryContainer.withValues(
                                alpha: 0.55)
                            : theme.colorScheme.surface.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
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
                              children: [
                                Text(
                                  item.title ?? 'Unknown',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${item.artist ?? 'Unknown'} • ${item.album ?? 'Unknown'}',
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
                            onPressed: () async {
                              await _queueManager.removeFromQueue(item.id);
                            },
                            icon: const Icon(Icons.delete_outline_rounded),
                            tooltip: 'Remove from queue',
                          ),
                        ],
                      ),
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
          ),
        );
          },
        );
      },
    );
  }
}
