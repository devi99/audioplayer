import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class SongCache {
  static const String _cacheDirName = 'song_cache';
  static const int _maxCacheSizeMb = 10240; // 10GB cache limit (10 * 1024)
  static const int _maxConcurrentDownloads = 3;

  final Map<String, String> _filePathCache = {}; // songId -> local file path
  final Map<String, bool> _downloadInProgress = {}; // songId -> is downloading
  int _activeDownloads = 0;

  Future<String> getCacheDirectory() async {
    final cacheDir = await getApplicationCacheDirectory();
    final songCacheDir = Directory(path.join(cacheDir.path, _cacheDirName));

    if (await songCacheDir.exists()) {
      return songCacheDir.path;
    }

    await songCacheDir.create(recursive: true);
    return songCacheDir.path;
  }

  Future<String?> getCachedFilePath(String songId) async {
    // Check in-memory cache first
    if (_filePathCache.containsKey(songId)) {
      final cachedPath = _filePathCache[songId]!;
      final file = File(cachedPath);
      if (await file.exists()) {
        return cachedPath;
      }
      // File doesn't exist, remove from cache
      _filePathCache.remove(songId);
    }

    // Check filesystem
    final cacheDir = await getCacheDirectory();
    final sanitizedSongId = _sanitizeFilename(songId);
    final filePath = path.join(cacheDir, '$sanitizedSongId.mp3');
    final file = File(filePath);

    if (await file.exists()) {
      // Update in-memory cache
      _filePathCache[songId] = filePath;
      return filePath;
    }

    return null;
  }

  Future<String> downloadAndCache(String songId, String streamUrl) async {
    // Check if already downloading
    if (_downloadInProgress[songId] == true) {
      // Wait for existing download to complete
      while (_downloadInProgress[songId] == true) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      // Check if download completed successfully
      final cachedPath = await getCachedFilePath(songId);
      if (cachedPath != null) {
        return cachedPath;
      }
    }

    // Limit concurrent downloads
    while (_activeDownloads >= _maxConcurrentDownloads) {
      await Future.delayed(const Duration(milliseconds: 200));
    }

    _downloadInProgress[songId] = true;
    _activeDownloads++;

    try {
      final cacheDir = await getCacheDirectory();
      final sanitizedSongId = _sanitizeFilename(songId);
      final filePath = path.join(cacheDir, '$sanitizedSongId.mp3');
      final tempFilePath = '$filePath.tmp';

      // Check cache size limit before downloading
      await _checkAndCleanCache();

      final dio = Dio();
      
      await dio.download(
        streamUrl,
        tempFilePath,
        options: Options(
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 10),
        ),
        onReceiveProgress: (received, total) {
          // Progress callback can be added here if needed
        },
      );

      // Verify the downloaded file
      final tempFile = File(tempFilePath);
      if (await tempFile.exists() && await tempFile.length() > 0) {
        // Rename temp file to final file
        await tempFile.rename(filePath);
        
        // Update in-memory cache
        _filePathCache[songId] = filePath;
        
        return filePath;
      } else {
        // Clean up partial download
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        throw Exception('Downloaded file is empty or invalid');
      }
    } catch (e) {
      // Clean up any partial download
      try {
        final cacheDir = await getCacheDirectory();
        final sanitizedSongId = _sanitizeFilename(songId);
        final tempFilePath = path.join(cacheDir, '$sanitizedSongId.mp3.tmp');
        final tempFile = File(tempFilePath);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {
        // Ignore cleanup errors
      }
      rethrow;
    } finally {
      _downloadInProgress.remove(songId);
      _activeDownloads--;
    }
  }

  Future<bool> isCached(String songId) async {
    return await getCachedFilePath(songId) != null;
  }

  Future<void> clearCache() async {
    try {
      final cacheDir = Directory(await getCacheDirectory());
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        await cacheDir.create(recursive: true);
      }
      _filePathCache.clear();
    } catch (e) {
      // Ignore errors during cache clearing
    }
  }

  Future<void> removeFromCache(String songId) async {
    try {
      if (_filePathCache.containsKey(songId)) {
        final filePath = _filePathCache[songId]!;
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
        _filePathCache.remove(songId);
      }

      // Also try to remove from filesystem directly
      final cacheDir = await getCacheDirectory();
      final sanitizedSongId = _sanitizeFilename(songId);
      final filePath = path.join(cacheDir, '$sanitizedSongId.mp3');
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // Ignore errors during cache removal
    }
  }

  Future<void> _checkAndCleanCache() async {
    try {
      final cacheDir = Directory(await getCacheDirectory());
      if (!await cacheDir.exists()) {
        return;
      }

      // Calculate total cache size
      int totalSize = 0;
      final files = <File>[];
      
      await for (final entity in cacheDir.list(recursive: false)) {
        if (entity is File) {
          final size = await entity.length();
          totalSize += size;
          files.add(entity);
        }
      }

      const maxSizeBytes = _maxCacheSizeMb * 1024 * 1024;
      if (totalSize < maxSizeBytes) {
        return;
      }

      // Sort files by modification time (oldest first)
      files.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));

      // Remove oldest files until cache is under limit
      for (final file in files) {
        if (totalSize < maxSizeBytes) {
          break;
        }
        
        final fileSize = await file.length();
        await file.delete();
        totalSize -= fileSize;
        
        // Remove from in-memory cache
        final fileName = path.basenameWithoutExtension(file.path);
        _filePathCache.remove(fileName);
      }
    } catch (e) {
      // Ignore errors during cache cleanup
    }
  }

  String _sanitizeFilename(String input) {
    // Replace characters that are not allowed in filenames
    return input
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'^[\.]+'), '_');
  }

  // Get current cache size in bytes
  Future<int> getCacheSize() async {
    try {
      final cacheDir = Directory(await getCacheDirectory());
      if (!await cacheDir.exists()) {
        return 0;
      }

      int totalSize = 0;
      await for (final entity in cacheDir.list(recursive: false)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      return totalSize;
    } catch (e) {
      return 0;
    }
  }

  // Get list of cached song IDs
  Future<List<String>> getCachedSongIds() async {
    try {
      final cacheDir = Directory(await getCacheDirectory());
      if (!await cacheDir.exists()) {
        return [];
      }

      final songIds = <String>[];
      await for (final entity in cacheDir.list(recursive: false)) {
        if (entity is File) {
          final fileName = path.basenameWithoutExtension(entity.path);
          // Remove .tmp extension if present
          if (fileName.endsWith('.tmp')) {
            continue;
          }
          songIds.add(fileName);
        }
      }
      return songIds;
    } catch (e) {
      return [];
    }
  }
}