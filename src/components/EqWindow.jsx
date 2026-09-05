import { useState, useRef, useCallback, useEffect, useMemo } from 'react';
import {
  EQ_BANDS, EQ_MIN, EQ_MAX, EQ_STEP, EQ_PRESETS, sliderFrac,
  eqOctaveAt, eqResponseDb,
} from '../audio/eqPresets';
import ToggleSwitch from './ToggleSwitch';

/* The face is one shared coordinate space: fader caps and the response
   curve map through the same dB → pixel function, so the drawn curve
   always meets the caps it comes from. Geometry is driven by these
   constants (mirrored onto .eq-root as CSS custom properties). */
const READOUT_H = 16; // column value strip above the fader
const TRAVEL_H = 152; // fader slot travel
const FREQ_H = 14;    // frequency label strip below the fader
const THUMB_H = 14;   // fader cap height
const SAMPLE_STEP = 0.5; // svg units between response samples

const api = () => window.freeplayer || null;

function dbToY(db) {
  const f = sliderFrac(db);
  const yPx = (1 - f) * (TRAVEL_H - THUMB_H) + THUMB_H / 2;
  return (yPx / TRAVEL_H) * 100;
}

function bandLabel(freq) {
  return freq >= 1000 ? `${freq / 1000}k` : String(freq);
}

function dbText(value) {
  const sign = value >= 0 ? '+' : '-';
  return `${sign}${Math.abs(value).toFixed(1)}`;
}

const GRID_DB = [-12, -9, -6, -3, 0, 3, 6, 9, 12];
// One octave per band means the columns are evenly spaced; faint verticals
// at the column boundaries turn the scope into an octave lattice.
const BAND_LINES = Array.from({ length: EQ_BANDS.length - 1 }, (_, i) => (i + 1) * 10);

function buildScope(gains) {
  const samples = [];
  for (let x = 0; x <= 100 + 1e-6; x += SAMPLE_STEP) {
    const db = eqResponseDb(gains, eqOctaveAt(x / 100));
    samples.push({ x, y: dbToY(db), db });
  }
  const line = `M ${samples.map((s) => `${s.x.toFixed(2)} ${s.y.toFixed(2)}`).join(' L ')}`;
  // Boost silhouette: the curve wherever it sits above 0 dB, flattened to
  // the 0 line elsewhere, closed along that line on the way back.
  const zeroY = dbToY(0);
  const boost = samples
    .map((s) => (s.db > 0 ? `${s.x.toFixed(2)} ${s.y.toFixed(2)}` : `${s.x.toFixed(2)} ${zeroY.toFixed(2)}`))
    .join(' L ');
  const fill = `M ${boost} L 100 ${zeroY.toFixed(2)} L 0 ${zeroY.toFixed(2)} Z`;
  return { line, fill };
}

