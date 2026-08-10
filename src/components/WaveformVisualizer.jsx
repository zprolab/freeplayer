import { useRef, useEffect, useCallback } from 'react';
import { audioEngine } from '../audioEngine';

// ── Constants ──
const WAVEFORM_COLOR = '#e24329';
const WAVEFORM_GLOW = 'rgba(226, 67, 41, 0.22)';
const BG_COLOR = '#1a1a1e';
const GRID_COLOR = 'rgba(16, 133, 72, 0.14)';
const GRID_MAJOR = 'rgba(16, 133, 72, 0.28)';
const LABEL_COLOR = 'rgba(255, 255, 255, 0.45)';
const LABEL_DIM = 'rgba(255, 255, 255, 0.25)';

const LAYOUT = {
  waveformTop: 0.08,
  waveformHeight: 0.47,
  dividerH: 0.02,
  spectrumHeight: 0.38,
};

const MIN_SPECTROGRAM_ROWS = 100;
const MAX_SPECTROGRAM_ROWS = 800;

// ── Spectrogram color gradient (thermal camera style) ──
function spectrogramColor(t) {
  if (t <= 0) return [15, 15, 20];
  if (t < 0.2) {
    const s = t / 0.2;
    return [Math.round(15 + 30 * s), Math.round(15 + 30 * s), Math.round(20 + 160 * s)];
  }
  if (t < 0.4) {
    const s = (t - 0.2) / 0.2;
    return [Math.round(45 + 30 * s), Math.round(45 + 150 * s), Math.round(180 + 40 * s)];
  }
  if (t < 0.55) {
    const s = (t - 0.4) / 0.15;
    return [Math.round(75 + 80 * s), Math.round(195 + 40 * s), Math.round(220 - 100 * s)];
  }
  if (t < 0.7) {
    const s = (t - 0.55) / 0.15;
    return [Math.round(155 + 100 * s), Math.round(235 - 30 * s), Math.round(120 - 90 * s)];
  }
  if (t < 0.85) {
    const s = (t - 0.7) / 0.15;
    return [Math.round(255), Math.round(205 - 90 * s), Math.round(30)];
  }
  return [255, Math.round(115 - 30 * ((t - 0.85) / 0.15)), 0];
}

// ── Spectrogram history buffer (module-level, survives remount) ──
let spectrogramBuffer = null;

// Reusable per-frame buffers (avoid 2+ heap allocations per animation frame)
let sharedTimeData = null;
let sharedFreqData = null;
let specImageData = null;

// ═══════════════════════════════════════════════════════════════
//  Component
// ═══════════════════════════════════════════════════════════════

