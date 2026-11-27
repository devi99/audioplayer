/// A song in the MPD queue.
///
/// MPD responses use capitalized keys with string values, e.g.:
/// `{"file": "Artist/Track.mp3", "Artist": "...", "Title": "...",
///   "Pos": "0", "Id": "455", "duration": "1212.029"}`
class MpdQueueItem {
  const MpdQueueItem({
    required this.file,
    this.artist,
    this.album,
    this.title,
    this.track,
    this.genre,
    this.date,
    this.durationSeconds,
    this.pos,
    this.id,
  });

  final String file;
  final String? artist;
  final String? album;
  final String? title;
  final String? track;
  final String? genre;
  final String? date;
  final double? durationSeconds;
  final int? pos;
  final int? id;

  /// File name without directory, used as fallback display title.
  String get fileName => file.split('/').last;

  static String? _string(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static double? _double(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int? _int(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  factory MpdQueueItem.fromJson(Map<String, dynamic> json) {
    return MpdQueueItem(
      file: json['file']?.toString() ?? '',
      artist: _string(json, 'Artist'),
      album: _string(json, 'Album'),
      title: _string(json, 'Title'),
      track: _string(json, 'Track'),
      genre: _string(json, 'Genre'),
      date: _string(json, 'Date'),
      durationSeconds: _double(json, 'duration') ?? _double(json, 'Time'),
      pos: _int(json, 'Pos'),
      id: _int(json, 'Id'),
    );
  }
}

/// Playback status of the MPD player, from `/api/Mpd/status`.
class MpdStatus {
  const MpdStatus({
    required this.state,
    this.volume,
    this.elapsedSeconds,
    this.durationSeconds,
    this.queueLength,
    this.random,
    this.consume,
    this.currentSong,
  });

  /// `play`, `pause`, or `stop`.
  final String state;
  final int? volume;
  final double? elapsedSeconds;
  final double? durationSeconds;
  final int? queueLength;
  final bool? random;
  final bool? consume;
  final MpdQueueItem? currentSong;

  bool get isPlaying => state == 'play';
  bool get isPaused => state == 'pause';

  factory MpdStatus.fromJson(Map<String, dynamic> json) {
    final currentSong = json['currentSong'];
    return MpdStatus(
      state: json['state']?.toString() ?? 'stop',
      volume: MpdQueueItem._int(json, 'volume'),
      elapsedSeconds: MpdQueueItem._double(json, 'elapsed'),
      durationSeconds: MpdQueueItem._double(json, 'duration'),
      queueLength: MpdQueueItem._int(json, 'queueLength'),
      random: json['random'] == 1 || json['random'] == '1' || json['random'] == true,
      consume:
          json['consume'] == 1 || json['consume'] == '1' || json['consume'] == true,
      currentSong: currentSong is Map && currentSong.isNotEmpty
          ? MpdQueueItem.fromJson(Map<String, dynamic>.from(currentSong))
          : null,
    );
  }
}
