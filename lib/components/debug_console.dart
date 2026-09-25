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
  bool _isVisible = false; // Start hidden by default

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

  double _getBottomOffset() {
    // On Android, account for bottomNavigationBar height
    if (defaultTargetPlatform == TargetPlatform.android) {
      return kBottomNavigationBarHeight + 16;
    }
    return 16;
  }

  @override
  Widget build(BuildContext context) {
    // Only show on mobile platforms when enabled
    if (!widget.enabled || !(Platform.isAndroid || Platform.isIOS)) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // The console panel - only when visible
        if (_isVisible)
          Positioned(
            left: 0,
            right: 0,
            bottom: _getBottomOffset(),
            height: _consoleHeight,
            child: _buildConsolePanel(theme),
          ),
        // Floating toggle button
        Positioned(
          bottom: _isVisible ? _getBottomOffset() + _consoleHeight + 8 : _getBottomOffset(),
          right: 16,
          child: _buildToggleButton(theme),
        ),
      ],
    );
  }

  Widget _buildConsolePanel(ThemeData theme) {
    return IgnorePointer(
      child: Container(
        height: _consoleHeight,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black87,
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
        ),
        child: Column(
          children: [
            // Header with buttons
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                    tooltip: 'Hide console',
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
                      color: Colors.white,
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
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 10,
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
    );
  }

  Widget _buildToggleButton(ThemeData theme) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(_toggleButtonSize / 2),
      color: theme.colorScheme.primary,
      child: InkWell(
        borderRadius: BorderRadius.circular(_toggleButtonSize / 2),
        onTap: _toggleVisibility,
        child: SizedBox(
          width: _toggleButtonSize,
          height: _toggleButtonSize,
          child: Icon(
            _isVisible ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
            size: 24,
            color: Colors.white,
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
