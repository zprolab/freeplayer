import { describe, it, expect, vi, beforeEach } from 'vitest';
import { computeNextIndex, computePrevIndex, shuffleArray, buildShuffleOrder } from '../src/hooks/playQueue';

const tracks = [
  { id: 1, title: 'A', file_path: 'path-A' }, { id: 2, title: 'B', file_path: 'path-B' },
  { id: 3, title: 'C', file_path: 'path-C' }, { id: 4, title: 'D', file_path: 'path-D' },
];

describe('computeNextIndex', () => {
  it('moves to the next track in sequential mode', () => {
    expect(computeNextIndex({ queue: tracks, queueIndex: 0, playMode: 'sequential', shuffledQueue: [] })).toEqual({ nextIdx: 1, reshuffled: null });
    expect(computeNextIndex({ queue: tracks, queueIndex: 2, playMode: 'sequential', shuffledQueue: [] })).toEqual({ nextIdx: 3, reshuffled: null });
  });

  it('wraps to the first track after the last in sequential mode', () => {
    expect(computeNextIndex({ queue: tracks, queueIndex: 3, playMode: 'sequential', shuffledQueue: [] }).nextIdx).toBe(0);
  });

  it('follows the shuffled order when it matches the queue', () => {
    const shuffled = [tracks[2], tracks[0], tracks[3], tracks[1]]; // ids [3,1,4,2]
    const r = computeNextIndex({ queue: tracks, queueIndex: 0, playMode: 'shuffle', shuffledQueue: shuffled });
    expect(r.reshuffled).toBeNull();
    // current track (id 1) sits at shuffled position 1 → next is shuffled[2] = id 4
    expect(r.nextIdx).toBe(3);
  });

  it('wraps to the head of the same shuffle order (no mid-cycle re-roll)', () => {
    // The stored order IS the queue order: the current track is last, so the
    // next one wraps back to the head instead of re-rolling. Re-rolling used
    // to repeat the track just played and skip tracks that never came up.
    const shuffled = [...tracks];
    const r = computeNextIndex({ queue: tracks, queueIndex: 3, playMode: 'shuffle', shuffledQueue: shuffled });
    expect(r.reshuffled).toBeNull();
    expect(r.nextIdx).toBe(0);
  });

  it('skips rather than playing the wrong track when the order no longer matches', () => {
    // The queue was replaced, so the current track is not in the stored order.
    // Advancing from findIndex === -1 landed on shuffled[1] and silently played
    // an unrelated track.
    const stale = [tracks[2], tracks[3]];
    const r = computeNextIndex({ queue: tracks, queueIndex: 0, playMode: 'shuffle', shuffledQueue: stale });
    expect(r).toEqual({ nextIdx: -1, reshuffled: null });
  });

  it('uses the queue as the shuffle order when none is stored', () => {
    const r = computeNextIndex({ queue: tracks, queueIndex: 1, playMode: 'shuffle', shuffledQueue: [] });
    expect(r.nextIdx).toBe(2);
    expect(r.reshuffled).toBeNull();
  });

  it('wraps to the head when no order is stored', () => {
    const r = computeNextIndex({ queue: tracks, queueIndex: 3, playMode: 'shuffle', shuffledQueue: [] });
    expect(r.reshuffled).toBeNull();
    expect(r.nextIdx).toBe(0);
  });

  it('returns -1 for an empty queue', () => {
    expect(computeNextIndex({ queue: [], queueIndex: 0, playMode: 'sequential', shuffledQueue: [] })).toEqual({ nextIdx: -1, reshuffled: null });
  });
});

