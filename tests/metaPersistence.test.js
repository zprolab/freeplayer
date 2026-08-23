import { describe, it, expect, vi } from 'vitest';
import { fetchAndSaveLyrics, fetchAndSaveCover } from '../src/services/metaPersistence';

describe('fetchAndSaveLyrics', () => {
  it('delegates to meta.fetchLyrics and passes the result through', async () => {
    const meta = { fetchLyrics: vi.fn(async () => ({ saved: true, content: '[00:01.00]hi' })) };
    const track = { id: 5, title: 'Sun', artist: 'A' };
    const r = await fetchAndSaveLyrics(track, meta);
    expect(r).toEqual({ saved: true, content: '[00:01.00]hi' });
    expect(meta.fetchLyrics).toHaveBeenCalledWith(track);
  });

  it('no-ops with { saved: false } when no meta object is provided', async () => {
    expect(await fetchAndSaveLyrics({ id: 5, title: 'Sun' }, null)).toEqual({ saved: false });
    expect(await fetchAndSaveLyrics({ id: 5, title: 'Sun' }, undefined)).toEqual({ saved: false });
  });

  it('short-circuits without a track id', async () => {
    const meta = { fetchLyrics: vi.fn() };
    expect(await fetchAndSaveLyrics(null, meta)).toEqual({ saved: false });
    expect(await fetchAndSaveLyrics({}, meta)).toEqual({ saved: false });
    expect(meta.fetchLyrics).not.toHaveBeenCalled();
  });
});

describe('fetchAndSaveCover', () => {
  it('delegates to meta.fetchCover and passes the result through', async () => {
    const meta = { fetchCover: vi.fn(async () => ({ saved: true, coverPath: '/x.jpg' })) };
    const track = { id: 5, title: 'Sun', artist: 'A' };
    const r = await fetchAndSaveCover(track, meta);
    expect(r).toEqual({ saved: true, coverPath: '/x.jpg' });
    expect(meta.fetchCover).toHaveBeenCalledWith(track);
  });

  it('no-ops with { saved: false } when no meta object is provided', async () => {
    expect(await fetchAndSaveCover({ id: 5, title: 'Sun' }, null)).toEqual({ saved: false });
  });

  it('short-circuits without a track id', async () => {
    const meta = { fetchCover: vi.fn() };
    expect(await fetchAndSaveCover(null, meta)).toEqual({ saved: false });
    expect(meta.fetchCover).not.toHaveBeenCalled();
  });
});
