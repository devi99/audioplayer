export type MusicTag = string;

export interface MusicTrack {
  id: string;
  title: string;
  artist: string;
  album: string;
  durationSeconds: number;
  rankOrder: number;
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

export function decodeTrackStream(stream: string): Buffer {
  if (!stream) {
    return Buffer.alloc(0);
  }

  const normalized = stream.replace(/^data:audio\/[-+\w.]+;base64,/, '').trim();
  return Buffer.from(normalized, 'base64');
}

export class MusicLibraryApiClient {
  private readonly baseUrl: string;
  private readonly fetchImpl: typeof fetch;

  constructor(options: MusicLibraryApiClientOptions) {
    this.baseUrl = options.baseUrl.replace(/\/+$/, '');
    this.fetchImpl = options.fetchImpl ?? fetch;
  }

  async getTracks(): Promise<MusicTrack[]> {
    const response = await this.fetchImpl(`${this.baseUrl}/tracks`);
    if (!response.ok) {
      throw new Error(`Failed to load music library: ${response.status} ${response.statusText}`);
    }

    const payload = (await response.json()) as LibraryApiResponse;
    return payload.tracks.map((track) => ({
      ...track,
      stream: track.stream ? track.stream : undefined,
      streamUrl: track.streamUrl ?? undefined,
      tags: Array.isArray(track.tags) ? track.tags.map((tag) => tag.toLowerCase()) : [],
      rankOrder: Number.isFinite(track.rankOrder) ? track.rankOrder : 0,
    }));
  }

  getDecodedStream(track: MusicTrack): Buffer {
    if (track.stream) {
      return decodeTrackStream(track.stream);
    }

    if (track.streamUrl) {
      return Buffer.from(track.streamUrl);
    }

    return Buffer.alloc(0);
  }
}
