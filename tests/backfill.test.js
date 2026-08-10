import { describe, it, expect, vi } from 'vitest';
import { backfillMissing, needsMetadataFill } from '../src/services/backfill';

describe('needsMetadataFill', () => {
  it('flags tracks with missing or unknown title/artist/album', () => {
    expect(needsMetadataFill({})).toBe(true);
    expect(needsMetadataFill({ title: 'Sun', artist: 'A', album: 'B' })).toBe(false);
    expect(needsMetadataFill({ title: 'Unknown Title', artist: 'A', album: 'B' })).toBe(true);
    expect(needsMetadataFill({ title: 'Sun', artist: 'Unknown Artist', album: 'B' })).toBe(true);
    expect(needsMetadataFill({ title: 'Sun', artist: 'A' })).toBe(true);
    expect(needsMetadataFill({ title: 'Sun', artist: 'A', album: '' })).toBe(true);
  });
});

describe('backfillMissing', () => {
  it('backfills only tracks missing the kind, reporting progress', async () => {
    const tracks = [{ id: 1, title: 'Sun', artist: 'A' }, { id: 2, title: 'Unknown Title', artist: 'Unknown Artist' }];
    const fetchForTrack = vi.fn(async () => ({ saved: true }));
    const missingCheck = vi.fn(async (t) => t.id === 2);
    const onProgress = vi.fn();
    await backfillMissing({ tracks, kind: 'metadata', fetchForTrack, missingCheck, onProgress, sleepMs: 0 });
    expect(fetchForTrack).toHaveBeenCalledTimes(1);
    expect(fetchForTrack).toHaveBeenCalledWith(tracks[1]);
    expect(onProgress).toHaveBeenLastCalledWith(expect.objectContaining({ done: 2, ok: 1, total: 2 }));
  });

  it('refuses to run twice concurrently', async () => {
    const tracks = [{ id: 1 }];
    let release;
    const gate = new Promise((r) => { release = r; });
    const p1 = backfillMissing({
      tracks, kind: 'lyrics', sleepMs: 0,
      fetchForTrack: async () => { await gate; return { saved: false }; },
      missingCheck: async () => true, onProgress: () => {},
    });
    const p2 = backfillMissing({
      tracks, kind: 'lyrics', sleepMs: 0,
      fetchForTrack: vi.fn(), missingCheck: async () => true, onProgress: () => {},
    });
    release();
    await Promise.all([p1, p2]);
    expect(p2).resolves.toBeUndefined();
  });
});
