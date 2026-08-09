import { useState, useRef, useCallback, useEffect } from 'react';
import { EQ_BANDS, EQ_MIN, EQ_MAX, EQ_STEP, EQ_PRESETS, sliderFrac } from '../eqPresets';

const THUMB = 12;
const SLIDER_H = 118;

const api = () => window.freeplayer || null;

export default function EqWindow() {
  const [enabled, setEnabled] = useState(false);
  const [preset, setPreset] = useState('平坦');
  const [gains, setGains] = useState(() => EQ_PRESETS[0].values.slice());
  const wrapRefs = useRef([]);
  const thumbRefs = useRef([]);
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
      a.getEqState().then((s) => { if (s) push(s); });
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

  const handleToggle = (e) => {
    commit({ enabled: e.target.checked, preset, gains });
  };

  // Hardware-rack style: faders only (no curve overlay)
  useEffect(() => {
    gains.forEach((v, i) => {
      const t = thumbRefs.current[i];
      if (t) t.style.bottom = `${sliderFrac(v) * (SLIDER_H - THUMB)}px`;
    });
  }, [gains]);

  const sum = gains.reduce((a, v) => a + Math.abs(v), 0);
  const effectLabel = enabled
    ? (sum < 0.5 ? '未生效(平坦)' : `已生效 · ${preset}`)
    : '未启用';

  return (
    <div className="eq-root">
      <div className="eq-titlebar">
        <span className="eq-title">均衡器</span>
        <span className={`eq-led ${enabled ? 'eq-led--on' : ''}`} />
      </div>
      <div className="eq-toprow">
        <span className={`eq-state ${enabled && sum >= 0.5 ? 'eq-state--on' : ''}`}>{effectLabel}</span>
        <label className="eq-toggle">
          启用均衡器
          <input type="checkbox" checked={enabled} onChange={handleToggle} />
          <span className="eq-switch" />
        </label>
      </div>
      <div className="eq-slider-area">
        <div className="eq-cols">
          {EQ_BANDS.map((freq, i) => (
            <div className="eq-col" key={freq}>
              <span className={`eq-db ${Math.abs(gains[i]) > 0.4 && enabled ? 'eq-db--hot' : ''}`}>
                {(gains[i] >= 0 ? '+' : '') + gains[i].toFixed(1)}
              </span>
              <div className="eq-slider-wrap" ref={(el) => { wrapRefs.current[i] = el; }}>
                <div className="eq-slider-track" />
                <div className={`eq-slider-thumb ${enabled ? 'eq-slider-thumb--on' : ''}`} ref={(el) => { thumbRefs.current[i] = el; }} />
                <input
                  type="range"
                  className="eq-slider-input"
                  min={EQ_MIN}
                  max={EQ_MAX}
                  step={EQ_STEP}
                  value={gains[i]}
                  onChange={handleSlider(i)}
                />
              </div>
              <span className="eq-freq">{freq >= 1000 ? `${freq / 1000}k` : freq}</span>
            </div>
          ))}
        </div>
      </div>
      <div className="eq-presets">
        {EQ_PRESETS.map((p) => (
          <button
            key={p.name}
            className={`eq-chip ${preset === p.name ? 'eq-chip--active' : ''}`}
            onClick={() => handlePreset(p)}
          >
            {p.name}
          </button>
        ))}
      </div>
    </div>
  );
}
