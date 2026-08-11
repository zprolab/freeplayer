import { describe, it, expect, vi, beforeEach } from 'vitest';
import { backfillMissing, cancelBackfill, isBackfillRunning, needsMetadataFill } from '../src/services/backfill';

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

// Module-level per-kind locks persist across tests on failure — clear them so
// one failing test cannot silently disable the next.
beforeEach(() => {
  cancelBackfill('lyrics');
  cancelBackfill('cover');
  cancelBackfill('metadata');
});

describe('backfillMissing', () => {
  it('backfills only tracks missing the kind, reporting progress', async () => {
    const tracks = [{ id: 1, title: 'Sun', artist: 'A' }, { id: 2, title: 'Unknown Title', artist: 'Unknown Artist' }];
    const fetchForTrack = vi.fn(async () => ({ saved: true }));
    const missingCheck = vi.fn(async (t) => t.id === 2);
    const onProgress = vi.fn();
    const result = await backfillMissing({ tracks, kind: 'metadata', fetchForTrack, missingCheck, onProgress, sleepMs: 0 });
    expect(fetchForTrack).toHaveBeenCalledTimes(1);
    expect(fetchForTrack).toHaveBeenCalledWith(tracks[1]);
    expect(onProgress).toHaveBeenNthCalledWith(1, { done: 0, total: 2, ok: 0, fail: 0, noMatch: 0 });
    expect(onProgress).toHaveBeenLastCalledWith({ done: 2, total: 2, ok: 1, fail: 0, noMatch: 0 });
    expect(result).toEqual({ ok: 1, fail: 0, noMatch: 0, cancelled: false });
  });

  it('counts fetch failures and no-match tracks separately', async () => {
    const tracks = [{ id: 1 }, { id: 2 }, { id: 3 }];
    const fetchForTrack = vi.fn(async (t) => {
      if (t.id === 1) throw new Error('api down');
      if (t.id === 2) return { saved: false }; // missing but nothing saved → noMatch
      return { saved: true };
    });
    const missingCheck = vi.fn(async () => true);
    const onProgress = vi.fn();
    const result = await backfillMissing({ tracks, kind: 'lyrics', fetchForTrack, missingCheck, onProgress, sleepMs: 0 });
    expect(result).toEqual({ ok: 1, fail: 1, noMatch: 1, cancelled: false });
    expect(onProgress).toHaveBeenLastCalledWith({ done: 3, total: 3, ok: 1, fail: 1, noMatch: 1 });
  });

  it('does not start and never calls onProgress for empty tracks', async () => {
    const onProgress = vi.fn();
    const result = await backfillMissing({ tracks: [], kind: 'lyrics', fetchForTrack: vi.fn(), missingCheck: vi.fn(), onProgress, sleepMs: 0 });
    expect(result).toBeUndefined();
    expect(onProgress).not.toHaveBeenCalled();
  });

  it('refuses to run twice concurrently for the same kind', async () => {
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
    expect(await p1).toEqual({ ok: 0, fail: 0, noMatch: 1, cancelled: false });
  });

  it('allows different kinds to run in parallel with per-kind locks', async () => {
    let release;
    const gate = new Promise((r) => { release = r; });
    const p1 = backfillMissing({
      tracks: [{ id: 1 }], kind: 'lyrics', sleepMs: 0,
      fetchForTrack: async () => { await gate; return { saved: true }; },
      missingCheck: async () => true, onProgress: () => {},
    });
    expect(isBackfillRunning('lyrics')).toBe(true);
    expect(isBackfillRunning('cover')).toBe(false);
    expect(isBackfillRunning()).toBe(true);
    const p2 = backfillMissing({
      tracks: [{ id: 2 }], kind: 'cover', sleepMs: 0,
      fetchForTrack: async () => ({ saved: true }),
      missingCheck: async () => true, onProgress: () => {},
    });
    await p2; // completes while lyrics is still gated
    expect(isBackfillRunning('cover')).toBe(false);
    release();
    await p1;
    expect(isBackfillRunning()).toBe(false);
  });

  it('stops processing further tracks when the signal aborts', async () => {
    const tracks = [{ id: 1 }, { id: 2 }, { id: 3 }];
    const controller = new AbortController();
    let release;
    const gate = new Promise((r) => { release = r; });
    const fetchForTrack = vi.fn(async (t) => {
      if (t.id === 1) await gate;
      return { saved: true };
    });
    const missingCheck = vi.fn(async () => true);
    const p = backfillMissing({
      tracks, kind: 'metadata', fetchForTrack, missingCheck,
      onProgress: () => {}, sleepMs: 0, signal: controller.signal,
    });
    controller.abort(); // abort while the first fetch is still in flight
    release();
    const result = await p;
    expect(result).toEqual({ ok: 1, fail: 0, noMatch: 0, cancelled: true });
    expect(fetchForTrack).toHaveBeenCalledTimes(1); // tracks 2/3 never fetched
  });
});

describe('backfillMissing force', () => {
  it('refetches every track when force is true, ignoring missingCheck', async () => {
    const tracks = [{ id: 1, title: 'Complete' }, { id: 2, title: 'Complete' }];
    const fetchForTrack = vi.fn(async () => ({ saved: true }));
    const missingCheck = vi.fn(async () => false); // would skip everything
    await backfillMissing({
      tracks, kind: 'lyrics', fetchForTrack, missingCheck,
      onProgress: () => {}, sleepMs: 0, force: true,
    });
    expect(missingCheck).not.toHaveBeenCalled();
    expect(fetchForTrack).toHaveBeenCalledTimes(2);
  });
});
