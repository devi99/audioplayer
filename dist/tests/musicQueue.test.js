"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = __importDefault(require("node:test"));
const strict_1 = __importDefault(require("node:assert/strict"));
const audioQueue_js_1 = require("../src/audioQueue.js");
const musicLibraryApi_js_1 = require("../src/musicLibraryApi.js");
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
(0, node_test_1.default)('decodeTrackStream decodes base64 music payloads', () => {
    const decoded = (0, musicLibraryApi_js_1.decodeTrackStream)(Buffer.from('hello-audio').toString('base64'));
    strict_1.default.equal(decoded.toString('utf8'), 'hello-audio');
});
(0, node_test_1.default)('AudioQueue filters by tag and rating selections', () => {
    const queue = new audioQueue_js_1.AudioQueue(library);
    const selected = queue.queueBySelection({ tags: ['ambient'], minRating: 4 });
    strict_1.default.deepEqual(selected.map((track) => track.id), ['1', '2']);
});
(0, node_test_1.default)('MusicLibraryApiClient decodes library response and normalizes tags', async () => {
    const api = new musicLibraryApi_js_1.MusicLibraryApiClient({
        baseUrl: 'https://musiclibrary.api',
        fetchImpl: async () => ({
            ok: true,
            status: 200,
            statusText: 'OK',
            json: async () => ({ tracks: library }),
        }),
    });
    const tracks = await api.getTracks();
    strict_1.default.equal(tracks[0].tags[0], 'ambient');
    strict_1.default.equal(api.getDecodedStream(tracks[0]).toString('utf8'), 'hello-audio');
});
//# sourceMappingURL=musicQueue.test.js.map