import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:audioplayer/models/library_entities.dart';
import 'package:audioplayer/models/music_track.dart';
import 'package:audioplayer/screens/library_screen.dart';
import 'package:audioplayer/services/music_library_api.dart';

void main() {
  testWidgets('switches between artists and albums in the navigation pane',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(api: FakeMusicLibraryApi()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Artists'), findsWidgets);
    expect(find.text('Albums'), findsWidgets);
    expect(find.text('2 artists in your library'), findsOneWidget);

    await tester.tap(find.text('Albums').first);
    await tester.pumpAndSettle();

    expect(find.text('2 albums in your library'), findsOneWidget);
    expect(find.text('Night Drive'), findsOneWidget);
  });

  testWidgets('shows Songs in the navigation pane and paginates song results',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(api: FakeMusicLibraryApi()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Songs'), findsOneWidget);

    await tester.tap(find.text('Songs').first);
    await tester.pumpAndSettle();

    expect(find.text('Songs'), findsWidgets);
    expect(find.text('Sunset Glow'), findsOneWidget);
    expect(find.text('Aster'), findsWidgets);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Song 21'), findsOneWidget);
  });

  testWidgets('opens an album detail view and returns to the album list',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(api: FakeMusicLibraryApi()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Albums').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Night Drive').first);
    await tester.pumpAndSettle();

    expect(find.text('Album songs'), findsOneWidget);
    expect(find.text('Sunset Glow'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Night Drive'), findsOneWidget);
    expect(find.text('Albums'), findsWidgets);
  });

  testWidgets('shows Play in navigation and builds a tier-specific queue',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(api: TieredMusicLibraryApi()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Play'), findsOneWidget);

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    expect(find.text('3 queued songs'), findsOneWidget);
    expect(find.text('Tier 1 No Filepath Song'), findsNothing);
    expect(find.text('Tier 1'), findsOneWidget);

    await tester.tap(find.text('Tier 2'));
    await tester.pumpAndSettle();

    expect(find.text('1 queued songs'), findsOneWidget);
    expect(find.text('Tier 2 Song'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
    await tester.pumpAndSettle();

    expect(find.text('0 queued songs'), findsOneWidget);
    expect(find.text('No songs in this tier.'), findsOneWidget);
  });

  testWidgets('updates now playing and advances with Next in Play queue',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(api: TieredMusicLibraryApi()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Now Playing: Nothing currently playing'),
        findsOneWidget);

    await tester.tap(find.text('Play Queue'));
    await tester.pumpAndSettle();

    expect(
        find.textContaining('Now Playing: Tier 1 Null Song'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Now Playing: Tier 1 Negative Song'),
      findsOneWidget,
    );
  });

  testWidgets('disables play for songs without a stream source',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(api: BrokenStreamMusicLibraryApi()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Songs').first);
    await tester.pumpAndSettle();

    final playButton = tester.widget<IconButton>(find.byType(IconButton).first);
    expect(playButton.onPressed, isNull);
  });

  testWidgets('shows star rankOrders for each song tier',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(api: FakeMusicLibraryApi()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Songs').first);
    await tester.pumpAndSettle();

    expect(find.text('★★★★'), findsWidgets);
  });

  test('uses the working non-WAV stream endpoint', () {
    final api = MusicLibraryApi();
    expect(
      api.streamSongUrl('2000'),
      'https://musiclibrary-api.dev.tarabora.eu/api/MusicStream/stream/2000',
    );
  });

  test('fetches the requested song page slice from the API response', () async {
    final api = PageAwareMusicLibraryApi();

    final pageOne = await api.fetchSongs(pageNumber: 1, pageSize: 2);
    final pageTwo = await api.fetchSongs(pageNumber: 2, pageSize: 2);

    expect(pageOne.map((song) => song.title).toList(), <String>[
      'Track 1',
      'Track 2',
    ]);
    expect(pageTwo.map((song) => song.title).toList(), <String>[
      'Track 3',
      'Track 4',
    ]);
  });

  test('keeps fractional rankOrder values without truncating them', () {
    final track = MusicTrack.fromJson({
      'id': '42',
      'title': 'Fractional Rank',
      'artist': 'Tester',
      'album': 'Demo',
      'durationSeconds': 180,
      'rankOrder': 2.5,
      'tags': ['demo'],
    });

    expect(track.rankOrder, 2.5);
    expect(track.tier(), 3);
  });
}

class PageAwareMusicLibraryApi extends MusicLibraryApi {
  @override
  Future<List<MusicTrack>> fetchSongs({
    int pageNumber = 1,
    int pageSize = 20,
  }) async {
    const totalTracks = <MusicTrack>[
      MusicTrack(
        id: '1',
        title: 'Track 1',
        artist: 'A',
        album: 'A',
        durationSeconds: 10,
        rankOrder: 0,
        tags: ['t'],
      ),
      MusicTrack(
        id: '2',
        title: 'Track 2',
        artist: 'A',
        album: 'A',
        durationSeconds: 10,
        rankOrder: 0,
        tags: ['t'],
      ),
      MusicTrack(
        id: '3',
        title: 'Track 3',
        artist: 'A',
        album: 'A',
        durationSeconds: 10,
        rankOrder: 0,
        tags: ['t'],
      ),
      MusicTrack(
        id: '4',
        title: 'Track 4',
        artist: 'A',
        album: 'A',
        durationSeconds: 10,
        rankOrder: 0,
        tags: ['t'],
      ),
    ];

    final startIndex = (pageNumber - 1) * pageSize;
    if (startIndex >= totalTracks.length) {
      return const <MusicTrack>[];
    }

    final endIndex = startIndex + pageSize > totalTracks.length
        ? totalTracks.length
        : startIndex + pageSize;

    return totalTracks.sublist(startIndex, endIndex).toList(growable: false);
  }
}

class BrokenStreamMusicLibraryApi extends MusicLibraryApi {
  @override
  Future<List<MusicTrack>> fetchSongs({
    int pageNumber = 1,
    int pageSize = 20,
  }) async {
    return const <MusicTrack>[
      MusicTrack(
        id: '999999',
        title: 'Missing Stream',
        artist: 'Broken API',
        album: 'No File',
        durationSeconds: 124,
        rankOrder: 0,
        tags: ['broken'],
      ),
    ];
  }

  @override
  String streamSongUrl(String songId) {
    return 'https://musiclibrary-api.dev.tarabora.eu/api/MusicStream/stream-wav/$songId';
  }
}

class FakeMusicLibraryApi extends MusicLibraryApi {
  @override
  Future<List<ArtistSummary>> fetchArtists({int pageSize = 100}) async {
    return const <ArtistSummary>[
      ArtistSummary(id: 1, name: 'Aster', albumCount: 2),
      ArtistSummary(id: 2, name: 'Brazen', albumCount: 1),
    ];
  }

  @override
  Future<List<AlbumSummary>> fetchAlbums({int pageSize = 100}) async {
    return const <AlbumSummary>[
      AlbumSummary(id: 1, title: 'Night Drive', artistName: 'Aster'),
      AlbumSummary(id: 2, title: 'Daylight', artistName: 'Aster'),
    ];
  }

  @override
  Future<List<MusicTrack>> fetchSongs({
    int pageNumber = 1,
    int pageSize = 20,
  }) async {
    final allTracks = <MusicTrack>[
      for (var index = 1; index <= 25; index++)
        MusicTrack(
          id: '$index',
          title: index == 1
              ? 'Sunset Glow'
              : index == 2
                  ? 'Moonlit Echo'
                  : 'Song $index',
          artist: index <= 5 ? 'Aster' : 'Brazen',
          album: index <= 10 ? 'Night Drive' : 'Daylight',
          durationSeconds: 210,
          rankOrder: 4,
          tags: ['ambient'],
          filePath: index <= 3 ? '/music/$index.mp3' : null,
        ),
    ];

    if (pageSize <= 0) {
      return allTracks;
    }

    final startIndex = (pageNumber - 1) * pageSize;
    if (startIndex >= allTracks.length) {
      return const <MusicTrack>[];
    }

    final endIndex = startIndex + pageSize > allTracks.length
        ? allTracks.length
        : startIndex + pageSize;

    return allTracks.sublist(startIndex, endIndex).toList(growable: false);
  }

  @override
  Future<List<MusicTrack>> fetchAlbumSongs(int albumId) async {
    final allTracks = await fetchSongs(pageSize: 0);
    return allTracks
        .where((song) =>
            song.album == 'Night Drive' && albumId == 1 ||
            song.album == 'Daylight' && albumId == 2)
        .toList(growable: false);
  }

  @override
  Future<String?> lookupAlbumImage(AlbumSummary album) async {
    return null;
  }

  @override
  Future<String?> lookupArtistImage(String artistName) async {
    return null;
  }
}

class TieredMusicLibraryApi extends MusicLibraryApi {
  @override
  Future<List<MusicTrack>> fetchSongs({
    int pageNumber = 1,
    int pageSize = 20,
  }) async {
    final missingRank = MusicTrack.fromJson({
      'id': 't1-null',
      'title': 'Tier 1 Null Song',
      'artist': 'Tier Tester',
      'album': 'Tier Album',
      'durationSeconds': 180,
      'filePath': '/stream/t1-null.mp3',
      'tags': ['tier'],
    });

    return <MusicTrack>[
      missingRank,
      const MusicTrack(
        id: 't1-negative',
        title: 'Tier 1 Negative Song',
        artist: 'Tier Tester',
        album: 'Tier Album',
        durationSeconds: 181,
        rankOrder: -0.5,
        filePath: '/stream/t1-negative.mp3',
        tags: ['tier'],
      ),
      const MusicTrack(
        id: 't2',
        title: 'Tier 2 Song',
        artist: 'Tier Tester',
        album: 'Tier Album',
        durationSeconds: 182,
        rankOrder: 0.2,
        filePath: '/stream/t2.mp3',
        tags: ['tier'],
      ),
      const MusicTrack(
        id: 't1-no-file',
        title: 'Tier 1 No Filepath Song',
        artist: 'Tier Tester',
        album: 'Tier Album',
        durationSeconds: 182,
        rankOrder: -0.2,
        tags: ['tier'],
      ),
      const MusicTrack(
        id: 't1-negative-2',
        title: 'Tier 1 Negative Song B',
        artist: 'Tier Tester',
        album: 'Tier Album',
        durationSeconds: 183,
        rankOrder: -0.1,
        filePath: '/stream/t1-negative-2.mp3',
        tags: ['tier'],
      ),
      const MusicTrack(
        id: 't5',
        title: 'Tier 5 Song',
        artist: 'Tier Tester',
        album: 'Tier Album',
        durationSeconds: 184,
        rankOrder: 3.5,
        filePath: '/stream/t5.mp3',
        tags: ['tier'],
      ),
    ];
  }
}
