import type { MusicTrack } from './musicLibraryApi.js';
export interface QueueFilter {
    tags?: string[];
    minRating?: number;
    maxRating?: number;
    limit?: number;
    offset?: number;
}
export declare class AudioQueue {
    private readonly tracks;
    constructor(tracks: MusicTrack[]);
    filterTracks(filter?: QueueFilter): MusicTrack[];
    scroll(offset?: number, limit?: number): MusicTrack[];
    queueBySelection(filter?: QueueFilter): MusicTrack[];
}
