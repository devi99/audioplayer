import 'package:flutter/material.dart';

/// Global storage for debug messages - cleared when app closes
class DebugMessageStorage {
  static final List<DebugMessage> _messages = [];
  static const int _maxMessages = 200;

  static void addMessage(String text) {
    _messages.add(DebugMessage(text: text, timestamp: DateTime.now()));
    if (_messages.length > _maxMessages) {
      _messages.removeRange(0, _messages.length - _maxMessages);
    }
  }

  static List<DebugMessage> get messages => List.unmodifiable(_messages);

  static void clear() {
    _messages.clear();
  }
}

class DebugMessage {
  final String text;
  final DateTime timestamp;

  DebugMessage({required this.text, required this.timestamp});
}

/// A full-screen debug console that displays debugPrint messages.
/// Accessible from the main menu on all platforms.
class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _formatTime(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Console'),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_rounded),
            tooltip: 'Clear all messages',
            onPressed: () {
              setState(() {
                DebugMessageStorage.clear();
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Info banner
          Container(
            color: theme.colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Debug messages are stored in memory only and will be cleared when the app closes.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          // Message list
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: DebugMessageStorage.messages.length,
              itemBuilder: (context, index) {
                final message = DebugMessageStorage.messages[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '[${_formatTime(message.timestamp)}] ${message.text}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
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

/// Override debugPrint to capture messages
void setupDebugMessageCapture() {
  // Only setup once
  if (debugPrint != _debugPrintWrapper) {
    final originalDebugPrint = debugPrint;
    debugPrint = (String? text, {int? wrapWidth}) {
      // Call original
      originalDebugPrint(text, wrapWidth: wrapWidth);
      // Store message
      if (text != null) {
        DebugMessageStorage.addMessage(text);
      }
    };
  }
}

// Wrapper function for debugPrint - matches the exact signature
void _debugPrintWrapper(String? text, {int? wrapWidth}) {
  // This is a placeholder to check if we've already set up the override
}
