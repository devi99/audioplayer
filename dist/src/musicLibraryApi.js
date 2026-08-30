"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.MusicLibraryApiClient = void 0;
exports.decodeTrackStream = decodeTrackStream;
function decodeTrackStream(stream) {
    if (!stream) {
        return Buffer.alloc(0);
    }
    const normalized = stream.replace(/^data:audio\/[-+\w.]+;base64,/, '').trim();
    return Buffer.from(normalized, 'base64');
}
class MusicLibraryApiClient {
    baseUrl;
    fetchImpl;
    constructor(options) {
        this.baseUrl = options.baseUrl.replace(/\/+$/, '');
        this.fetchImpl = options.fetchImpl ?? fetch;
    }
    async getTracks() {
        const response = await this.fetchImpl(`${this.baseUrl}/tracks`);
        if (!response.ok) {
            throw new Error(`Failed to load music library: ${response.status} ${response.statusText}`);
        }
        const payload = (await response.json());
        return payload.tracks.map((track) => ({
            ...track,
            stream: track.stream ? track.stream : undefined,
            streamUrl: track.streamUrl ?? undefined,
            tags: Array.isArray(track.tags) ? track.tags.map((tag) => tag.toLowerCase()) : [],
            rating: Number.isFinite(track.rating) ? track.rating : 0,
        }));
    }
    getDecodedStream(track) {
        if (track.stream) {
            return decodeTrackStream(track.stream);
        }
        if (track.streamUrl) {
            return Buffer.from(track.streamUrl);
        }
        return Buffer.alloc(0);
    }
}
exports.MusicLibraryApiClient = MusicLibraryApiClient;
//# sourceMappingURL=musicLibraryApi.js.map