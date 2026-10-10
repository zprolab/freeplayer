// Micro-benchmark for the visualiser's per-frame work on the main thread.
//
// The two hot loops (spectrogram blit, waveform envelope) live inside
// WaveformVisualizer.jsx and are not exported, so they are reproduced here with
// the same constants and buffer sizes the component uses. Purpose: find out
// whether the visualiser can hold 60fps on a realistic canvas, and how the cost
// splits between the FFT size and the pixel work.
//
// Run: node scripts/bench-visualizer.mjs

const CSS_W = 900;          // Now Playing scope panel width
const CSS_H = 360;
const DPR = 1.5;            // sizeCanvas caps the backing scale at 1.5
const DW = Math.round(CSS_W * DPR);
const DH = Math.round(CSS_H * DPR);
const DM_TOP = Math.round(18 * DPR);
const DM_BOTTOM = Math.round(42 * DPR);
const DM_LEFT = Math.round(12 * DPR);
const DM_RIGHT = Math.round(12 * DPR);
const DPLOT_W = DW - DM_LEFT - DM_RIGHT;
const DPLOT_H = DH - DM_TOP - DM_BOTTOM;
const NUM_ROWS = Math.min(800, Math.max(100, Math.floor(CSS_H - 18 - 42)));

const LUT = new Uint8ClampedArray(256 * 4);
for (let i = 0; i < 256; i++) {
  LUT[i * 4] = i; LUT[i * 4 + 1] = i; LUT[i * 4 + 2] = i; LUT[i * 4 + 3] = 255;
}

function makeBuffer(binCount) {
  return Array.from({ length: NUM_ROWS }, () => {
    const row = new Uint8Array(binCount);
    for (let i = 0; i < binCount; i++) row[i] = (i * 7 + Math.random() * 8) & 0xff;
    return row;
  });
}

// ── spectrogram: build one row into a scratch buffer, then blit per screen row ──
function benchSpectrogram({ binCount, sampleRate }) {
  const buffer = makeBuffer(binCount);
  const pixels = new Uint8ClampedArray(DPLOT_W * DPLOT_H * 4);
  let scratch = new Uint8ClampedArray(DPLOT_W * 4);

  const F_MIN = 20; const F_MAX = 20000;
  const LOG_SPAN = Math.log(F_MAX / F_MIN);
  const binForColumn = new Int32Array(DPLOT_W);
  const freqAtLogFrac = (x) => F_MIN * Math.exp(LOG_SPAN * Math.min(Math.max(x, 0), 1));
  for (let px = 0; px < DPLOT_W; px++) {
    const f = freqAtLogFrac(px / Math.max(DPLOT_W - 1, 1));
    binForColumn[px] = Math.min(binCount - 1, Math.max(0, Math.round((f / (sampleRate / 2)) * binCount)));
  }
  if (scratch.length < DPLOT_W * 4) scratch = new Uint8ClampedArray(DPLOT_W * 4);

  return () => {
    for (let row = 0; row < NUM_ROWS; row++) {
      const srcRow = buffer[row];
      for (let px = 0; px < DPLOT_W; px++) {
        const v = srcRow[binForColumn[px]];
        const lo = v * 4;
        const o = px * 4;
        scratch[o] = LUT[lo]; scratch[o + 1] = LUT[lo + 1];
        scratch[o + 2] = LUT[lo + 2]; scratch[o + 3] = 255;
      }
      const y0 = Math.round(((NUM_ROWS - 1 - row) / NUM_ROWS) * DPLOT_H);
      const y1 = row === 0 ? DPLOT_H : Math.round(((NUM_ROWS - row) / NUM_ROWS) * DPLOT_H);
      if (y1 <= y0) continue;
      const blit = scratch.subarray(0, DPLOT_W * 4);
      const base = y0 * DPLOT_W * 4;
      for (let y = y0; y < y1; y++) pixels.set(blit, base + (y - y0) * DPLOT_W * 4);
    }
  };
}

// ── waveform: per-column min/max envelope over fftSize samples ──
function benchWaveform({ fftSize }) {
  const timeData = new Uint8Array(fftSize);
  for (let i = 0; i < fftSize; i++) timeData[i] = 128 + Math.round(100 * Math.sin(i / 20));
  const cols = Math.round(DW);
  const minBuf = new Float32Array(cols);
  const maxBuf = new Float32Array(cols);
  const amp = DPLOT_H * 0.46;
  const perCol = fftSize / cols;
  return () => {
    for (let px = 0; px < cols; px++) {
      const start = Math.floor(px * perCol);
      const end = px === cols - 1 ? fftSize : Math.min(fftSize, Math.max(start + 1, Math.floor((px + 1) * perCol)));
      let lo = timeData[start]; let hi = lo;
      for (let i = start + 1; i < end; i++) {
        const v = timeData[i];
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
      minBuf[px] = lo; maxBuf[px] = hi;
    }
    void amp; void minBuf; void maxBuf;
  };
}

function time(label, fn, reps) {
  fn(); // warm up
  const t0 = process.hrtime.bigint();
  for (let i = 0; i < reps; i++) fn();
  const ms = Number(process.hrtime.bigint() - t0) / 1e6 / reps;
  const pct = (ms / 16.7) * 100;
  console.log(`  ${label.padEnd(34)} ${ms.toFixed(2).padStart(6)} ms/frame   ${pct.toFixed(0).padStart(4)}% of 60fps budget`);
  return ms;
}

console.log(`canvas ${CSS_W}x${CSS_H} css @${DPR}x -> ${DW}x${DH} device, plot ${DPLOT_W}x${DPLOT_H}, ${NUM_ROWS} rows`);
console.log('note: JS-only cost; native canvas compositing is separate\n');

for (const tier of [{ name: 'Reactive (2048)', fftSize: 2048 }, { name: 'Balanced (8192)', fftSize: 8192 }, { name: 'Precise (16384)', fftSize: 16384 }]) {
  const binCount = tier.fftSize / 2;
  console.log(`${tier.name}:`);
  time('spectrogram blit', benchSpectrogram({ binCount, sampleRate: 44100 }), 30);
  time('waveform envelope', benchWaveform({ fftSize: tier.fftSize }), 30);
  console.log('');
}