export default function WaveformVisualizer({ audioElement, trackId, mode, onModeChange }) {
  const canvasRef = useRef(null);
  const ctxRef = useRef(null);
  const animFrameRef = useRef(null);

  // Reset spectrogram history when track changes
  useEffect(() => {
    spectrogramBuffer = null;
  }, [trackId]);

  // Resume suspended context on play
  useEffect(() => {
    if (!audioElement) return;
    const resume = () => {
      audioEngine.resume();
      audioEngine.connect(audioElement);
    };
    audioElement.addEventListener('play', resume);
    return () => audioElement.removeEventListener('play', resume);
  }, [audioElement]);

  // Canvas sizing — cap the backing scale: the visualizer is a live display,
  // 1.5x keeps it sharp while halving canvas + ImageData memory vs 2x Retina.
  // P2: cached CSS size so the draw loop never forces a layout read per frame.
  const sizeRef = useRef({ w: 0, h: 0 });
  const sizeCanvas = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    const dpr = Math.min(window.devicePixelRatio || 1, 1.5);
    if (canvas.width !== rect.width * dpr || canvas.height !== rect.height * dpr) {
      canvas.width = rect.width * dpr;
      canvas.height = rect.height * dpr;
      const ctx = canvas.getContext('2d');
      ctx.scale(dpr, dpr);
      ctxRef.current = ctx;
    }
    sizeRef.current = { w: rect.width, h: rect.height };
  }, []);

  useEffect(() => {
    sizeCanvas();
    window.addEventListener('resize', sizeCanvas);
    return () => window.removeEventListener('resize', sizeCanvas);
  }, [sizeCanvas]);

  // ── Draw loop ──
  useEffect(() => {
    if (mode === 'off') return;

    const canvas = canvasRef.current;
    if (!canvas) return;

    let running = true;

    const schedule = () => {
      if (!running) return;
      // P2: when paused, drop to ~4fps — 60fps no-signal painting is wasted work
      if (audioElement && audioElement.paused) {
        animFrameRef.current = setTimeout(draw, 250);
      } else {
        animFrameRef.current = requestAnimationFrame(draw);
      }
    };

    const draw = () => {
      if (!running || mode === 'off') return;
      // Layout reads only when the size is unknown (resize listener keeps it fresh)
      if (sizeRef.current.w === 0) sizeCanvas();
      const ctx = ctxRef.current;
      const W = sizeRef.current.w;
      const H = sizeRef.current.h;

      const an = audioElement ? audioEngine.connect(audioElement) : null;

      if (!ctx || !an || !W || !H) {
        if (ctx && W && H) drawNoSignal(ctx, W, H);
        schedule();
        return;
      }

      const bufferLen = an.frequencyBinCount;
      if (!sharedFreqData || sharedFreqData.length !== bufferLen) {
        sharedFreqData = new Uint8Array(bufferLen);
        sharedTimeData = new Uint8Array(bufferLen);
      }
      an.getByteFrequencyData(sharedFreqData);
      an.getByteTimeDomainData(sharedTimeData);

      if (mode === 'spectrogram') {
        drawSpectrogramMode(ctx, sharedFreqData, bufferLen, W, H);
      } else {
        drawWaveformMode(ctx, sharedFreqData, sharedTimeData, bufferLen, W, H);
      }

      schedule();
    };

    draw();

    return () => {
      running = false;
      if (animFrameRef.current) {
        cancelAnimationFrame(animFrameRef.current);
        clearTimeout(animFrameRef.current);
        animFrameRef.current = null;
      }
    };
  }, [audioElement, trackId, mode, sizeCanvas]);

  if (mode === 'off') {
    return (
      <div className="visualizer visualizer--off">
        <div className="visualizer-off-inner">
          <span className="visualizer-off-label mono">VISUALIZER OFF</span>
          <button className="visualizer-off-btn" onClick={() => onModeChange('waveform')} title="Press V to enable">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
              <polyline points="4 12 10 18 20 6"/>
            </svg>
            Enable
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="visualizer">
      <canvas ref={canvasRef} className="visualizer-canvas" />

      {/* Mode switch controls */}
      <div className="visualizer-controls">
        <div className="vis-mode-group">
          <button
            className={`vis-mode-btn ${mode === 'waveform' ? 'vis-mode-btn--active' : ''}`}
            onClick={() => onModeChange('waveform')}
            title="Oscilloscope + Spectrum (V to toggle, Shift+V to cycle)"
          >
            <svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5">
              <polyline points="1,8 4,3 7,10 10,6 13,13 15,9"/>
            </svg>
          </button>
          <button
            className={`vis-mode-btn ${mode === 'spectrogram' ? 'vis-mode-btn--active' : ''}`}
            onClick={() => onModeChange('spectrogram')}
            title="Spectrogram Waterfall"
          >
            <svg width="12" height="12" viewBox="0 0 16 16" fill="currentColor">
              <rect x="1" y="1" width="3" height="14" rx="0.5" opacity="0.3"/>
              <rect x="5" y="3" width="3" height="12" rx="0.5" opacity="0.5"/>
              <rect x="9" y="5" width="3" height="10" rx="0.5" opacity="0.7"/>
              <rect x="13" y="2" width="2" height="13" rx="0.5" opacity="0.9"/>
            </svg>
          </button>
        </div>
        <button
          className="vis-mode-btn vis-mode-btn--off"
          onClick={() => onModeChange('off')}
          title="Turn Off Visualizer"
        >
          <svg width="10" height="10" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
            <line x1="4" y1="4" x2="12" y2="12"/>
            <line x1="12" y1="4" x2="4" y2="12"/>
          </svg>
        </button>
      </div>

    </div>
  );
}

