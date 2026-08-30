class MusicTrack {
  const MusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationSeconds,
    required this.rating,
    required this.tags,
    this.streamUrl,
    this.stream,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final int durationSeconds;
  final int rating;
  final List<String> tags;
  final String? streamUrl;
  final String? stream;

  factory MusicTrack.fromJson(Map<String, dynamic> json) {
    return MusicTrack(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String,
      album: json['album'] as String,
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      tags: List<String>.from((json['tags'] as List<dynamic>? ?? const []).map((tag) => tag.toString())),
      streamUrl: json['streamUrl'] as String?,
      stream: json['stream'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'durationSeconds': durationSeconds,
      'rating': rating,
      'tags': tags,
      'streamUrl': streamUrl,
      'stream': stream,
    };
  }
}
