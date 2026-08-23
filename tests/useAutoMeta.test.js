import { describe, it, expect, vi, beforeEach } from 'vitest';

// The hook imports useEffect/useRef/useState from 'react' — swap in a
// lightweight harness so the effects can be driven without a DOM renderer.
// useRef is keyed by call order across renders, mirroring React's stable-ref
// behavior; useState returns [value, setter] pairs keyed the same way.
const { hookState } = vi.hoisted(() => ({
  hookState: { effects: [], refs: [], refIndex: 0, states: [], stateIndex: 0 },
}));

vi.mock('react', async (importOriginal) => {
  const actual = await importOriginal();
  return {
    ...actual,
    useEffect: (cb) => { hookState.effects.push(cb); },
    useRef: (init) => {
      const idx = hookState.refIndex++;
      if (!hookState.refs[idx]) hookState.refs[idx] = { current: init };
      return hookState.refs[idx];
    },
    useState: (init) => {
      const idx = hookState.stateIndex++;
      if (!hookState.states[idx]) hookState.states[idx] = { value: init, setter: () => {} };
      return [hookState.states[idx].value, (v) => { hookState.states[idx].value = v; }];
    },
  };
});

import { useAutoMeta } from '../src/hooks/useAutoMeta';

const track1 = { id: 1, title: 'Sun', artist: 'A' };
const track2 = { id: 2, title: 'Moon', artist: 'B' };

function reset() {
  hookState.effects = [];
  hookState.refs = [];
  hookState.refIndex = 0;
  hookState.states = [];
  hookState.stateIndex = 0;
}

function mount(track, meta, dispatch) {
  reset();
  useAutoMeta(track, meta, dispatch);
}

function update(track, meta, dispatch) {
  hookState.effects = [];
  hookState.refIndex = 0;
  hookState.stateIndex = 0;
  useAutoMeta(track, meta, dispatch);
}

// meta with getBackend stubbed; auto-fetch switches come from getSetting
// (plugin.<backend>.autoFetch).
function makeMeta({ lyricsBackend = 'lrclib-lyrics', coverBackend = 'itunes-cover', metadataBackend = 'musicbrainz-meta' } = {}) {
  return {
    getBackend: vi.fn(async (kind) => (
      kind === 'lyrics' ? lyricsBackend : kind === 'metadata' ? metadataBackend : coverBackend
    )),
    fetchCover: vi.fn(async () => ({ saved: false })),
    fetchLyrics: vi.fn(async () => ({ saved: false })),
    fetchMetadata: vi.fn(async () => ({ saved: false })),
  };
}

const autoFetchMap = {};
function setAutoFetch(backend, on) {
  autoFetchMap[`plugin.${backend}.autoFetch`] = on ? '1' : '0';
  window.freeplayer.getSetting = vi.fn(async (key) => autoFetchMap[key] ?? null);
}

async function flush() {
  await new Promise((r) => setTimeout(r, 0));
  await new Promise((r) => setTimeout(r, 0));
}

beforeEach(() => {
  Object.keys(autoFetchMap).forEach((k) => delete autoFetchMap[k]);
  window.freeplayer.getCover = vi.fn(async () => null);
  window.freeplayer.getLrc = vi.fn(async () => null);
});

