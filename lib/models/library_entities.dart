class ArtistSummary {
  const ArtistSummary({
    required this.id,
    required this.name,
    required this.albumCount,
    this.singleTrackCount = 0,
    this.musicBrainzId,
  });

  final int id;
  final String name;
  final int albumCount;
  final int singleTrackCount;
  final String? musicBrainzId;

  factory ArtistSummary.fromJson(Map<String, dynamic> json) {
    return ArtistSummary(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      albumCount: (json['albumCount'] as num?)?.toInt() ?? 0,
      singleTrackCount: (json['singleTrackCount'] as num?)?.toInt() ?? 0,
      musicBrainzId: json['musicBrainzId'] as String?,
    );
  }
}

class AlbumSummary {
  const AlbumSummary({
    required this.id,
    required this.title,
    required this.artistName,
    this.musicBrainzId,
    this.coverImageUrl,
    this.songCount,
  });

  final int id;
  final String title;
  final String artistName;
  final String? musicBrainzId;
  final String? coverImageUrl;
  final int? songCount;

  factory AlbumSummary.fromJson(Map<String, dynamic> json) {
    return AlbumSummary(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String,
      artistName: json['artistName'] as String? ?? 'Unknown artist',
      musicBrainzId: json['musicBrainzId'] as String?,
      coverImageUrl: json['coverImageUrl'] as String?,
      songCount: (json['songCount'] as num?)?.toInt(),
    );
  }
}

class SingleTrackSummary {
  const SingleTrackSummary({
    required this.id,
    required this.title,
    required this.artistName,
    this.rankOrder,
    this.releaseDate,
    this.localFilePath,
  });

  final int id;
  final String title;
  final String artistName;
  final double? rankOrder;
  final String? releaseDate;
  final String? localFilePath;

  factory SingleTrackSummary.fromJson(Map<String, dynamic> json) {
    return SingleTrackSummary(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String,
      artistName: json['artistName'] as String? ?? 'Unknown artist',
      rankOrder: json['rankOrder'] != null 
          ? (json['rankOrder'] is num 
              ? (json['rankOrder'] as num).toDouble() 
              : double.tryParse(json['rankOrder'].toString())) 
          : null,
      releaseDate: json['releaseDate'] as String?,
      localFilePath: json['localFilePath'] as String?,
    );
  }
}