describe('buildShuffleOrder', () => {
  it('puts the current track first and every other track exactly once', () => {
    const order = buildShuffleOrder(tracks, 3);
    expect(order[0].id).toBe(3);
    expect(order).toHaveLength(tracks.length);
    expect([...order].map(t => t.id).sort()).toEqual([1, 2, 3, 4]);
  });

  it('covers the whole queue in one pass (the old swap made a cycle repeat and skip)', () => {
    for (let attempt = 0; attempt < 25; attempt++) {
      let order = buildShuffleOrder(tracks, 2);
      const played = [order[0].id];
      let queueIndex = tracks.findIndex(t => t.id === order[0].id);
      let stored = order;
      for (let step = 0; step < tracks.length - 1; step++) {
        const r = computeNextIndex({ queue: tracks, queueIndex, playMode: 'shuffle', shuffledQueue: stored });
        queueIndex = r.nextIdx;
        played.push(tracks[queueIndex].id);
      }
      expect(new Set(played).size).toBe(tracks.length);
      expect(played[0]).toBe(2);
    }
  });

  it('still includes a track that is not in the list it is asked about', () => {
    const order = buildShuffleOrder(tracks, 99);
    expect(order).toHaveLength(tracks.length);
    expect([...order].map(t => t.id).sort()).toEqual([1, 2, 3, 4]);
  });
});

describe('computePrevIndex', () => {
  it('goes to the previous track in sequential mode', () => {
    expect(computePrevIndex({ queue: tracks, queueIndex: 2, currentTime: 1, playMode: 'sequential', shuffledQueue: [] }).prevIdx).toBe(1);
  });

  it('wraps to the last track before the first in sequential mode', () => {
    expect(computePrevIndex({ queue: tracks, queueIndex: 0, currentTime: 1, playMode: 'sequential', shuffledQueue: [] }).prevIdx).toBe(3);
  });

  it('restarts the current track when more than 3s elapsed', () => {
    expect(computePrevIndex({ queue: tracks, queueIndex: 1, currentTime: 4, playMode: 'sequential', shuffledQueue: [] }).prevIdx).toBe(1);
  });

  it('steps back through the shuffled order', () => {
    const shuffled = [tracks[2], tracks[0], tracks[3], tracks[1]]; // ids [3,1,4,2]
    // current track (id 3) is shuffled position 0 → wraps to the last entry (id 2)
    const r = computePrevIndex({ queue: tracks, queueIndex: 2, currentTime: 1, playMode: 'shuffle', shuffledQueue: shuffled });
    expect(r.prevIdx).toBe(1);
  });

  it('wraps to the last shuffled track from the first', () => {
    const shuffled = [tracks[2], tracks[0], tracks[3], tracks[1]];
    // current track is id 1 (queue idx 0), shuffled position 1 → previous is id 3
    const r = computePrevIndex({ queue: tracks, queueIndex: 0, currentTime: 1, playMode: 'shuffle', shuffledQueue: shuffled });
    expect(r.prevIdx).toBe(2);
  });

  it('returns -1 for an empty queue', () => {
    expect(computePrevIndex({ queue: [], queueIndex: 0, currentTime: 1, playMode: 'sequential', shuffledQueue: [] }).prevIdx).toBe(-1);
  });

  it('bails out when the stored shuffle order no longer contains the current track', () => {
    // findIndex === -1 used to fall through to the wrap branch and jump to the
    // last entry of an unrelated order.
    const stale = [tracks[2], tracks[3]];
    expect(computePrevIndex({ queue: tracks, queueIndex: 0, currentTime: 1, playMode: 'shuffle', shuffledQueue: stale }).prevIdx).toBe(-1);
  });
});

describe('shuffleArray', () => {
  it('returns a permutation of the same tracks without mutating the input', () => {
    const input = tracks.slice();
    const shuffled = shuffleArray(input);
    expect(shuffled).toHaveLength(tracks.length);
    expect(shuffled.map(t => t.id).sort()).toEqual(tracks.map(t => t.id).sort());
    expect(input).toEqual(tracks);
  });
});

// ── Hook-level tests: session lifecycle, volume clamp, next/prev wiring ──
// Same lightweight react harness pattern as useAutoMeta.test.js. useCallback
// is mocked to identity (no dispatcher in a plain-node environment); the refs
// stay stable by call order and effects are pushed for manual driving.

const { hookState } = vi.hoisted(() => ({
  hookState: { effects: [], refs: [], refIndex: 0, states: [], stateIndex: 0 },
}));

vi.mock('react', async (importOriginal) => {
  const actual = await importOriginal();
  return {
    ...actual,
    useEffect: (cb) => { hookState.effects.push(cb); },
    useCallback: (cb) => cb,
    useRef: (init) => {
      const idx = hookState.refIndex++;
      if (!hookState.refs[idx]) hookState.refs[idx] = { current: init };
      return hookState.refs[idx];
    },
  };
});