// ═══════════════════════════════════════════════════════════════
//  Mode: Waveform + Spectrum bars
// ═══════════════════════════════════════════════════════════════

function drawWaveformMode(ctx, freqData, timeData, bufferLen, W, H) {
  // Solid background — prevents transparent-canvas bleed-through
  ctx.fillStyle = BG_COLOR;
  ctx.fillRect(0, 0, W, H);

  const wfTop = Math.round(H * LAYOUT.waveformTop);
  const wfH = Math.round(H * LAYOUT.waveformHeight);
  const divH = Math.round(H * LAYOUT.dividerH);
  const spTop = wfTop + wfH + divH;
  const spH = Math.round(H * LAYOUT.spectrumHeight);
  const spBaseline = spTop + spH;

  drawGrid(ctx, W, H, wfTop, wfH, spTop, spH, spBaseline);
  drawWaveform(ctx, timeData, W, wfTop, wfH);

  // Check if any frequency data is above noise floor (P2: no spread — the
  // 1024-element spread allocates an argument array every frame)
  let maxFreq = 0;
  for (let i = 0; i < freqData.length; i++) {
    if (freqData[i] > maxFreq) maxFreq = freqData[i];
  }
  if (maxFreq > 5) {
    drawSpectrum(ctx, freqData, W, spTop, spH);
  }

  drawLabels(ctx, W, H, wfTop, wfH, spBaseline);

  // Subtle peak indicator bar — confirms data is flowing
  const peakW = Math.min((maxFreq / 255) * (W - 20), W - 20);
  ctx.fillStyle = `rgba(226, 67, 41, ${0.15 + (maxFreq / 255) * 0.4})`;
  ctx.fillRect(10, H - 3, peakW, 1.5);
}

// ═══════════════════════════════════════════════════════════════
//  Mode: Spectrogram (waterfall heatmap)
// ═══════════════════════════════════════════════════════════════