describe('useAutoMeta with per-backend switches', () => {
  it('attempts once per track per session when both switches are on', async () => {
    setAutoFetch('lrclib-lyrics', true);
    setAutoFetch('itunes-cover', true);
    const meta = makeMeta();
    const dispatch = vi.fn();
    mount(track1, meta, dispatch);
    hookState.effects[0](); // resolve switches
    await flush();
    update(track1, meta, dispatch); // re-render with resolved auto state
    hookState.effects[1](); // fetch pass
    await flush();
    expect(meta.fetchCover).toHaveBeenCalledTimes(1);
    expect(meta.fetchLyrics).toHaveBeenCalledTimes(1);

    update(track1, meta, dispatch); // same track re-render
    hookState.effects[1]();
    await flush();
    expect(meta.fetchCover).toHaveBeenCalledTimes(1);
    expect(meta.fetchLyrics).toHaveBeenCalledTimes(1);

    update(track2, meta, dispatch); // new track -> new attempt
    hookState.effects[1]();
    await flush();
    expect(meta.fetchCover).toHaveBeenCalledTimes(2);
    expect(meta.fetchLyrics).toHaveBeenCalledTimes(2);
    expect(meta.fetchCover).toHaveBeenLastCalledWith(track2);
  });

  it('does nothing when meta is missing (runtime not ready)', async () => {
    setAutoFetch('lrclib-lyrics', true);
    const meta = makeMeta();
    const dispatch = vi.fn();
    window.freeplayer.getCover = vi.fn();
    mount(track1, null, dispatch);
    hookState.effects[0]();
    await flush();
    hookState.effects[1]?.();
    await flush();
    expect(window.freeplayer.getCover).not.toHaveBeenCalled();
    expect(window.freeplayer.getLrc).not.toHaveBeenCalled();
    expect(meta.fetchCover).not.toHaveBeenCalled();
    expect(meta.fetchLyrics).not.toHaveBeenCalled();
    expect(dispatch).not.toHaveBeenCalled();
  });

  it('does nothing when both auto-fetch switches are off (default)', async () => {
    setAutoFetch('lrclib-lyrics', false);
    setAutoFetch('itunes-cover', false);
    const meta = makeMeta();
    const dispatch = vi.fn();
    window.freeplayer.getCover = vi.fn();
    mount(track1, meta, dispatch);
    hookState.effects[0]();
    await flush();
    hookState.effects[1]();
    await flush();
    expect(window.freeplayer.getCover).not.toHaveBeenCalled();
    expect(meta.fetchCover).not.toHaveBeenCalled();
    expect(meta.fetchLyrics).not.toHaveBeenCalled();
  });

  it('fetches only lyrics when only the lyrics switch is on', async () => {
    setAutoFetch('lrclib-lyrics', true);
    setAutoFetch('itunes-cover', false);
    const meta = makeMeta();
    const dispatch = vi.fn();
    window.freeplayer.getCover = vi.fn(async () => '/covers/x.jpg');
    mount({ ...track1, cover_path: '/covers/x.jpg' }, meta, dispatch);
    hookState.effects[0]();
    await flush();
    update({ ...track1, cover_path: '/covers/x.jpg' }, meta, dispatch);
    hookState.effects[1]();
    await flush();
    expect(meta.fetchCover).not.toHaveBeenCalled();
    expect(meta.fetchLyrics).toHaveBeenCalledTimes(1);
  });

  it('dispatches an id-matched SET_TRACK_FIELDS with the new cover path when a cover was saved', async () => {
    setAutoFetch('lrclib-lyrics', false);
    setAutoFetch('itunes-cover', true);
    const meta = { ...makeMeta(), fetchCover: vi.fn(async () => ({ saved: true, coverPath: '/new.jpg' })) };
    const dispatch = vi.fn();
    mount({ ...track1, cover_path: '/old.jpg' }, meta, dispatch);
    hookState.effects[0]();
    await flush();
    update({ ...track1, cover_path: '/old.jpg' }, meta, dispatch);
    hookState.effects[1]();
    await flush();
    expect(dispatch).toHaveBeenCalledWith({
      type: 'SET_TRACK_FIELDS',
      payload: { id: 1, fields: { cover_path: '/new.jpg' } },
    });
  });

  it('still syncs the saved cover when the user switched tracks mid-fetch (never looks lost)', async () => {
    setAutoFetch('lrclib-lyrics', false);
    setAutoFetch('itunes-cover', true);
    const meta = { ...makeMeta(), fetchCover: vi.fn(async () => ({ saved: true, coverPath: '/new.jpg' })) };
    const dispatch = vi.fn();
    mount(track1, meta, dispatch);
    hookState.effects[0](); // resolve switches
    await flush();
    update(track1, meta, dispatch);
    hookState.effects[1](); // fetch pass for track1 (async, in flight)
    update(track2, meta, dispatch); // user switches tracks before it resolves
    await flush();
    // The stale fetch must still patch track 1 by id — never clobber
    // currentTrack (track 2), never drop the saved cover.
    expect(dispatch).toHaveBeenCalledWith({
      type: 'SET_TRACK_FIELDS',
      payload: { id: 1, fields: { cover_path: '/new.jpg' } },
    });
    expect(dispatch).not.toHaveBeenCalledWith(expect.objectContaining({ type: 'SET_CURRENT_TRACK' }));
  });

  it('fetches metadata and dispatches the updated fields when the switch is on and fields are unknown', async () => {
    setAutoFetch('lrclib-lyrics', false);
    setAutoFetch('itunes-cover', false);
    setAutoFetch('musicbrainz-meta', true);
    const meta = { ...makeMeta(), fetchMetadata: vi.fn(async () => ({ saved: true, updated: { artist: 'Real Artist' } })) };
    const dispatch = vi.fn();
    mount({ ...track1, artist: 'Unknown Artist' }, meta, dispatch);
    hookState.effects[0](); // resolve switches
    await flush();
    update({ ...track1, artist: 'Unknown Artist' }, meta, dispatch); // re-render with resolved auto state
    hookState.effects[1](); // fetch pass
    await flush();
    expect(meta.fetchMetadata).toHaveBeenCalledTimes(1);
    expect(meta.fetchMetadata).toHaveBeenCalledWith({ ...track1, artist: 'Unknown Artist' });
    expect(dispatch).toHaveBeenCalledWith({
      type: 'SET_TRACK_FIELDS',
      payload: { id: 1, fields: { artist: 'Real Artist' } },
    });
  });

  it('does not fetch metadata when the metadata switch is off', async () => {
    setAutoFetch('lrclib-lyrics', false);
    setAutoFetch('itunes-cover', false);
    setAutoFetch('musicbrainz-meta', false);
    const meta = makeMeta();
    const dispatch = vi.fn();
    mount({ ...track1, artist: 'Unknown Artist' }, meta, dispatch);
    hookState.effects[0]();
    await flush();
    update({ ...track1, artist: 'Unknown Artist' }, meta, dispatch);
    hookState.effects[1]();
    await flush();
    expect(meta.fetchMetadata).not.toHaveBeenCalled();
    expect(meta.fetchLyrics).not.toHaveBeenCalled();
    expect(meta.fetchCover).not.toHaveBeenCalled();
  });

  it('merges fetched metadata and cover into one dispatch when both switches are on', async () => {
    setAutoFetch('lrclib-lyrics', false);
    setAutoFetch('itunes-cover', true);
    setAutoFetch('musicbrainz-meta', true);
    const meta = {
      ...makeMeta(),
      fetchCover: vi.fn(async () => ({ saved: true, coverPath: '/new.jpg' })),
      fetchMetadata: vi.fn(async () => ({ saved: true, updated: { title: 'New' } })),
    };
    const dispatch = vi.fn();
    mount({ ...track1, artist: 'Unknown Artist' }, meta, dispatch);
    hookState.effects[0](); // resolve switches
    await flush();
    update({ ...track1, artist: 'Unknown Artist' }, meta, dispatch); // re-render with resolved auto state
    hookState.effects[1](); // fetch pass
    await flush();
    expect(dispatch).toHaveBeenCalledTimes(1);
    expect(dispatch).toHaveBeenCalledWith({
      type: 'SET_TRACK_FIELDS',
      payload: { id: 1, fields: { title: 'New', cover_path: '/new.jpg' } },
    });
  });
});
