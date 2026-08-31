import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/library_entities.dart';
import '../models/music_track.dart';

class MusicLibraryApi {
  MusicLibraryApi({this.baseUrl = 'https://musiclibrary-api.dev.tarabora.eu', http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  final Map<String, Future<String?>> _artistImageCache = {};
  final Map<String, Future<String?>> _albumImageCache = {};

  Future<List<ArtistSummary>> fetchArtists({int pageSize = 100}) {
    return _fetchAllPages(
      path: '/api/Artists',
      pageSize: pageSize,
      parser: ArtistSummary.fromJson,
    );
  }

  Future<List<AlbumSummary>> fetchAlbums({int pageSize = 100}) {
    return _fetchAllPages(
      path: '/api/Albums',
      pageSize: pageSize,
      parser: AlbumSummary.fromJson,
    );
  }

  Future<List<MusicTrack>> fetchSongs({int pageNumber = 1, int pageSize = 20}) async {
    final response = await _client.get(
      _buildUri(
        '/api/Songs',
        queryParameters: pageSize > 0
            ? <String, String>{
                'pageNumber': '$pageNumber',
                'pageSize': '$pageSize',
              }
            : null,
      ),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load /api/Songs (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    final items = decoded is List
        ? decoded
        : (decoded as Map<String, dynamic>? ?? const <String, dynamic>{})['items']
                as List<dynamic>? ??
            const <dynamic>[];

    final tracks = items
        .map((item) =>
            MusicTrack.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();

    if (pageSize <= 0) {
      return tracks;
    }

    final normalizedPageNumber = pageNumber > 0 ? pageNumber : 1;
    final startIndex = (normalizedPageNumber - 1) * pageSize;
    final endIndex = startIndex + pageSize;

    if (startIndex >= tracks.length) {
      return const <MusicTrack>[];
    }

    return tracks
        .sublist(startIndex, endIndex > tracks.length ? tracks.length : endIndex)
        .toList(growable: false);
  }

  Future<List<String>> fetchSongTags(String songId) async {
    final response = await _client.get(
      _buildUri('/api/songs/$songId/tags'),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load /api/songs/$songId/tags (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      return const <String>[];
    }

    final tags = <String>[];
    for (final tag in decoded) {
      if (tag is Map) {
        final name = tag['name']?.toString().trim() ?? '';
        if (name.isNotEmpty) {
          tags.add(name);
        }
      }
    }

    return tags;
  }

  String streamSongUrl(String songId) {
    return _buildUri('/api/MusicStream/stream/$songId').toString();
  }

  Future<String?> lookupArtistImage(String artistName) {
    return _artistImageCache.putIfAbsent(
        artistName, () => _lookupArtistImage(artistName));
  }

  Future<String?> lookupAlbumImage(AlbumSummary album) {
    final cacheKey =
        '${album.id}:${album.musicBrainzId ?? album.title}:${album.artistName}';
    return _albumImageCache.putIfAbsent(
        cacheKey, () => _lookupAlbumImage(album));
  }

  Future<List<T>> _fetchAllPages<T>({
    required String path,
    required int pageSize,
    required T Function(Map<String, dynamic>) parser,
  }) async {
    final items = <T>[];
    var pageNumber = 1;

    while (true) {
      final response = await _client.get(
        _buildUri(
          path,
          queryParameters: <String, String>{
            'pageNumber': '$pageNumber',
            'pageSize': '$pageSize',
          },
        ),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to load $path (${response.statusCode})');
      }

      final decoded = _decodeBody(response.body);
      final responseItems = (decoded['items'] as List<dynamic>? ?? const []);

      for (final item in responseItems) {
        items.add(parser(Map<String, dynamic>.from(item as Map)));
      }

      final hasNextPage = decoded['hasNextPage'] as bool? ?? false;
      if (!hasNextPage || responseItems.isEmpty) {
        return items;
      }

      pageNumber++;
    }
  }

  Future<String?> _lookupArtistImage(String artistName) async {
    final searchResult = await _getJson(
      'https://en.wikipedia.org/w/api.php',
      queryParameters: <String, String>{
        'action': 'query',
        'list': 'search',
        'srsearch': artistName,
        'format': 'json',
        'origin': '*',
      },
    );

    final searchResults =
        searchResult['query']?['search'] as List<dynamic>? ?? const [];
    if (searchResults.isEmpty) {
      return null;
    }

    final pageId = searchResults.first['pageid']?.toString();
    if (pageId == null) {
      return null;
    }

    final pageResult = await _getJson(
      'https://en.wikipedia.org/w/api.php',
      queryParameters: <String, String>{
        'action': 'query',
        'pageids': pageId,
        'prop': 'pageimages',
        'pithumbsize': '720',
        'format': 'json',
        'origin': '*',
      },
    );

    final pages = pageResult['query']?['pages'] as Map<String, dynamic>?;
    final page = pages?[pageId] as Map<String, dynamic>?;
    return page?['thumbnail']?['source'] as String?;
  }

  Future<String?> _lookupAlbumImage(AlbumSummary album) async {
    final musicBrainzId = album.musicBrainzId;
    if (musicBrainzId != null && musicBrainzId.isNotEmpty) {
      return 'https://coverartarchive.org/release/$musicBrainzId/front-250';
    }

    final searchResult = await _getJson(
      'https://musicbrainz.org/ws/2/release/',
      queryParameters: <String, String>{
        'query': 'release:${album.title} AND artist:${album.artistName}',
        'fmt': 'json',
        'limit': '1',
      },
      headers: const <String, String>{
        'User-Agent': 'AudioPlayer/1.0 (local-development)',
      },
    );

    final releases =
        searchResult['releases'] as List<dynamic>? ?? const [];
    if (releases.isEmpty) {
      return album.coverImageUrl;
    }

    final firstRelease = releases.first as Map<String, dynamic>;
    final releaseId = firstRelease['id'] as String?;
    if (releaseId == null || releaseId.isEmpty) {
      return album.coverImageUrl;
    }

    return 'https://coverartarchive.org/release/$releaseId/front-250';
  }

  Uri _buildUri(String path, {Map<String, String>? queryParameters}) {
    final root = baseUrl.replaceAll(RegExp(r'/$'), '');
    return Uri.parse('$root$path').replace(queryParameters: queryParameters);
  }

  Future<Map<String, dynamic>> _getJson(
    String url, {
    Map<String, String>? queryParameters,
    Map<String, String>? headers,
  }) async {
    final response = await _client.get(
      Uri.parse(url).replace(queryParameters: queryParameters),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception(
          'Failed to load ${response.request?.url} (${response.statusCode})');
    }

    return _decodeBody(response.body);
  }

  static Map<String, dynamic> _decodeBody(String body) {
    final data = jsonDecode(body);
    if (data is Map<String, dynamic>) {
      return data;
    }
    return <String, dynamic>{};
  }
}