export default function EqWindow() {
  const [enabled, setEnabled] = useState(false);
  const [preset, setPreset] = useState('平坦');
  const [gains, setGains] = useState(() => EQ_PRESETS[0].values.slice());
  const stateRef = useRef({ enabled: false, preset: '平坦', gains: EQ_PRESETS[0].values.slice() });
  const commitTimer = useRef(null);
  stateRef.current = { enabled, preset, gains };

  const push = useCallback((next) => {
    setEnabled(next.enabled);
    setPreset(next.preset);
    setGains(next.gains.slice());
  }, []);

  useEffect(() => {
    const a = api();
    if (a?.getEqState) {
      a.getEqState().then((s) => { if (s) push(s); })
        .catch((err) => console.warn('Failed to load EQ state:', err));
    }
    if (a?.onEqChange) {
      a.onEqChange((s) => {
        if (s && (s.preset !== stateRef.current.preset || s.enabled !== stateRef.current.enabled
            || s.gains.some((g, i) => g !== stateRef.current.gains[i]))) {
          push(s);
        }
      });
    }
  }, [push]);

  const commit = useCallback((next) => {
    push(next);
    clearTimeout(commitTimer.current);
    commitTimer.current = setTimeout(() => {
      api()?.setEq?.(next);
    }, 150);
  }, [push]);

  const handleSlider = (i) => (e) => {
    const v = parseFloat(e.target.value);
    const g = gains.slice();
    g[i] = v;
    commit({ enabled, preset: '自定义', gains: g });
  };

  const handlePreset = (p) => {
    commit({ enabled, preset: p.name, gains: p.values.slice() });
  };

  const handleToggle = (next) => {
    commit({ enabled: next, preset, gains });
  };

  const scope = useMemo(() => buildScope(gains), [gains]);

  const sum = gains.reduce((a, v) => a + Math.abs(v), 0);
  const live = enabled && sum >= 0.5;
  const status = enabled
    ? (sum < 0.5 ? '生效中 · 平坦' : `生效中 · ${preset}`)
    : '已旁路';
  const grid = GRID_DB.map((db) => ({ db, y: dbToY(db) }));
  // Cap and rail-fill positions come from the same dB → pixel mapping the
  // curve uses, so a column's cap always sits on the curve.
  const centerPx = (TRAVEL_H - THUMB_H) / 2;

  return (
    <div
      className="eq-root"
      style={{
        '--eq-readout': `${READOUT_H}px`,
        '--eq-travel': `${TRAVEL_H}px`,
        '--eq-freq': `${FREQ_H}px`,
        '--eq-thumb': `${THUMB_H}px`,
      }}
    >
      <header className="eq-header">
        <div className="eq-heading">
          <h1 className="eq-title">均衡器</h1>
          <span className={`eq-badge${enabled ? ' eq-badge--on' : ''}`}>{status}</span>
        </div>
        <div className="eq-enable">
          <span>启用</span>
          <ToggleSwitch checked={enabled} onChange={handleToggle} label="启用均衡器" />
        </div>
      </header>

      <section className={`eq-card${enabled ? '' : ' eq-card--off'}`}>
        <div className="eq-canvas">
          <svg
            className={`eq-scope${live ? ' eq-scope--live' : ''}`}
            viewBox="0 0 100 100"
            preserveAspectRatio="none"
            aria-hidden="true"
          >
            {grid.map(({ db, y }) => (
              <line
                key={db}
                className={db === 0 ? 'eq-grid eq-grid--zero' : db === 12 || db === -12 ? 'eq-grid eq-grid--edge' : 'eq-grid'}
                x1="0" x2="100" y1={y} y2={y}
                vectorEffect="non-scaling-stroke"
              />
            ))}
            {BAND_LINES.map((x) => (
              <line key={x} className="eq-grid eq-grid--v" x1={x} x2={x} y1="0" y2="100" vectorEffect="non-scaling-stroke" />
            ))}
            <path className="eq-scope-fill" d={scope.fill} vectorEffect="non-scaling-stroke" />
            <path className="eq-scope-line" d={scope.line} vectorEffect="non-scaling-stroke" />
          </svg>
          <div className="eq-cols">
            {EQ_BANDS.map((freq, i) => {
              const hot = enabled && Math.abs(gains[i]) > 0.4;
              const capPx = sliderFrac(gains[i]) * (TRAVEL_H - THUMB_H);
              const fillStyle = {
                bottom: `${Math.min(capPx, centerPx)}px`,
                height: `${Math.abs(capPx - centerPx)}px`,
              };
              return (
                <div className="eq-col" key={freq}>
                  <span className={`eq-readout${hot ? ' eq-readout--hot' : ''}`}>
                    {dbText(gains[i])}
                  </span>
                  <div className="eq-slot">
                    <span className="eq-rail" aria-hidden="true" />
                    <span className="eq-fill" style={fillStyle} aria-hidden="true" />
                    <span
                      className={`eq-cap${hot ? ' eq-cap--hot' : ''}`}
                      style={{ bottom: `${capPx}px` }}
                      aria-hidden="true"
                    />
                    <input
                      type="range"
                      className="eq-slider"
                      min={EQ_MIN}
                      max={EQ_MAX}
                      step={EQ_STEP}
                      value={gains[i]}
                      onChange={handleSlider(i)}
                      aria-label={`${freq} 赫兹频段增益`}
                      aria-valuetext={dbText(gains[i])}
                    />
                  </div>
                  <span className="eq-freq">{bandLabel(freq)}</span>
                </div>
              );
            })}
          </div>
        </div>
      </section>

      <div className="eq-presets">
        {EQ_PRESETS.map((p) => (
          <button
            key={p.name}
            type="button"
            className={`eq-chip${preset === p.name ? ' eq-chip--active' : ''}`}
            onClick={() => handlePreset(p)}
          >
            {p.name}
          </button>
        ))}
      </div>
    </div>
  );
}