vi.mock('../src/context/PlayerContext', () => ({
  usePlayer: vi.fn(),
}));

vi.mock('../src/audio/audioEngine', () => ({
  audioEngine: {
    setGain: vi.fn(), setVolume: vi.fn(), dispose: vi.fn(),
    // the graph wires (idempotently) at play start — see usePlayback
    connect: vi.fn(), resume: vi.fn(),
  },
}));

import { usePlayer } from '../src/context/PlayerContext';
import { audioEngine } from '../src/audio/audioEngine';
import { usePlayback } from '../src/hooks/usePlayback';
import { PlaybackEngine, __setPlaybackEngineForTests } from '../src/player/playbackEngine';

function reset() {
  hookState.effects = [];
  hookState.refs = [];
  hookState.refIndex = 0;
  hookState.states = [];
  hookState.stateIndex = 0;
  audioEngine.setGain.mockClear();
  audioEngine.setVolume.mockClear();
  audioEngine.dispose.mockClear();
  audioEngine.connect.mockClear();
  audioEngine.resume.mockClear();
}

function makeAudio() {
  const audio = {
    src: '', volume: 1, currentTime: 0, duration: 100, paused: true, error: null,
    play: vi.fn(async () => {}),
    pause: vi.fn(() => { audio.paused = true; }),
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
  };
  return audio;
}

let handlers;
let engine;
function mount(overrides = {}) {
  reset();
  const audio = overrides.audio || makeAudio();
  const player = {
    state: overrides.state || {
      tracks, queue: tracks, queueIndex: 0, playMode: 'sequential',
      shuffledQueue: [], volume: 0.8, isPlaying: false, currentTrack: null,
    },
    dispatch: vi.fn(),
    audioRef: { current: audio },
  };
  usePlayer.mockReturnValue(player);
  // A fresh engine per mount: the real one is a process-lifetime singleton, so
  // sharing it across tests would leak session and event-listener state.
  engine = new PlaybackEngine({ audio });
  __setPlaybackEngineForTests(engine);
  handlers = usePlayback();
  return { audio, dispatch: player.dispatch, player, engine };
}

async function flush(times = 3) {
  for (let i = 0; i < times; i++) await new Promise((r) => setTimeout(r, 0));
}

beforeEach(() => {
  window.freeplayer.playStart = vi.fn(async () => 1);
  window.freeplayer.playEnd = vi.fn(async () => {});
});

