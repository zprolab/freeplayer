import { describe, it, expect, vi, beforeEach } from 'vitest';

// The hook imports useEffect/useRef from 'react' — swap in a lightweight
// harness so the effect can be driven without a DOM renderer. useRef is
// keyed by call order across renders, mirroring React's stable-ref behavior.
const { hookState } = vi.hoisted(() => ({
  hookState: { effects: [], refs: [], refIndex: 0 },
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
  };
});

import { useAutoMeta } from '../src/hooks/useAutoMeta';

const track1 = { id: 1, title: 'Sun', artist: 'A' };
const track2 = { id: 2, title: 'Moon', artist: 'B' };

function mount(track, enabled, meta, dispatch) {
  hookState.effects = [];
  hookState.refs = [];
  hookState.refIndex = 0;
  useAutoMeta(track, enabled, meta, dispatch);
}

function update(track, enabled, meta, dispatch) {
  hookState.effects = [];
  hookState.refIndex = 0;
  useAutoMeta(track, enabled, meta, dispatch);
}

function noopMeta() {
  return {
    fetchCover: vi.fn(async () => ({ saved: false })),
    fetchLyrics: vi.fn(async () => ({ saved: false })),
  };
}

async function flush() {
  await new Promise((r) => setTimeout(r, 0));
}

beforeEach(() => {
  window.freeplayer.getCover = vi.fn(async () => null);
  window.freeplayer.getLrc = vi.fn(async () => null);
});

describe('useAutoMeta with injected meta', () => {
  it('attempts once per track per session', async () => {
    const meta = noopMeta();
    const dispatch = vi.fn();
    mount(track1, true, meta, dispatch);
    hookState.effects[0]();
    await flush();
    expect(meta.fetchCover).toHaveBeenCalledTimes(1);
    expect(meta.fetchLyrics).toHaveBeenCalledTimes(1);

    update(track1, true, meta, dispatch); // same track re-render
    hookState.effects[0]();
    await flush();
    expect(meta.fetchCover).toHaveBeenCalledTimes(1);
    expect(meta.fetchLyrics).toHaveBeenCalledTimes(1);

    update(track2, true, meta, dispatch); // new track -> new attempt
    hookState.effects[0]();
    await flush();
    expect(meta.fetchCover).toHaveBeenCalledTimes(2);
    expect(meta.fetchLyrics).toHaveBeenCalledTimes(2);
    expect(meta.fetchCover).toHaveBeenLastCalledWith(track2);
  });

  it('does nothing when meta is missing (runtime not ready)', async () => {
    const meta = noopMeta();
    const dispatch = vi.fn();
    window.freeplayer.getCover = vi.fn();
    mount(track1, true, null, dispatch);
    hookState.effects[0]();
    await flush();
    expect(window.freeplayer.getCover).not.toHaveBeenCalled();
    expect(window.freeplayer.getLrc).not.toHaveBeenCalled();
    expect(meta.fetchCover).not.toHaveBeenCalled();
    expect(meta.fetchLyrics).not.toHaveBeenCalled();
    expect(dispatch).not.toHaveBeenCalled();
  });

  it('does nothing when the auto-fetch setting is off', async () => {
    const meta = noopMeta();
    const dispatch = vi.fn();
    window.freeplayer.getCover = vi.fn();
    mount(track1, false, meta, dispatch);
    hookState.effects[0]();
    await flush();
    expect(window.freeplayer.getCover).not.toHaveBeenCalled();
    expect(meta.fetchCover).not.toHaveBeenCalled();
  });

  it('only fetches what is missing (existing cover is kept)', async () => {
    const meta = noopMeta();
    const dispatch = vi.fn();
    window.freeplayer.getCover = vi.fn(async () => '/covers/x.jpg');
    mount({ ...track1, cover_path: '/covers/x.jpg' }, true, meta, dispatch);
    hookState.effects[0]();
    await flush();
    expect(meta.fetchCover).not.toHaveBeenCalled();
    expect(meta.fetchLyrics).toHaveBeenCalledTimes(1);
  });

  it('dispatches SET_CURRENT_TRACK with the new cover path when a cover was saved', async () => {
    const meta = { ...noopMeta(), fetchCover: vi.fn(async () => ({ saved: true, coverPath: '/new.jpg' })) };
    const dispatch = vi.fn();
    mount({ ...track1, cover_path: '/old.jpg' }, true, meta, dispatch);
    hookState.effects[0]();
    await flush();
    expect(dispatch).toHaveBeenCalledWith({
      type: 'SET_CURRENT_TRACK',
      payload: expect.objectContaining({ id: 1, cover_path: '/new.jpg' }),
    });
  });
});
