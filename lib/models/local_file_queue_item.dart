class LocalFileQueueItem {
  const LocalFileQueueItem({
    required this.id,
    required this.fullFilePath,
    this.album,
    this.artist,
    this.title,
    this.isCurrentlyPlaying = false,
    this.queueOrder = 0,
  });

  final int id;
  final String fullFilePath;
  final String? album;
  final String? artist;
  final String? title;
  final bool isCurrentlyPlaying;
  final int queueOrder;

  factory LocalFileQueueItem.fromJson(Map<String, dynamic> json) {
    return LocalFileQueueItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      fullFilePath: (json['fullFilePath'] ?? '').toString(),
      album: json['album']?.toString(),
      artist: json['artist']?.toString(),
      title: json['title']?.toString(),
      isCurrentlyPlaying: json['isCurrentlyPlaying'] as bool? ?? false,
      queueOrder: (json['queueOrder'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fullFilePath': fullFilePath,
      'album': album,
      'artist': artist,
      'title': title,
      'isCurrentlyPlaying': isCurrentlyPlaying,
      'queueOrder': queueOrder,
    };
  }
}