describe('usePlayback session lifecycle', () => {
  it('wires the audio graph before play() so the EQ is in every play path', async () => {
    const calls = [];
    audioEngine.connect.mockImplementation(() => calls.push('connect'));
    const audio = makeAudio();
    audio.play.mockImplementation(async () => calls.push('play'));
    mount({ audio });
    await handlers.playTrack(tracks[0]);
    // connect must precede play: routing a playing element into the graph
    // mid-flight audibly hiccups (and the EQ would otherwise be bypassed
    // in views without a mounted visualizer).
    expect(calls).toEqual(['connect', 'play']);
    expect(audioEngine.resume).toHaveBeenCalled();
  });

  it('playTrack ends the previous session before starting a new one', async () => {
    window.freeplayer.playStart = vi.fn(async () => 42);
    mount();
    await handlers.playTrack(tracks[0]);
    expect(window.freeplayer.playStart).toHaveBeenCalledWith(1);
    await handlers.playTrack(tracks[1]);
    expect(window.freeplayer.playEnd).toHaveBeenCalledTimes(1);
    expect(window.freeplayer.playEnd).toHaveBeenCalledWith(expect.objectContaining({ sessionId: 42 }));
    expect(window.freeplayer.playStart).toHaveBeenLastCalledWith(2);
  });

  it('serializes rapid playTrack calls so no session is left open', async () => {
    let release;
    const gate = new Promise((r) => { release = r; });
    window.freeplayer.playStart = vi.fn(async (id) => {
      if (id === tracks[0].id) await gate;
      return id;
    });
    mount();
    const p1 = handlers.playTrack(tracks[0]);
    const p2 = handlers.playTrack(tracks[1]);
    release();
    await Promise.all([p1, p2]);
    // Both rapid calls must end up with exactly one playEnd for the session
    // the first call opened — never zero (the pre-fix leak) nor two.
    expect(window.freeplayer.playEnd).toHaveBeenCalledTimes(1);
    expect(window.freeplayer.playEnd).toHaveBeenCalledWith(expect.objectContaining({ sessionId: tracks[0].id }));
    expect(window.freeplayer.playStart).toHaveBeenNthCalledWith(1, tracks[0].id);
    expect(window.freeplayer.playStart).toHaveBeenNthCalledWith(2, tracks[1].id);
  });

  it('closes the previous session even when audio.play() rejects', async () => {
    window.freeplayer.playStart = vi.fn(async () => 7);
    const audio = makeAudio();
    mount({ audio });
    await handlers.playTrack(tracks[0]);
    audio.play = vi.fn(async () => { throw new Error('NotAllowedError'); });
    await handlers.playTrack(tracks[1]);
    // Previous session closed exactly once; the failed track never started
    expect(window.freeplayer.playEnd).toHaveBeenCalledTimes(1);
    expect(window.freeplayer.playEnd).toHaveBeenCalledWith(expect.objectContaining({ sessionId: 7 }));
    expect(window.freeplayer.playStart).toHaveBeenCalledTimes(1);
  });

  it('closes the current session on unmount', async () => {
    window.freeplayer.playStart = vi.fn(async () => 9);
    mount();
    await handlers.playTrack(tracks[0]);
    const cleanup = hookState.effects[2]();
    cleanup();
    await flush();
    expect(window.freeplayer.playEnd).toHaveBeenCalledTimes(1);
    expect(window.freeplayer.playEnd).toHaveBeenCalledWith(expect.objectContaining({ sessionId: 9 }));
    // The engine is a process-lifetime singleton: unmounting the UI must NOT
    // tear down the audio graph (a StrictMode/HMR remount would lose playback).
    expect(audioEngine.dispose).not.toHaveBeenCalled();
  });
});

describe('usePlayback volume', () => {
  it('clamps out-of-range input and rejects non-finite input', async () => {
    const { dispatch } = mount();
    handlers.handleVolumeChange(1.7);
    expect(audioEngine.setVolume).toHaveBeenLastCalledWith(1);
    expect(dispatch).toHaveBeenCalledWith({ type: 'SET_VOLUME', payload: 1 });
    handlers.handleVolumeChange(-0.5);
    expect(audioEngine.setVolume).toHaveBeenLastCalledWith(0);
    handlers.handleVolumeChange(NaN);
    expect(audioEngine.setVolume).toHaveBeenCalledTimes(2); // NaN rejected
    expect(dispatch).toHaveBeenCalledTimes(2);
  });
});

describe('usePlayback next/prev wiring (real logic from playQueue)', () => {
  it('handleNext dispatches the next index and plays that track', async () => {
    window.freeplayer.playStart = vi.fn(async () => 1);
    const { dispatch, audio } = mount();
    handlers.handleNext();
    expect(dispatch).toHaveBeenCalledWith({ type: 'SET_QUEUE_INDEX', payload: 1 });
    await flush();
    expect(audio.src).toBe('media://path-B');
    expect(window.freeplayer.playStart).toHaveBeenCalledWith(tracks[1].id);
  });

  it('handleNext in repeat-one replays through the session lifecycle', async () => {
    window.freeplayer.playStart = vi.fn(async () => 5);
    const { dispatch, audio } = mount({ state: {
      tracks, queue: tracks, queueIndex: 1, playMode: 'repeat-one',
      shuffledQueue: [], volume: 0.8, isPlaying: false, currentTrack: tracks[1],
    } });
    await handlers.playTrack(tracks[1]);
    window.freeplayer.playEnd.mockClear();
    window.freeplayer.playStart.mockClear();
    handlers.handleNext();
    await flush();
    // The loop must open a NEW session and close the previous one, otherwise a
    // looping track is recorded as a single session that grows without bound.
    expect(window.freeplayer.playEnd).toHaveBeenCalled();
    expect(window.freeplayer.playStart).toHaveBeenCalledWith(tracks[1].id);
    expect(audio.src).toBe('media://path-B');
    expect(dispatch).not.toHaveBeenCalledWith({ type: 'SET_QUEUE_INDEX', payload: expect.anything() });
  });

  it('handlePrev restarts the track when more than 3s elapsed', () => {
    const { dispatch, audio } = mount();
    audio.currentTime = 5;
    handlers.handlePrev();
    expect(audio.currentTime).toBe(0);
    expect(dispatch).not.toHaveBeenCalledWith({ type: 'SET_QUEUE_INDEX', payload: expect.anything() });
  });

  it('handlePrev dispatches the previous index when restarting is not needed', async () => {
    window.freeplayer.playStart = vi.fn(async () => 1);
    const { dispatch } = mount();
    handlers.handlePrev(); // queueIndex 0 → wraps to last track
    expect(dispatch).toHaveBeenCalledWith({ type: 'SET_QUEUE_INDEX', payload: 3 });
    await flush();
    expect(window.freeplayer.playStart).toHaveBeenCalledWith(tracks[3].id);
  });
});

