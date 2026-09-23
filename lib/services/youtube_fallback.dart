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
  
  // Cache for YouTube search results: artist+title -> videoId
  // Prevents repeated searches for the same song
  final Map<String, String> _searchCache = {};
  
  // Pending searches to avoid duplicate concurrent searches
  final Set<String> _pendingSearches = {};

  /// Callback to show a floating YouTube player in the UI
  /// This is set by the UI to display the player
  Function(YoutubePlayerController, String, VoidCallback)? showFloatingPlayer;

  /// Callback for loading state changes
  /// UI can use this to show/hide a loading indicator
  Function(bool)? onLoadingChanged;

  /// Callback for error messages
  /// UI can use this to display error toasts
  Function(String)? onError;

  /// Search for a YouTube video matching the artist and title.
  /// 
  /// If [showFloatingPlayer] callback is set, displays an in-app player.
  /// Otherwise, returns the YouTube URL for external playback.
  Future<String?> searchAndPlay(String artist, String title) async {
    if (_isDisposed) {
      throw StateError('YouTubeFallback has been disposed');
    }

    // Create a cache key from artist and title
    final cacheKey = '$artist|$title'.toLowerCase();
    
    // Check cache first
    if (_searchCache.containsKey(cacheKey)) {
      debugPrint('YouTube fallback: Using cached result for "$artist - $title"');
      final videoId = _searchCache[cacheKey]!;
      return _playFromVideoId(videoId, artist, title);
    }
    
    // Prevent duplicate concurrent searches for the same song
    if (_pendingSearches.contains(cacheKey)) {
      debugPrint('YouTube fallback: Search already in progress for "$artist - $title"');
      // Wait a bit and check cache again (another call might have completed)
      await Future.delayed(const Duration(milliseconds: 100));
      if (_searchCache.containsKey(cacheKey)) {
        final videoId = _searchCache[cacheKey]!;
        return _playFromVideoId(videoId, artist, title);
      }
    }
    
    _pendingSearches.add(cacheKey);

    try {
      // Emit loading started
      onLoadingChanged?.call(true);
      debugPrint('YouTube fallback: Starting search for "$artist - $title"');

      // Wrap search in timeout - max 15 seconds
      Video? video;
      try {
        video = await _searchYouTubeWithTimeout(artist, title).timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            debugPrint('YouTube fallback: Search timed out for "$artist - $title"');
            throw TimeoutException('YouTube search timed out after 15 seconds', const Duration(seconds: 15));
          },
        );
      } on TimeoutException {
        // Try once more with a simpler query
        debugPrint('YouTube fallback: Retrying with simpler query');
        video = await _searchYouTubeWithTimeout(artist, title, useSimpleQuery: true).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException('YouTube search timed out after retry', const Duration(seconds: 10));
          },
        );
      }
      
      if (video == null) {
        // Emit error
        onError?.call('No YouTube video found for "$artist - $title"');
        debugPrint('YouTube fallback: No videos found for "$artist - $title"');
        onLoadingChanged?.call(false);
        return null;
      }
      
      // Cache the result
      final videoId = video.id.value;
      _searchCache[cacheKey] = videoId;
      debugPrint('YouTube fallback: Cached video ID $videoId for "$artist - $title"');
      
      return await _playFromVideoId(videoId, artist, title);
      
    } catch (e) {
      // Emit error
      onError?.call('YouTube search failed: $e');
      onLoadingChanged?.call(false);
      debugPrint('YouTube fallback search failed: $e');
      return null;
    } finally {
      _pendingSearches.remove(cacheKey);
    }
  }
  
  /// Perform the actual YouTube search with configurable query format
  Future<Video?> _searchYouTubeWithTimeout(String artist, String title, {bool useSimpleQuery = false}) async {
    final search = _yt.search;
    
    // Try primary query format
    String query;
    if (useSimpleQuery) {
      query = '$artist $title';
    } else {
      query = '$artist - $title';
    }
    
    debugPrint('YouTube fallback: Searching with query "$query"');
    final videoSearchList = await search.search(query);
    
    if (videoSearchList.isNotEmpty) {
      return videoSearchList.first;
    }
    
    // Try fallback query if primary failed
    if (!useSimpleQuery) {
      final fallbackQuery = '$artist $title';
      debugPrint('YouTube fallback: Trying fallback query "$fallbackQuery"');
      final fallbackSearchList = await search.search(fallbackQuery);
      if (fallbackSearchList.isNotEmpty) {
        return fallbackSearchList.first;
      }
    }
    
    return null;
  }
  
  /// Play a video given its video ID
  Future<String?> _playFromVideoId(String videoId, String artist, String title) async {
    final youtubeUrl = 'https://www.youtube.com/watch?v=$videoId';
    
    // For desktop platforms (Linux, Windows, macOS), use browser as WebView has limitations
    // For mobile platforms (Android, iOS), use in-app player
    final isDesktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;
    
    if (isDesktop) {
      debugPrint('YouTube fallback: Desktop platform detected, opening in browser');
      if (await canLaunchUrl(Uri.parse(youtubeUrl))) {
        await launchUrl(Uri.parse(youtubeUrl), mode: LaunchMode.externalApplication);
        onLoadingChanged?.call(false);
        return youtubeUrl;
      }
      onError?.call('Could not open browser for YouTube video');
      onLoadingChanged?.call(false);
      return null;
    }
    
    // If we have a callback to show floating player, use in-app playback (mobile only)
    if (showFloatingPlayer != null) {
      debugPrint('YouTube fallback: Starting in-app playback for video ID $videoId');
      
      try {
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
        showFloatingPlayer!(controller, '$artist - $title', () {
          debugPrint('YouTube fallback: Floating player dismissed');
          controller.pauseVideo();
          controller.close();
          onLoadingChanged?.call(false);
        });
        
        onLoadingChanged?.call(false);
        return youtubeUrl;
      } catch (e) {
        onError?.call('Failed to initialize YouTube player: $e');
        onLoadingChanged?.call(false);
        return null;
      }
    }
    
    // Otherwise return the URL for external playback
    onLoadingChanged?.call(false);
    return youtubeUrl;
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
