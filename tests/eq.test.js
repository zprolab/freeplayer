import { describe, it, expect } from 'vitest';
import { EQ_PRESETS, EQ_MIN, EQ_MAX, sliderFrac } from '../src/eqPresets';

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