// ── PlaybackEngine listening accounting ──
// These used to be derived from Date.now() - playStartTimeRef, so a paused or
// backgrounded player kept accruing listening time and reported a "listened
// position" that seeking could inflate.
describe('PlaybackEngine listening accounting', () => {
  function engineWithAudio(duration = 180) {
    const audio = makeAudio();
    audio.duration = duration;
    const bridge = { playStart: vi.fn(async () => 77), playEnd: vi.fn(async () => {}) };
    return { engine: new PlaybackEngine({ audio, bridge }), audio, bridge };
  }

  it('does not count paused time as listening time', async () => {
    const { engine, audio } = engineWithAudio(180);
    engine.bind();
    engine._trackId = 1;
    await engine.openSession(1);

    // Play for 90s, then pause for 300s, then a second 90s segment.
    engine._segmentStart = Date.now() - 90_000;
    audio.currentTime = 90;
    engine._closeSegment();
    await new Promise((r) => setTimeout(r, 5)); // wall clock passes while paused
    engine._segmentStart = Date.now() - 90_000;
    audio.currentTime = 180;
    engine._notePosition(180);

    const snap = engine.sessionSnapshot();
    expect(snap.durationSeconds).toBeGreaterThanOrEqual(179);
    expect(snap.durationSeconds).toBeLessThanOrEqual(181);
    expect(snap.playPercentage).toBe(100);
  });

  it('reports the furthest position reached, so a skip scores low', async () => {
    const { engine, audio } = engineWithAudio(180);
    engine.bind();
    engine._trackId = 1;
    await engine.openSession(1);
    engine._segmentStart = Date.now() - 600_000; // 10 minutes of wall clock
    audio.currentTime = 8;                        // ...but only 8s in
    engine._notePosition(8);

    const snap = engine.sessionSnapshot();
    expect(snap.playPercentage).toBe(4);          // 8/180
    expect(snap.durationSeconds).toBeLessThan(700); // not the whole wall clock
  });

  it('does not lower the percentage when the listener seeks backwards', async () => {
    const { engine, audio } = engineWithAudio(180);
    engine.bind();
    engine._trackId = 1;
    await engine.openSession(1);
    engine._notePosition(120);
    audio.currentTime = 10; // seeked back to the start
    engine._notePosition(10);

    expect(engine.sessionSnapshot().playPercentage).toBe(Math.round((120 / 180) * 100));
  });

  it('closes the previous session when the same track is replayed', async () => {
    const { engine, bridge } = engineWithAudio(180);
    engine.bind();
    window.freeplayer = { ...window.freeplayer, ...bridge };
    engine.bridge = bridge;
    engine._sessionId = 11;
    engine._segmentStart = Date.now() - 181_000;
    await engine.play({ id: 1, file_path: '/x/a.flac' });
    expect(bridge.playEnd).toHaveBeenCalledWith(expect.objectContaining({ sessionId: 11 }));
    expect(bridge.playStart).toHaveBeenCalledWith(1);
  });
});
