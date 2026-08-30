export type MusicTag = string;
export interface MusicTrack {
    id: string;
    title: string;
    artist: string;
    album: string;
    durationSeconds: number;
    rating: number;
    tags: MusicTag[];
    streamUrl?: string;
    stream?: string;
    streamFormat?: string;
}
export interface LibraryApiResponse {
    tracks: MusicTrack[];
}
export interface MusicLibraryApiClientOptions {
    baseUrl: string;
    fetchImpl?: typeof fetch;
}
export declare function decodeTrackStream(stream: string): Buffer;
export declare class MusicLibraryApiClient {
    private readonly baseUrl;
    private readonly fetchImpl;
    constructor(options: MusicLibraryApiClientOptions);
    getTracks(): Promise<MusicTrack[]>;
    getDecodedStream(track: MusicTrack): Buffer;
}
