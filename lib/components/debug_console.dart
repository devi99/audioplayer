import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// Debug console overlay that displays debugPrint messages at the bottom of the screen.
/// Only active on mobile platforms (Android and iOS).
class DebugConsole extends StatefulWidget {
  const DebugConsole({super.key, this.enabled = true});

  final bool enabled;

  @override
  State<DebugConsole> createState() => _DebugConsoleState();
}

class _DebugConsoleState extends State<DebugConsole> {
  static const int _maxMessages = 100;
  static const double _consoleHeight = 100.0;
  static const double _toggleButtonSize = 48.0;

  final List<_DebugMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();

  // Original debugPrint function
  final dynamic _originalDebugPrint = debugPrint;

  bool _isDisposed = false;
  bool _isVisible = true;

  @override
  void initState() {
    super.initState();
    _setupDebugPrintOverride();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _restoreOriginalDebugPrint();
    _scrollController.dispose();
    super.dispose();
  }

  void _setupDebugPrintOverride() {
    // Only override on mobile platforms when enabled
    if (widget.enabled && (Platform.isAndroid || Platform.isIOS)) {
      debugPrint = _captureDebugPrint as dynamic;
    }
  }

  void _restoreOriginalDebugPrint() {
    // Only restore if we were the ones who changed it
    if (debugPrint == _captureDebugPrint) {
      debugPrint = _originalDebugPrint;
    }
  }

  void _captureDebugPrint(Object? object, {int wrapWidth = 0}) {
    // Call original debugPrint
    _originalDebugPrint?.call(object, wrapWidth: wrapWidth);

    // Add to our message list
    if (!_isDisposed && mounted) {
      final message = _DebugMessage(
        text: object.toString(),
        timestamp: DateTime.now(),
      );

      setState(() {
        _messages.add(message);
        // Limit messages to prevent memory issues
        if (_messages.length > _maxMessages) {
          _messages.removeRange(0, _messages.length - _maxMessages);
        }
      });

      // Auto-scroll to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  void _clearMessages() {
    setState(() {
      _messages.clear();
    });
  }

  void _toggleVisibility() {
    setState(() {
      _isVisible = !_isVisible;
    });
  }

  String _formatTime(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // Only show on mobile platforms when enabled
    if (!widget.enabled || !(Platform.isAndroid || Platform.isIOS)) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    // Calculate bottom offset to avoid overlapping with bottomNavigationBar on Android
    final bottomOffset = _getBottomOffset(context);

    // If not visible, just show the floating toggle button
    if (!_isVisible) {
      return Positioned(
        bottom: bottomOffset + 16,
        right: 16,
        child: _buildToggleButton(theme),
      );
    }

    return Stack(
      children: [
        // The console itself
        Positioned(
          left: 0,
          right: 0,
          bottom: bottomOffset,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            child: SizedBox(
              height: _consoleHeight,
              child: Material(
                elevation: 4,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    border: Border(
                      top: BorderSide(
                        color: theme.colorScheme.outline.withValues(alpha: 0.5),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Header with toggle and clear buttons
                      Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                _isVisible ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
                                size: 18,
                              ),
                              tooltip: _isVisible ? 'Hide console' : 'Show console',
                              onPressed: _toggleVisibility,
                              style: IconButton.styleFrom(
                                padding: const EdgeInsets.all(4),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                            Text(
                              'DEBUG CONSOLE',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16),
                              tooltip: 'Clear',
                              onPressed: _clearMessages,
                              style: IconButton.styleFrom(
                                padding: const EdgeInsets.all(4),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Message list
                      Expanded(
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            return Text(
                              '[${_formatTime(message.timestamp)}] ${message.text}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface,
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // Floating toggle button (shown when console is visible too, for easy access)
        Positioned(
          bottom: bottomOffset + _consoleHeight + 8,
          right: 16,
          child: _buildToggleButton(theme),
        ),
      ],
    );
  }

  double _getBottomOffset(BuildContext context) {
    // On Android, account for bottomNavigationBar height
    if (defaultTargetPlatform == TargetPlatform.android) {
      return kBottomNavigationBarHeight;
    }
    return 0.0;
  }

  Widget _buildToggleButton(ThemeData theme) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(_toggleButtonSize / 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(_toggleButtonSize / 2),
        onTap: _toggleVisibility,
        child: SizedBox(
          width: _toggleButtonSize,
          height: _toggleButtonSize,
          child: Icon(
            _isVisible ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
            size: 24,
          ),
        ),
      ),
    );
  }
}

class _DebugMessage {
  final String text;
  final DateTime timestamp;

  _DebugMessage({required this.text, required this.timestamp});
}