function drawSpectrogramMode(ctx, freqData, bufferLen, W, H) {
  ctx.fillStyle = BG_COLOR;
  ctx.fillRect(0, 0, W, H);

  const marginTop = 18;
  const marginBottom = 42;
  const marginLeft = 12;
  const marginRight = 12;
  const plotW = W - marginLeft - marginRight;
  const plotH = H - marginTop - marginBottom;

  // Dynamic row count: 1 row per pixel of plot height (capped)
  const numRows = Math.max(MIN_SPECTROGRAM_ROWS, Math.min(MAX_SPECTROGRAM_ROWS, Math.floor(plotH)));

  // Initialize or resize spectrogram buffer
  if (!spectrogramBuffer) {
    spectrogramBuffer = new Array(numRows);
    for (let i = 0; i < numRows; i++) {
      spectrogramBuffer[i] = new Uint8Array(bufferLen);
    }
  } else if (spectrogramBuffer.length !== numRows) {
    const oldLen = spectrogramBuffer.length;
    const newBuffer = new Array(numRows);
    if (numRows > oldLen) {
      const diff = numRows - oldLen;
      for (let i = 0; i < diff; i++) {
        newBuffer[i] = new Uint8Array(bufferLen);
      }
      for (let i = 0; i < oldLen; i++) {
        newBuffer[diff + i] = spectrogramBuffer[i];
      }
    } else {
      const diff = oldLen - numRows;
      for (let i = 0; i < numRows; i++) {
        newBuffer[i] = spectrogramBuffer[diff + i];
      }
    }
    spectrogramBuffer = newBuffer;
  }

  // Shift history up, append new frequency data at the end (P2: reuse the
  // row buffer instead of allocating a fresh Uint8Array every frame)
  spectrogramBuffer.copyWithin(0, 1);
  spectrogramBuffer[numRows - 1].set(freqData);

  // DIAGNOSTIC (FP_SPECTRO_TEST=1): overwrite the newest row with a known
  // 4-quadrant brightness pattern to verify frequency mapping:
  //   left 1/4 = 255 (loudest) -> right 1/4 = 0 (silent)
  if (window.__FP_SPECTRO_TEST) {
    const testRow = spectrogramBuffer[numRows - 1];
    const q = bufferLen / 4;
    for (let i = 0; i < bufferLen; i++) {
      testRow[i] = i < q ? 255 : i < q * 2 ? 170 : i < q * 3 ? 85 : 0;
    }
  }

  const binStep = bufferLen / plotW;
  const rowH = Math.max(1, Math.ceil(plotH / numRows));

  // ── Render spectrogram via putImageData at device-pixel resolution ──
  // Reuse the ImageData buffer across frames (only realloc on size change).
  // dpr MUST match sizeCanvas' cap (min(devicePixelRatio, 1.5)) — putImageData
  // writes raw device pixels and clips at the canvas backing store.
  const dpr = Math.min(window.devicePixelRatio || 1, 1.5);
  const dw = Math.round(W * dpr);
  const dh = Math.round(H * dpr);
  const dmTop = Math.round(18 * dpr);
  const dmBottom = Math.round(42 * dpr);
  const dmLeft = Math.round(12 * dpr);
  const dmRight = Math.round(12 * dpr);
  const dplotW = dw - dmLeft - dmRight;
  const dplotH = dh - dmTop - dmBottom;
  if (dplotW <= 0 || dplotH <= 0) return;

  if (!specImageData || specImageData.width !== dplotW || specImageData.height !== dplotH) {
    specImageData = ctx.createImageData(dplotW, dplotH);
  }
  const pixels = specImageData.data;

  const dRowH = Math.max(1, Math.round(dplotH / numRows));
  for (let row = 0; row < numRows; row++) {
    const imgY = dplotH - 1 - Math.round((row / (numRows - 1)) * (dplotH - 1));
    const srcRow = spectrogramBuffer[row];

    for (let px = 0; px < dplotW; px++) {
      const binIdx = Math.floor((px / dpr) * binStep);
      const val = srcRow[Math.min(binIdx, bufferLen - 1)] / 255;
      const [r, g, b] = spectrogramColor(val);

      for (let dy = 0; dy < dRowH && (imgY + dy) < dplotH; dy++) {
        const base = ((imgY + dy) * dplotW + px) * 4;
        pixels[base] = r;
        pixels[base + 1] = g;
        pixels[base + 2] = b;
        pixels[base + 3] = 255;
      }
    }
  }

  ctx.putImageData(specImageData, dmLeft, dmTop);

  // Grid overlay
  ctx.strokeStyle = 'rgba(16, 133, 72, 0.10)';
  ctx.lineWidth = 0.5;
  for (let i = 1; i < 8; i++) {
    const y = Math.round(marginTop + (plotH / 8) * i) + 0.5;
    ctx.beginPath();
    ctx.moveTo(marginLeft, y);
    ctx.lineTo(W - marginRight, y);
    ctx.stroke();
  }

  // Frequency labels
  const freqY = H - 14;
  ctx.font = '9px "JetBrains Mono", monospace';
  ctx.fillStyle = LABEL_COLOR;
  ctx.textBaseline = 'bottom';
  ctx.textAlign = 'center';
  const freqLabels = [
    { hz: '20',  xFrac: 0.04 }, { hz: '100', xFrac: 0.22 },
    { hz: '500', xFrac: 0.40 }, { hz: '2k',  xFrac: 0.58 },
    { hz: '8k',  xFrac: 0.76 }, { hz: '20k', xFrac: 0.94 },
  ];
  freqLabels.forEach(({ hz, xFrac }) => {
    ctx.fillText(hz, marginLeft + plotW * xFrac, freqY);
  });
  ctx.textAlign = 'right';
  ctx.fillStyle = LABEL_DIM;
  ctx.fillText('Hz', W - marginRight, freqY);

  // Time labels on right edge
  ctx.textAlign = 'left';
  ctx.font = '7px "JetBrains Mono", monospace';
  ctx.fillStyle = LABEL_DIM;
  ctx.fillText('now', W - marginRight + 4, marginTop + 8);
  ctx.fillText('←', W - marginRight + 4, marginTop + plotH);

  // Peak indicator (P2: loop instead of Math.max(...) spread per frame)
  let maxFreq = 0;
  for (let i = 0; i < freqData.length; i++) {
    if (freqData[i] > maxFreq) maxFreq = freqData[i];
  }
  const peakW = Math.min((maxFreq / 255) * plotW, plotW);
  ctx.fillStyle = `rgba(226, 67, 41, ${0.15 + (maxFreq / 255) * 0.5})`;
  ctx.fillRect(marginLeft, H - 3, peakW, 1.5);
}

