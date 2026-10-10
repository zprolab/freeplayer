import { describe, it, expect, vi, beforeEach } from 'vitest';

// Same lightweight react harness as useTraySettings.test.js: useEffect/useState
// are driven by call order so the settings load effect and the change handler
// can be exercised without a DOM renderer.
const { hookState } = vi.hoisted(() => ({
  hookState: { effects: [], states: [], stateIndex: 0 },
}));

vi.mock('react', async (importOriginal) => {
  const actual = await importOriginal();
  return {
    ...actual,
    useEffect: (cb) => { hookState.effects.push(cb); },
    useCallback: (fn) => fn,
    useState: (init) => {
      const idx = hookState.stateIndex++;
      if (!hookState.states[idx]) hookState.states[idx] = { value: typeof init === 'function' ? init() : init };
      return [hookState.states[idx].value, (v) => { hookState.states[idx].value = v; }];
    },
  };
});

vi.mock('../src/audio/audioEngine', () => {
  const listeners = new Set();
  return {
    audioEngine: {
      _size: 8192,
      setFftSize(size) { this._size = size; listeners.forEach((l) => l(size)); return size; },
      getFftSize() { return this._size; },
      subscribeFftSize(l) { listeners.add(l); return () => listeners.delete(l); },
      __listeners: listeners,
    },
  };
});

import { audioEngine } from '../src/audio/audioEngine';
import {
  useVisualizerQuality, QUALITY_TIERS, SETTING_KEY,
} from '../src/hooks/useVisualizerQuality';

function reset() {
  hookState.effects = [];
  hookState.states = [];
  hookState.stateIndex = 0;
  audioEngine.__listeners.clear();
  audioEngine._size = 8192;
}

// The load effect is the only effect in the hook.
function runEffects() {
  hookState.effects.forEach((fn) => fn());
}

beforeEach(() => {
  reset();
  window.freeplayer = {
    getSetting: vi.fn(async () => null),
    setSetting: vi.fn(async () => true),
  };
});

describe('useVisualizerQuality', () => {
  it('persists the tier under the key the native allowlist accepts', async () => {
    const { changeQuality } = useVisualizerQuality();
    runEffects();
    changeQuality('precise');
    await Promise.resolve();
    // The original bug: this key was missing from FPBridge's allowlist, so every
    // write answered false and the preference reverted on the next launch.
    expect(window.freeplayer.setSetting).toHaveBeenCalledWith({ key: SETTING_KEY, value: 'precise' });
    expect(SETTING_KEY).toBe('visualizer_quality');
  });

  it('applies the tier to the analyser so the engine is the live source of truth', () => {
    const { changeQuality } = useVisualizerQuality();
    runEffects();
    changeQuality('reactive');
    expect(audioEngine.getFftSize()).toBe(2048);
    changeQuality('precise');
    expect(audioEngine.getFftSize()).toBe(16384);
  });

  it('loads the stored tier on mount', async () => {
    window.freeplayer.getSetting = vi.fn(async () => 'precise');
    useVisualizerQuality();
    runEffects();
    await Promise.resolve();
    await Promise.resolve();
    expect(window.freeplayer.getSetting).toHaveBeenCalledWith(SETTING_KEY);
    expect(audioEngine.getFftSize()).toBe(16384);
  });

  it('falls back to the default for an unknown stored value', async () => {
    window.freeplayer.getSetting = vi.fn(async () => 'nonsense');
    useVisualizerQuality();
    runEffects();
    await Promise.resolve();
    await Promise.resolve();
    expect(audioEngine.getFftSize()).toBe(8192);
  });

  it('logs when the write is rejected instead of failing silently', async () => {
    const err = vi.spyOn(console, 'error').mockImplementation(() => {});
    window.freeplayer.setSetting = vi.fn(async () => false);
    const { changeQuality } = useVisualizerQuality();
    runEffects();
    changeQuality('balanced');
    await Promise.resolve();
    await Promise.resolve();
    expect(err).toHaveBeenCalled();
    err.mockRestore();
  });

  it('exposes the tier table used by both the Settings page and the visualizer', () => {
    const { tiers } = useVisualizerQuality();
    runEffects();
    expect(tiers).toBe(QUALITY_TIERS);
    expect(tiers.map((t) => t.fftSize)).toEqual([2048, 8192, 16384]);
  });
});
