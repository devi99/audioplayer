import type { MusicTrack } from './musicLibraryApi.js';

export interface QueueFilter {
  tags?: string[];
  minRating?: number;
  maxRating?: number;
  limit?: number;
  offset?: number;
}

export class AudioQueue {
  private readonly tracks: MusicTrack[];

  constructor(tracks: MusicTrack[]) {
    this.tracks = [...tracks];
  }

  filterTracks(filter: QueueFilter = {}): MusicTrack[] {
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

  scroll(offset = 0, limit = 25): MusicTrack[] {
    return this.tracks.slice(offset, offset + limit);
  }

  queueBySelection(filter: QueueFilter = {}): MusicTrack[] {
    return this.filterTracks(filter);
  }
}