// ═══════════════════════════════════════════════════════════════
//  No signal / idle
// ═══════════════════════════════════════════════════════════════

function drawNoSignal(ctx, W, H) {
  ctx.fillStyle = BG_COLOR;
  ctx.fillRect(0, 0, W, H);
  ctx.fillStyle = LABEL_DIM;
  ctx.font = '11px "JetBrains Mono", monospace';
  ctx.textAlign = 'center';
  ctx.fillText('NO SIGNAL', W / 2, H / 2);
}

// ═══════════════════════════════════════════════════════════════
//  Drawing functions (waveform mode)
// ═══════════════════════════════════════════════════════════════

function drawGrid(ctx, W, H, wfTop, wfH, spTop, spH, spBaseline) {
  const wfBot = wfTop + wfH;
  const spBot = spTop + spH;
  const gridVCount = 16;

  ctx.strokeStyle = GRID_COLOR;
  ctx.lineWidth = 0.5;
  for (let i = 1; i < gridVCount; i++) {
    const x = Math.round((W / gridVCount) * i) + 0.5;
    ctx.beginPath(); ctx.moveTo(x, wfTop); ctx.lineTo(x, wfBot); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(x, spTop); ctx.lineTo(x, spBot); ctx.stroke();
  }

  const wfMid = wfTop + wfH / 2;
  ctx.strokeStyle = GRID_COLOR;
  ctx.lineWidth = 0.5;
  [0.25, 0.75].forEach(ratio => {
    const y = Math.round(wfTop + wfH * ratio) + 0.5;
    ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(W, y); ctx.stroke();
  });
  ctx.strokeStyle = GRID_MAJOR;
  ctx.beginPath();
  ctx.moveTo(0, Math.round(wfMid) + 0.5);
  ctx.lineTo(W, Math.round(wfMid) + 0.5);
  ctx.stroke();

  [0.25, 0.5, 0.75].forEach(ratio => {
    const y = Math.round(spTop + spH * (1 - ratio)) + 0.5;
    ctx.strokeStyle = GRID_COLOR;
    ctx.lineWidth = 0.5;
    ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(W, y); ctx.stroke();
  });

  ctx.strokeStyle = GRID_MAJOR;
  ctx.lineWidth = 0.6;
  ctx.beginPath();
  ctx.moveTo(0, Math.round(spBaseline) + 0.5);
  ctx.lineTo(W, Math.round(spBaseline) + 0.5);
  ctx.stroke();
}

