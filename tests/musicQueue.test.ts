import test from 'node:test';
import assert from 'node:assert/strict';

import { AudioQueue } from '../src/audioQueue.js';
import { decodeTrackStream, MusicLibraryApiClient } from '../src/musicLibraryApi.js';

const library = [
  {
    id: '1',
    title: 'Midnight Echo',
    artist: 'Aster',
    album: 'Night Drive',
    durationSeconds: 245,
    rating: 5,
    tags: ['ambient', 'night-drive'],
    stream: Buffer.from('hello-audio').toString('base64'),
  },
  {
    id: '2',
    title: 'Blue Skies',
    artist: 'Aster',
    album: 'Daylight',
    durationSeconds: 203,
    rating: 4,
    tags: ['ambient', 'uplift'],
    stream: Buffer.from('second-audio').toString('base64'),
  },
  {
    id: '3',
    title: 'Static Bloom',
    artist: 'Brazen',
    album: 'Voltage',
    durationSeconds: 367,
    rating: 2,
    tags: ['techno'],
    stream: Buffer.from('third-audio').toString('base64'),
  },
];

test('decodeTrackStream decodes base64 music payloads', () => {
  const decoded = decodeTrackStream(Buffer.from('hello-audio').toString('base64'));
  assert.equal(decoded.toString('utf8'), 'hello-audio');
});

test('AudioQueue filters by tag and rating selections', () => {
  const queue = new AudioQueue(library);
  const selected = queue.queueBySelection({ tags: ['ambient'], minRating: 4 });

  assert.deepEqual(
    selected.map((track) => track.id),
    ['1', '2'],
  );
});

test('MusicLibraryApiClient decodes library response and normalizes tags', async () => {
  const api = new MusicLibraryApiClient({
    baseUrl: 'https://musiclibrary.api',
    fetchImpl: async () => ({
      ok: true,
      status: 200,
      statusText: 'OK',
      json: async () => ({ tracks: library }),
    }) as Response,
  });

  const tracks = await api.getTracks();
  assert.equal(tracks[0].tags[0], 'ambient');
  assert.equal(api.getDecodedStream(tracks[0]).toString('utf8'), 'hello-audio');
});
