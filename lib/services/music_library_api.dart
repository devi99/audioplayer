import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/music_track.dart';

class MusicLibraryApi {
  MusicLibraryApi({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Future<List<MusicTrack>> fetchTracks() async {
    final response = await _client.get(Uri.parse('$baseUrl/tracks'));

    if (response.statusCode != 200) {
      throw Exception('Failed to load tracks (${response.statusCode})');
    }

    final decoded = _decodeBody(response.body);
    final tracks = decoded['tracks'] as List<dynamic>? ?? const [];
    return tracks
        .map((track) => MusicTrack.fromJson(Map<String, dynamic>.from(track as Map)))
        .toList();
  }

  static Map<String, dynamic> _decodeBody(String body) {
    final data = jsonDecode(body);
    if (data is Map<String, dynamic>) {
      return data;
    }
    return <String, dynamic>{'tracks': const <dynamic>[]};
  }
}
