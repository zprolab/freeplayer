import React from 'react';
import { EQ_BANDS, EQ_MIN, EQ_MAX, EQ_STEP, EQ_PRESETS, sliderFrac } from '../eqPresets';

const THUMB = 15;
const SLIDER_H = 118;
const VB_W = 580;
const VB_H = 168;

const api = () => window.freeplayer || null;

export default function EqWindow() {
  const [enabled, setEnabled] = React.useState(false);
  const [preset, setPreset] = React.useState('平坦');
  const [gains, setGains] = React.useState(() => EQ_PRESETS[0].values.slice());
  const areaRef = React.useRef(null);
  const curveRef = React.useRef(null);
  const wrapRefs = React.useRef([]);
  const thumbRefs = React.useRef([]);
  const stateRef = React.useRef({ enabled: false, preset: '平坦', gains: EQ_PRESETS[0].values.slice() });
  const commitTimer = React.useRef(null);
  stateRef.current = { enabled, preset, gains };

  const push = React.useCallback((next) => {
    setEnabled(next.enabled);
    setPreset(next.preset);
    setGains(next.gains.slice());
  }, []);

  React.useEffect(() => {
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

  const commit = React.useCallback((next) => {
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

  const draw = React.useCallback(() => {
    const area = areaRef.current;
    const curve = curveRef.current;
    if (!area || !curve) return;
    const svgRect = curve.getBoundingClientRect();
    const xscale = VB_W / svgRect.width;
    const yscale = VB_H / svgRect.height;
    const mid = VB_H / 2;
    const range = EQ_MAX - EQ_MIN;
    const pts = gains.map((v, i) => {
      const wrapRect = wrapRefs.current[i].getBoundingClientRect();
      const frac = sliderFrac(v);
      const x = (wrapRect.left + wrapRect.width / 2 - svgRect.left) * xscale;
      const y = (wrapRect.top - svgRect.top + THUMB / 2 + (1 - frac) * (SLIDER_H - THUMB)) * yscale;
      return `${x.toFixed(1)},${y.toFixed(1)}`;
    });
    const active = enabled;
    const baseL = 12 * xscale;
    const baseR = (svgRect.width - 12) * xscale;
    curve.innerHTML =
      `<polyline points="${pts.join(' ')}" fill="none" stroke="${active ? '#e24329' : '#55575d'}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round" opacity="${active ? 0.95 : 0.35}"></polyline>` +
      `<polygon points="${pts.join(' ')} ${baseR.toFixed(1)},${mid} ${baseL.toFixed(1)},${mid}" fill="${active ? '#e24329' : '#55575d'}" opacity="${active ? 0.12 : 0.05}"></polygon>`;
  }, [enabled, gains]);

  React.useEffect(() => {
    gains.forEach((v, i) => {
      const t = thumbRefs.current[i];
      if (t) t.style.bottom = `${sliderFrac(v) * (SLIDER_H - THUMB)}px`;
    });
    draw();
  }, [gains, enabled, draw]);

  React.useEffect(() => {
    draw();
    window.addEventListener('resize', draw);
    if (document.fonts?.ready) document.fonts.ready.then(draw);
    return () => window.removeEventListener('resize', draw);
  }, [draw]);

  const sum = gains.reduce((a, v) => a + Math.abs(v), 0);
  const effectLabel = enabled
    ? (sum < 0.5 ? '未生效(平坦)' : `已生效 · ${preset}`)
    : '未启用';

  return (
    <div className="eq-root">
      <div className="eq-titlebar">
        <span className="eq-title">均衡器</span>
      </div>
      <div className="eq-toprow">
        <span className={`eq-state ${enabled && sum >= 0.5 ? 'eq-state--on' : ''}`}>{effectLabel}</span>
        <label className="eq-toggle">
          启用均衡器
          <input type="checkbox" checked={enabled} onChange={handleToggle} />
          <span className="eq-switch" />
        </label>
      </div>
      <div className="eq-slider-area" ref={areaRef}>
        <div className="eq-zero-line" />
        <svg className="eq-curve" ref={curveRef} viewBox={`0 0 ${VB_W} ${VB_H}`} preserveAspectRatio="none" />
        <div className="eq-cols">
          {EQ_BANDS.map((freq, i) => (
            <div className="eq-col" key={freq}>
              <span className={`eq-db ${Math.abs(gains[i]) > 0.4 && enabled ? 'eq-db--hot' : ''}`}>
                {(gains[i] >= 0 ? '+' : '') + gains[i].toFixed(1)}
              </span>
              <div className="eq-slider-wrap" ref={(el) => { wrapRefs.current[i] = el; }}>
                <div className="eq-slider-track" />
                <div className="eq-slider-thumb" ref={(el) => { thumbRefs.current[i] = el; }} />
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
