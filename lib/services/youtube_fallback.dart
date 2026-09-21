import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Service for handling YouTube playback when local files are unavailable.
/// 
/// This service can either:
/// 1. Search and play YouTube videos in-app using a small floating player
/// 2. Open YouTube videos in the user's default browser
class YouTubeFallback {
  final YoutubeExplode _yt = YoutubeExplode();
  bool _isDisposed = false;

  /// Callback to show a floating YouTube player in the UI
  /// This is set by the UI to display the player
  Function(YoutubePlayerController, String, VoidCallback)? showFloatingPlayer;

  /// Search for a YouTube video matching the artist and title.
  /// 
  /// If [showFloatingPlayer] callback is set, displays an in-app player.
  /// Otherwise, returns the YouTube URL for external playback.
  Future<String?> searchAndPlay(String artist, String title) async {
    if (_isDisposed) {
      throw StateError('YouTubeFallback has been disposed');
    }

    try {
      // Build search query: "Artist - Title"
      final query = '$artist - $title';
      
      // Search for videos matching the query
      final search = _yt.search;
      final videoSearchList = await search.search(query);
      
      Video? video;
      if (videoSearchList.isNotEmpty) {
        video = videoSearchList.first;
        debugPrint('YouTube fallback: Found video "${video.title}" for "$artist - $title"');
      } else {
        // Try without the dash separator
        final fallbackQuery = '$artist $title';
        debugPrint('YouTube fallback: Trying fallback query "$fallbackQuery"');
        final fallbackSearchList = await search.search(fallbackQuery);
        video = fallbackSearchList.isNotEmpty ? fallbackSearchList.first : null;
        if (video != null) {
          debugPrint('YouTube fallback: Found video "${video.title}" for "$fallbackQuery"');
        }
      }
      
      if (video == null) {
        debugPrint('YouTube fallback: No videos found for "$artist - $title"');
        return null;
      }
      
      final videoId = video.id.value;
      final youtubeUrl = 'https://www.youtube.com/watch?v=$videoId';
      
      // For desktop platforms (Linux, Windows, macOS), use browser as WebView has limitations
      // For mobile platforms (Android, iOS), use in-app player
      final isDesktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;
      
      if (isDesktop) {
        debugPrint('YouTube fallback: Desktop platform detected, opening in browser');
        if (await canLaunchUrl(Uri.parse(youtubeUrl))) {
          await launchUrl(Uri.parse(youtubeUrl), mode: LaunchMode.externalApplication);
          return youtubeUrl;
        }
        return null;
      }
      
      // If we have a callback to show floating player, use in-app playback (mobile only)
      if (showFloatingPlayer != null) {
        debugPrint('YouTube fallback: Starting in-app playback for ${video.title}');
        
        // Create the controller with the video ID
        final controller = YoutubePlayerController.fromVideoId(
          videoId: videoId,
          autoPlay: true,
          params: const YoutubePlayerParams(
            showControls: true,
            mute: false,
            loop: false,
          ),
        );
        
        // Show the floating player
        showFloatingPlayer!(controller, video.title, () {
          debugPrint('YouTube fallback: Floating player dismissed');
          controller.pauseVideo();
          controller.close();
        });
        
        return youtubeUrl;
      }
      
      // Otherwise return the URL for external playback
      return youtubeUrl;
    } catch (e) {
      debugPrint('YouTube fallback search failed: $e');
      return null;
    }
  }

  /// Set the callback to display a floating YouTube player.
  /// This should be called by the UI to enable in-app YouTube playback.
  void setFloatingPlayerCallback(
    Function(YoutubePlayerController, String, VoidCallback) callback,
  ) {
    showFloatingPlayer = callback;
  }

  /// Close the YouTube client to release resources.
  void dispose() {
    if (!_isDisposed) {
      _yt.close();
      _isDisposed = true;
    }
  }
}
