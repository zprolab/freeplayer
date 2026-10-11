// features/library/store.js is the non-React half of the library feature, so it
// is exercised directly — no renderer, no React, no bridge stub beyond the one
// call it makes. Same reason playQueue/engine have their own tests: the logic
// that decides ORDER is where a silent regression is hardest to notice (a list
// that is merely mis-sorted still looks fine).
import { describe, it, expect, beforeEach, vi } from 'vitest';

const tracksMock = vi.fn();

vi.mock('@/core/client.js', () => ({
  library: { tracks: (...args) => tracksMock(...args) },
}));

const { fetchTracks, compareTracks, sortTracks } = await import('@/features/library/store.js');

const T = (over = {}) => ({
  id: 1, title: 'Alpha', artist: 'Beta', album: 'Gamma', genre: 'Delta',
  year: 2000, duration: 100, ...over,
});

describe('fetchTracks', () => {
  beforeEach(() => tracksMock.mockReset());

  it('passes search and sort through to the host', async () => {
    tracksMock.mockResolvedValue([]);
    await fetchTracks({ search: 'moon', sortBy: 'artist', sortDir: 'DESC' });
    expect(tracksMock).toHaveBeenCalledWith({ search: 'moon', sortBy: 'artist', sortDir: 'DESC' });
  });

  it('defaults to title ASC', async () => {
    tracksMock.mockResolvedValue([]);
    await fetchTracks();
    expect(tracksMock).toHaveBeenCalledWith({ search: '', sortBy: 'title', sortDir: 'ASC' });
  });

  // A sort key the host does not accept would be forwarded as-is and the host
  // would silently fall back to its own default, which is not necessarily ours.
  it('rejects a sort key the host does not accept', async () => {
    tracksMock.mockResolvedValue([]);
    await fetchTracks({ sortBy: 'meta_source' });
    expect(tracksMock).toHaveBeenCalledWith(expect.objectContaining({ sortBy: 'title' }));
  });

  it('normalises a non-ASC direction to ASC', async () => {
    tracksMock.mockResolvedValue([]);
    await fetchTracks({ sortDir: 'sideways' });
    expect(tracksMock).toHaveBeenCalledWith(expect.objectContaining({ sortDir: 'ASC' }));
  });

  // Reachable: a rejected bridge call caught one level up leaves the payload
  // undefined, and `data.map` downstream would then throw inside render.
  it('returns an empty list when the host answers with a non-array', async () => {
    tracksMock.mockResolvedValue(undefined);
    expect(await fetchTracks()).toEqual([]);
    tracksMock.mockResolvedValue({ tracks: [] });
    expect(await fetchTracks()).toEqual([]);
  });
});

describe('compareTracks / sortTracks', () => {
  it('compares text case-insensitively', () => {
    const a = T({ title: 'apple' });
    const b = T({ title: 'Banana' });
    expect(compareTracks(a, b, 'title', 'ASC')).toBeLessThan(0);
    expect(compareTracks(b, a, 'title', 'ASC')).toBeGreaterThan(0);
  });

  it('compares year and duration numerically, not as text', () => {
    // Text comparison would order '1999' after '2000'.
    const older = T({ year: 1999, duration: 90 });
    const newer = T({ year: 2000, duration: 100 });
    expect(compareTracks(older, newer, 'year', 'ASC')).toBeLessThan(0);
    expect(compareTracks(older, newer, 'duration', 'ASC')).toBeLessThan(0);
  });

  it('treats a missing numeric value as 0 rather than NaN', () => {
    const missing = T({ year: undefined, duration: undefined });
    const present = T({ year: 2001, duration: 120 });
    const cmp = compareTracks(missing, present, 'year', 'ASC');
    expect(Number.isNaN(cmp)).toBe(false);
    expect(cmp).toBeLessThan(0);
  });

  it('inverts with DESC', () => {
    const a = T({ title: 'apple' });
    const b = T({ title: 'banana' });
    expect(compareTracks(a, b, 'title', 'DESC')).toBeGreaterThan(0);
  });

  it('sorts a copy and never mutates the input', () => {
    const input = [T({ id: 1, title: 'c' }), T({ id: 2, title: 'a' }), T({ id: 3, title: 'b' })];
    const frozen = input.slice();
    const sorted = sortTracks(input, 'title', 'ASC');
    expect(sorted.map((t) => t.title)).toEqual(['a', 'b', 'c']);
    expect(input).toEqual(frozen);        // Redux state must not be reordered in place
    expect(sorted).not.toBe(input);
  });
});
