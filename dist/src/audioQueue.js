"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.AudioQueue = void 0;
class AudioQueue {
    tracks;
    constructor(tracks) {
        this.tracks = [...tracks];
    }
    filterTracks(filter = {}) {
        const wantedTags = (filter.tags ?? []).map((tag) => tag.toLowerCase());
        const minRating = filter.minRating ?? 0;
        const maxRating = filter.maxRating ?? Number.POSITIVE_INFINITY;
        return this.tracks
            .filter((track) => {
            const matchesTags = wantedTags.length === 0 || wantedTags.every((tag) => track.tags.includes(tag));
            const matchesRating = track.rating >= minRating && track.rating <= maxRating;
            return matchesTags && matchesRating;
        })
            .sort((left, right) => {
            const byRating = right.rating - left.rating;
            if (byRating !== 0) {
                return byRating;
            }
            return left.title.localeCompare(right.title);
        })
            .slice(filter.offset ?? 0, filter.limit ? (filter.offset ?? 0) + filter.limit : undefined);
    }
    scroll(offset = 0, limit = 25) {
        return this.tracks.slice(offset, offset + limit);
    }
    queueBySelection(filter = {}) {
        return this.filterTracks(filter);
    }
}
exports.AudioQueue = AudioQueue;
//# sourceMappingURL=audioQueue.js.map