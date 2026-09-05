import { describe, it, expect, beforeEach, vi } from 'vitest';
import { EQ_PRESETS, EQ_MIN, EQ_MAX, sliderFrac, eqResponseDb, eqOctaveAt } from '../src/audio/eqPresets';
import { AudioEngine } from '../src/audio/audioEngine';

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
    const flat = EQ_PRESETS.find((p) => p.name === 'Flat');
    expect(flat.values.every((v) => v === 0)).toBe(true);
  });

  it('sliderFrac maps range to 0..1', () => {
    expect(sliderFrac(-12)).toBe(0);
    expect(sliderFrac(0)).toBe(0.5);
    expect(sliderFrac(12)).toBe(1);
  });
});

describe('EQ response curve model', () => {
  it('eqOctaveAt centers band i exactly on octave i', () => {
    EQ_PRESETS[0].values.forEach((_, i) => {
      expect(eqOctaveAt((i + 0.5) / EQ_PRESETS[0].values.length)).toBeCloseTo(i, 10);
    });
  });

  it('a single band peaks at its own gain and falls off with distance', () => {
    const gains = [0, 0, 0, 0, 0, 6, 0, 0, 0, 0];
    expect(eqResponseDb(gains, 5)).toBeCloseTo(6, 10);
    const near = eqResponseDb(gains, 6);
    expect(near).toBeGreaterThan(0);
    expect(near).toBeLessThan(6);
    expect(eqResponseDb(gains, 9)).toBeLessThan(near);
  });

  it('flat preset is silent everywhere', () => {
    for (let x = 0; x <= 1; x += 0.1) {
      expect(Math.abs(eqResponseDb([0, 0, 0, 0, 0, 0, 0, 0, 0, 0], eqOctaveAt(x)))).toBeLessThan(1e-9);
    }
  });

  it('response is symmetric in log-frequency', () => {
    const gains = [0, 0, 0, 0, 0, 0, 0, 4, 0, 0];
    const oct = 7;
    expect(eqResponseDb(gains, oct + 0.5)).toBeCloseTo(eqResponseDb(gains, oct - 0.5), 10);
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

  it('restores pending EQ curve on connect (relaunch path)', () => {
    const originalCreate = window.AudioContext.prototype.createBiquadFilter;
    const filters = [];
    window.AudioContext.prototype.createBiquadFilter = function () {
      const f = originalCreate.call(this);
      f.gain.setTargetAtTime = vi.fn();
      filters.push(f);
      return f;
    };
    try {
      const gains = [6, 6, 5, 3.5, 2, 0, 0, 0, 0, 0];
      engine.applyEq(gains, true);
      engine.connect({});
      expect(filters).toHaveLength(10);
      filters.forEach((f, i) => {
        expect(f.gain.setTargetAtTime).toHaveBeenCalledWith(gains[i], expect.any(Number), 0.05);
      });
    } finally {
      window.AudioContext.prototype.createBiquadFilter = originalCreate;
    }
  });

  it('dispose releases eq filters', () => {
    engine.connect({});
    engine.dispose();
    expect(engine.eqFilters).toBeNull();
  });

  it('wires EQ chain as sole source→analyser path (no parallel edge)', () => {
    const elA = {};
    const elB = { src: 'b' };
    engine.connect(elA);
    const analyserConnect = vi.spyOn(engine.analyser, 'connect');
    const gainConnect = vi.spyOn(engine.gainNode, 'connect');
    const filterConnects = engine.eqFilters.map((f) => vi.spyOn(f, 'connect'));

    engine.connect(elB);

    // source → EQ×10 → analyser → gain → destination: the analyser is
    // downstream of the EQ so the visualizer shows the audible spectrum.
    expect(analyserConnect).toHaveBeenCalledWith(engine.gainNode);
    expect(analyserConnect).not.toHaveBeenCalledWith(engine.eqFilters[0]);
    engine.eqFilters.slice(0, -1).forEach((f, i) => {
      expect(filterConnects[i]).toHaveBeenCalledWith(engine.eqFilters[i + 1]);
    });
    expect(filterConnects[9]).toHaveBeenCalledWith(engine.analyser);
    expect(gainConnect).toHaveBeenCalledWith(engine.ctx.destination);
  });
});