function drawWaveform(ctx, timeData, W, wfTop, wfH) {
  const midY = wfTop + wfH / 2;
  const sliceW = W / timeData.length;
  const amplitude = wfH * 0.46;

  const trace = (color, width) => {
    ctx.strokeStyle = color;
    ctx.lineWidth = width;
    ctx.beginPath();
    for (let i = 0; i < timeData.length; i++) {
      const v = timeData[i] / 128.0;
      const y = midY + (v - 1) * amplitude;
      const x = i * sliceW;
      i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
    }
    ctx.stroke();
  };

  trace(WAVEFORM_GLOW, 5);
  trace('rgba(226, 67, 41, 0.38)', 2);
  ctx.globalAlpha = 0.92;
  trace(WAVEFORM_COLOR, 1);
  ctx.globalAlpha = 1;
}

function drawSpectrum(ctx, dataArray, W, spTop, spH) {
  const barCount = 128;
  const step = Math.floor(dataArray.length / barCount);
  const totalW = W - 20;
  const startX = 10;
  const barW = (totalW / barCount) * 0.68;
  const gapW = (totalW / barCount) * 0.32;

  for (let i = 0; i < barCount; i++) {
    let sum = 0;
    for (let j = 0; j < step; j++) sum += dataArray[i * step + j];
    const avg = sum / step;
    const barH = (avg / 255) * spH;
    const x = startX + i * (barW + gapW);
    const y = spTop + spH - barH;

    const t = avg / 255;
    const r = Math.round(45 + t * 75);
    const g = Math.round(100 + t * 50);
    const b = Math.round(195 + t * 35);
    ctx.fillStyle = `rgb(${r}, ${g}, ${b})`;
    ctx.fillRect(x, y, Math.max(barW, 1.5), barH);
  }
}

function drawLabels(ctx, W, H, wfTop, wfH, spBaseline) {
  ctx.font = '10px "JetBrains Mono", monospace';
  ctx.textBaseline = 'middle';

  const wfMid = wfTop + wfH / 2;
  ctx.fillStyle = LABEL_DIM;
  ctx.textAlign = 'left';
  ctx.fillText('L', 12, wfMid);
  ctx.textAlign = 'right';
  ctx.fillText('R', W - 12, wfMid);

  const ampTop = wfTop + wfH * 0.04;
  const ampBot = wfTop + wfH * 0.96;
  ctx.strokeStyle = LABEL_DIM;
  ctx.lineWidth = 0.5;
  ctx.beginPath(); ctx.moveTo(8, ampTop); ctx.lineTo(16, ampTop); ctx.stroke();
  ctx.beginPath(); ctx.moveTo(8, ampBot); ctx.lineTo(16, ampBot); ctx.stroke();
  ctx.font = '7px "JetBrains Mono", monospace';
  ctx.textAlign = 'left';
  ctx.fillText('+1', 18, ampTop);
  ctx.fillText('−1', 18, ampBot);

  const divY = wfTop + wfH;
  ctx.strokeStyle = GRID_MAJOR;
  ctx.lineWidth = 0.5;
  ctx.beginPath();
  ctx.moveTo(10, Math.round(divY) + 0.5);
  ctx.lineTo(W - 10, Math.round(divY) + 0.5);
  ctx.stroke();

  const freqY = spBaseline + 14;
  ctx.font = '9px "JetBrains Mono", monospace';
  ctx.fillStyle = LABEL_COLOR;
  ctx.textBaseline = 'top';
  ctx.textAlign = 'center';
  const freqLabels = [
    { hz: '20',  xFrac: 0.04 },
    { hz: '100', xFrac: 0.22 },
    { hz: '500', xFrac: 0.40 },
    { hz: '2k',  xFrac: 0.58 },
    { hz: '8k',  xFrac: 0.76 },
    { hz: '20k', xFrac: 0.94 },
  ];
  freqLabels.forEach(({ hz, xFrac }) => {
    ctx.fillText(hz, 10 + (W - 20) * xFrac, freqY);
  });
  ctx.textAlign = 'right';
  ctx.fillStyle = LABEL_DIM;
  ctx.fillText('Hz', W - 12, freqY);

}
