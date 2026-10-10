#!/usr/bin/env node
// Summarises the visualiser profiling probe from the app's diagnostics log.
//
// The probe only exists in a build made with VITE_FP_PERF=1 (see
// WaveformVisualizer.jsx); it reports one line per 5s window:
//   PERF VISUALIZER mode=<waveform|spectrogram> frames=N avg=Xms max=Yms over=Zms
//
// Run: node scripts/perf-report.mjs [path-to-log]

import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

const LOG = process.argv[2]
  || join(homedir(), 'Library', 'Application Support', 'FreePlayer', 'diagnostics', 'freeplayer-diagnostics.log');

let text;
try {
  text = readFileSync(LOG, 'utf8');
} catch (err) {
  console.error(`cannot read ${LOG}: ${err.message}`);
  process.exit(1);
}

const samples = [];
for (const line of text.split('\n')) {
  const m = line.match(/PERF VISUALIZER mode=(\w+) frames=(\d+) avg=([\d.]+)ms max=([\d.]+)ms over=([\d.]+)ms/);
  if (m) samples.push({ mode: m[1], frames: +m[2], avg: +m[3], max: +m[4], over: +m[5] });
}

if (!samples.length) {
  console.log('no PERF VISUALIZER samples in the log.');
  console.log('the probe requires a build made with VITE_FP_PERF=1.');
  process.exit(0);
}

const byMode = new Map();
for (const s of samples) {
  if (!byMode.has(s.mode)) byMode.set(s.mode, []);
  byMode.get(s.mode).push(s);
}

console.log(`samples: ${samples.length} windows from ${LOG}\n`);
console.log(`${'mode'.padEnd(13)}${'windows'.padStart(8)}${'fps'.padStart(8)}${'avg ms'.padStart(9)}${'max ms'.padStart(9)}${'% of 60fps'.padStart(12)}`);
for (const [mode, list] of byMode) {
  const frames = list.reduce((n, s) => n + s.frames, 0);
  const over = list.reduce((n, s) => n + s.over, 0);
  const avg = list.reduce((n, s) => n + s.avg, 0) / list.length;
  const max = Math.max(...list.map((s) => s.max));
  const fps = over > 0 ? (frames / over) * 1000 : 0;
  console.log(`${mode.padEnd(13)}${String(list.length).padStart(8)}${fps.toFixed(1).padStart(8)}${avg.toFixed(2).padStart(9)}${max.toFixed(2).padStart(9)}${((avg / 16.7) * 100).toFixed(0).padStart(11)}%`);
}

console.log('\ninterpretation:');
console.log('  avg is the draw-loop cost only (JS + canvas calls queued), not native compositing.');
console.log('  fps well below 60 with a paused element is expected: the loop drops to ~4fps (250ms timer) when audio is paused.');
