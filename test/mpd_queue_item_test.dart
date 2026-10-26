import 'package:flutter_test/flutter_test.dart';

import 'package:audioplayer/models/mpd_queue_item.dart';

void main() {
  group('MpdQueueItem', () {
    test('parses a queue item from the MPD API', () {
      // Shape captured from GET /api/Mpd/queue
      final json = <String, dynamic>{
        'file': 'Artist/Album/01 Song.m4a',
        'Last-Modified': '2012-12-02T12:16:20Z',
        'Format': '44100:f:2',
        'Artist': 'Artist',
        'Album': 'Album',
        'Title': 'Song',
        'Track': '1',
        'Genre': 'Music',
        'Date': '2012',
        'Time': '203',
        'duration': '202.989',
        'Pos': '0',
        'Id': '455',
      };

      final item = MpdQueueItem.fromJson(json);

      expect(item.file, 'Artist/Album/01 Song.m4a');
      expect(item.artist, 'Artist');
      expect(item.album, 'Album');
      expect(item.title, 'Song');
      expect(item.track, '1');
      expect(item.genre, 'Music');
      expect(item.date, '2012');
      expect(item.durationSeconds, 202.989);
      expect(item.pos, 0);
      expect(item.id, 455);
      expect(item.fileName, '01 Song.m4a');
    });

    test('parses items with missing metadata', () {
      final item = MpdQueueItem.fromJson(<String, dynamic>{
        'file': 'song.mp3',
        'Artist': 'Artist',
        'Title': 'Song',
        'Time': '241',
        'duration': 240.692,
        'Pos': '1',
        'Id': '456',
      });

      expect(item.album, isNull);
      expect(item.durationSeconds, 240.692);
      expect(item.title, 'Song');
      expect(item.fileName, 'song.mp3');
    });
  });

  group('MpdStatus', () {
    test('parses the stopped status from the MPD API', () {
      // Shape captured from GET /api/Mpd/status
      final status = MpdStatus.fromJson(<String, dynamic>{
        'state': 'stop',
        'volume': '43',
        'elapsed': 0,
        'duration': 0,
        'queueLength': 0,
        'random': 1,
        'consume': 1,
        'currentSong': <String, dynamic>{},
      });

      expect(status.state, 'stop');
      expect(status.volume, 43);
      expect(status.queueLength, 0);
      expect(status.random, isTrue);
      expect(status.consume, isTrue);
      expect(status.currentSong, isNull);
      expect(status.isPlaying, isFalse);
      expect(status.isPaused, isFalse);
    });

    test('parses a playing status with a current song', () {
      final status = MpdStatus.fromJson(<String, dynamic>{
        'state': 'play',
        'volume': '55',
        'elapsed': 12.5,
        'duration': 202.989,
        'queueLength': 3,
        'random': 0,
        'consume': 0,
        'currentSong': <String, dynamic>{
          'file': 'Artist/Album/01 Song.m4a',
          'Artist': 'Artist',
          'Title': 'Song',
          'Pos': '1',
          'Id': '455',
        },
      });

      expect(status.state, 'play');
      expect(status.isPlaying, isTrue);
      expect(status.elapsedSeconds, 12.5);
      expect(status.durationSeconds, 202.989);
      expect(status.currentSong?.file, 'Artist/Album/01 Song.m4a');
      expect(status.random, isFalse);
      expect(status.consume, isFalse);
    });
  });
}
