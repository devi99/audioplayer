class MusicTrack {
  const MusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationSeconds,
    required this.rankOrder,
    required this.tags,
    this.streamUrl,
    this.stream,
    this.filePath,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final int durationSeconds;
  final double rankOrder;
  final List<String> tags;
  final String? streamUrl;
  final String? stream;
  final String? filePath;

  int tier() {
    if (rankOrder >= 0 && rankOrder < 1) {
      return 1;
    }
    if (rankOrder >= 1 && rankOrder < 2) {
      return 2;
    }
    if (rankOrder >= 2 && rankOrder < 3) {
      return 3;
    }
    if (rankOrder >= 3 && rankOrder < 4) {
      return 4;
    }
    if (rankOrder >= 4 && rankOrder <= 5) {
      return 5;
    }
    return 0;
  }

  String starDisplay() {
    final filledStars = tier();
    final emptyStars = 5 - filledStars;
    return '${'★' * filledStars}${'☆' * emptyStars}';
  }

  factory MusicTrack.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'] ?? json['songId'];
    final rawDuration = json['durationSeconds'] ?? json['songLength'];
    final rawTags = json['tags'];
    final rawRankOrder = json['rankOrder'];

    final parsedRankOrder = switch (rawRankOrder) {
      null => -1.0,
      num value => value.toDouble(),
      _ => double.tryParse(rawRankOrder.toString()) ?? -1.0,
    };

    return MusicTrack(
      id: rawId?.toString() ?? '',
      title: (json['title'] ?? '').toString(),
      artist:
          (json['artist'] ?? json['artistName'] ?? 'Unknown artist').toString(),
      album: (json['album'] ?? json['albumTitle'] ?? '').toString(),
      durationSeconds: rawDuration is num
          ? rawDuration.toInt()
          : int.tryParse(rawDuration?.toString() ?? '') ?? 0,
      rankOrder: parsedRankOrder,
      tags: rawTags is List
          ? List<String>.from(rawTags.map((tag) => tag.toString()))
          : const <String>[],
      streamUrl:
          json['streamUrl']?.toString() ?? json['stream_url']?.toString(),
      stream: json['stream']?.toString(),
      filePath: json['filePath']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'durationSeconds': durationSeconds,
      'rankOrder': rankOrder,
      'tags': tags,
      'streamUrl': streamUrl,
      'stream': stream,
      'filePath': filePath,
    };
  }
}
