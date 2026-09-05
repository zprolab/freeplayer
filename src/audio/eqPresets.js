export const EQ_BANDS = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
export const EQ_MIN = -12;
export const EQ_MAX = 12;
export const EQ_STEP = 0.5;

export const EQ_PRESETS = [
  { name: '平坦', values: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0] },
  { name: '低音增强', values: [6, 6, 5, 3.5, 2, 0, 0, 0, 0, 0] },
  { name: '人声清晰', values: [0, 0, 0, 0, 0, 3, 3, 3, 2, 0] },
  { name: '古典', values: [3, 3, 2, 0, 0, 0, 0, 1.5, 2, 3] },
  { name: '摇滚', values: [5, 5, 4, 2, 0, 0, 1, 3, 4.5, 5] },
  { name: '流行', values: [0.5, 1, 1.5, 2.5, 3, 3, 2.5, 1.5, 1, 0.5] },
];

export function sliderFrac(value, min = EQ_MIN, max = EQ_MAX) {
  return (value - min) / (max - min);
}

/* ── Response-curve model ──────────────────────────────────────────────
   The face draws the audible response of the EQ chain, not a decoration:
   each column is one octave (31 Hz → 16 kHz is 9 octaves, so equal spacing
   IS log spacing), and every band contributes a bell bump in log-frequency
   whose width approximates the peaking filters actually applied at runtime
   (Q ≈ √2 → a half-power width close to one octave).
   x is normalized across the visible face (0..1); EQ_BAND_SIGMA is in octaves. */

export const EQ_BAND_SIGMA = 0.42; // octaves — skirts of a Q≈√2 peaking filter
const EQ_EDGE_OCT = 0.5; // one half-octave of overshoot beyond 31 Hz / 16 kHz

export function eqOctaveAt(x) {
  return x * (EQ_BANDS.length - 1 + 2 * EQ_EDGE_OCT) - EQ_EDGE_OCT;
}

export function eqResponseDb(gains, oct) {
  let db = 0;
  for (let i = 0; i < gains.length; i += 1) {
    const d = oct - i;
    db += gains[i] * Math.exp(-(d * d) / (2 * EQ_BAND_SIGMA * EQ_BAND_SIGMA));
  }
  return db;
}
