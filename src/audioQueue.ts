import type { MusicTrack } from './musicLibraryApi.js';

export interface QueueFilter {
  tags?: string[];
  minrankOrder?: number;
  maxrankOrder?: number;
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
    const minrankOrder = filter.minrankOrder ?? 0;
    const maxrankOrder = filter.maxrankOrder ?? Number.POSITIVE_INFINITY;

    return this.tracks
      .filter((track) => {
        const matchesTags = wantedTags.length === 0 || wantedTags.every((tag) => track.tags.includes(tag));
        const matchesrankOrder = track.rankOrder >= minrankOrder && track.rankOrder <= maxrankOrder;
        return matchesTags && matchesrankOrder;
      })
      .sort((left, right) => {
        const byrankOrder = right.rankOrder - left.rankOrder;
        if (byrankOrder !== 0) {
          return byrankOrder;
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
