import { describe, it, expect, beforeEach, vi } from 'vitest';
import { EQ_PRESETS, EQ_MIN, EQ_MAX, sliderFrac } from '../src/eqPresets';
import { AudioEngine } from '../src/audioEngine';

describe('EQ presets data', () => {
  it('has 6 presets with 10 bands each', () => {
    expect(EQ_PRESETS).toHaveLength(6);
    EQ_PRESETS.forEach((p) => {
      expect(p.name).toBeTruthy();
      expect(p.values).toHaveLength(10);
    });
  });

  it('all values within ±12dB range', () => {
    EQ_PRESETS.forEach((p) => {
      p.values.forEach((v) => {
        expect(v).toBeGreaterThanOrEqual(EQ_MIN);
        expect(v).toBeLessThanOrEqual(EQ_MAX);
      });
    });
  });

  it('flat preset is all zeros', () => {
    const flat = EQ_PRESETS.find((p) => p.name === '平坦');
    expect(flat.values.every((v) => v === 0)).toBe(true);
  });

  it('sliderFrac maps range to 0..1', () => {
    expect(sliderFrac(-12)).toBe(0);
    expect(sliderFrac(0)).toBe(0.5);
    expect(sliderFrac(12)).toBe(1);
  });
});

describe('AudioEngine EQ', () => {
  let engine;
  beforeEach(() => {
    engine = new AudioEngine();
  });

  it('creates 10 peaking filters on connect', () => {
    engine.connect({});
    expect(engine.eqFilters).toHaveLength(10);
    engine.eqFilters.forEach((f, i) => {
      expect(f.type).toBe('peaking');
      expect(f.frequency.value).toBe([31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000][i]);
      expect(f.Q.value).toBe(1.4142);
    });
  });

  it('applyEq sets target gains per band with 0.05s smoothing', () => {
    engine.connect({});
    const gains = [6, 6, 5, 3.5, 2, 0, 0, 0, 0, 0];
    const spies = engine.eqFilters.map((f) => vi.spyOn(f.gain, 'setTargetAtTime'));
    engine.applyEq(gains, true);
    spies.forEach((spy, i) => {
      expect(spy).toHaveBeenCalledWith(gains[i], expect.any(Number), 0.05);
    });
  });

  it('applyEq disabled flattens to 0dB', () => {
    engine.connect({});
    const spies = engine.eqFilters.map((f) => vi.spyOn(f.gain, 'setTargetAtTime'));
    engine.applyEq([6, 6, 5, 3.5, 2, 0, 0, 0, 0, 0], false);
    spies.forEach((spy) => {
      expect(spy).toHaveBeenCalledWith(0, expect.any(Number), 0.05);
    });
  });

  it('applyEq before connect is a no-op', () => {
    expect(() => engine.applyEq([0, 0, 0, 0, 0, 0, 0, 0, 0, 0], true)).not.toThrow();
  });

  it('dispose releases eq filters', () => {
    engine.connect({});
    engine.dispose();
    expect(engine.eqFilters).toBeNull();
  });
});
