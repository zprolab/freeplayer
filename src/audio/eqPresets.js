export const EQ_BANDS = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
export const EQ_MIN = -12;
export const EQ_MAX = 12;
export const EQ_STEP = 0.5;

export const EQ_PRESETS = [
  { name: 'Flat', values: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0] },
  { name: 'Bass Boost', values: [6, 6, 5, 3.5, 2, 0, 0, 0, 0, 0] },
  { name: 'Vocal', values: [0, 0, 0, 0, 0, 3, 3, 3, 2, 0] },
  { name: 'Classical', values: [3, 3, 2, 0, 0, 0, 0, 1.5, 2, 3] },
  { name: 'Rock', values: [5, 5, 4, 2, 0, 0, 1, 3, 4.5, 5] },
  { name: 'Pop', values: [0.5, 1, 1.5, 2.5, 3, 3, 2.5, 1.5, 1, 0.5] },
];

/* Preset identity is its name (persisted in the DB and matched by the UI),
   so renames ship with this map: states saved under the old Chinese names
   normalize on load instead of decaying into an unmatched preset. */
const EQ_LEGACY_PRESET_NAMES = {
  '平坦': 'Flat',
  '低音增强': 'Bass Boost',
  '人声清晰': 'Vocal',
  '古典': 'Classical',
  '摇滚': 'Rock',
  '流行': 'Pop',
  '自定义': 'Custom',
};

export function normalizePreset(name) {
  return EQ_LEGACY_PRESET_NAMES[name] ?? name;
}

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
