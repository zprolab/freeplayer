import { useEffect, useRef, useState, useMemo, useCallback } from 'react';
import { parseLRC } from '@/features/lyrics/lrc.js';
import { formatTime } from '@/utils/format.js';
import { useActiveLineScroll } from '@/features/lyrics/useActiveLineScroll.js';
import { accentFor, cssRgb } from '@/features/playback/ambientColor.js';

// Zoom ladder. Module scope because it is a constant, not state.
const ZOOM_STEPS = [-2, -1, 0, 1, 2, 3, 4];

export default function ImmersiveMode({
  track, lrcContent, currentTime, duration, coverUrl,
  isPlaying, onSeek, onTogglePlay, onNext, onPrev, onClose,
}) {
  const lyrics = useMemo(() => parseLRC(lrcContent), [lrcContent]);
  const listRef = useRef(null);
  const [zoom, setZoom] = useState(0); // 0=normal, each ±1 = step
  const baseSize = 22;
  const fontSize = baseSize + zoom * 4;

  // Active line
  const activeIndex = useMemo(() => {
    if (!lyrics.length) return -1;
    let idx = -1;
    for (let i = 0; i < lyrics.length; i++) {
      if (lyrics[i].time <= currentTime) idx = i;
      else break;
    }
    return idx;
  }, [lyrics, currentTime]);

  // Auto-scroll
  useActiveLineScroll(listRef, activeIndex, '.immersive-line--active');

  // Esc to close
  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  const progress = duration > 0 ? (currentTime / duration) * 100 : 0;

  const zoomIn = useCallback(() => {
    setZoom((z) => {
      const idx = ZOOM_STEPS.indexOf(z);
      return idx < ZOOM_STEPS.length - 1 ? ZOOM_STEPS[idx + 1] : z;
    });
  }, []);
  const zoomOut = useCallback(() => {
    setZoom((z) => {
      const idx = ZOOM_STEPS.indexOf(z);
      return idx > 0 ? ZOOM_STEPS[idx - 1] : z;
    });
  }, []);

  // Extract the dominant color from the cover art for the ambient glow
  const [bgColor, setBgColor] = useState(null);
  // Accent derived from the same average colour as the background, so the
  // highlight belongs to the artwork instead of fighting it. Null until the
  // cover resolves, in which case the CSS falls back to the brand accent.
  const accent = useMemo(() => accentFor(bgColor), [bgColor]);
  useEffect(() => {
    let stale = false;
    if (!coverUrl) {
      setBgColor(null);
      return;
    }
    const img = new Image();
    img.onload = () => {
      if (stale) return;
      try {
        const canvas = document.createElement('canvas');
        // 24x24 rather than 8x8: a flat average of very few pixels blends the
        // artwork's actual colours into a muddy mid-tone, and the accent derived
        // from it then no longer resembles the cover.
        canvas.width = 24;
        canvas.height = 24;
        const ctx = canvas.getContext('2d', { willReadFrequently: true });
        ctx.drawImage(img, 0, 0, 24, 24);
        const d = ctx.getImageData(0, 0, 24, 24).data;
        // Weight each pixel by its saturation, so the artwork's CHROMA decides
        // the ambient colour instead of whatever covers the most area. A flat
        // mean lets a large muted background swamp a smaller vivid figure.
        let r = 0, g = 0, b = 0, w = 0;
        for (let i = 0; i < d.length; i += 4) {
          const [pr, pg, pb] = [d[i], d[i + 1], d[i + 2]];
          const max = Math.max(pr, pg, pb);
          const min = Math.min(pr, pg, pb);
          // Saturation 0..1, then squared so near-grey pixels barely count.
          const sat = max === 0 ? 0 : (max - min) / max;
          const weight = sat * sat;
          r += pr * weight; g += pg * weight; b += pb * weight; w += weight;
        }
        // Fully grey artwork has no chroma to weight by — fall back to the mean.
        if (w === 0) {
          let sr = 0, sg = 0, sb = 0;
          for (let i = 0; i < d.length; i += 4) { sr += d[i]; sg += d[i + 1]; sb += d[i + 2]; }
          const n = d.length / 4;
          setBgColor({ r: Math.round(sr / n), g: Math.round(sg / n), b: Math.round(sb / n) });
          return;
        }
        setBgColor({ r: Math.round(r / w), g: Math.round(g / w), b: Math.round(b / w) });
      } catch {
        setBgColor(null);
      }
    };
    img.onerror = () => { if (!stale) setBgColor(null); };
    img.src = coverUrl;
    return () => { stale = true; };
  }, [coverUrl]);

  return (
    <div
      className="immersive-overlay"
      // One accent for the whole view — the active lyric, its left indicator and
      // the progress fill all read this. Derived from the cover's average colour
      // with lightness inverted against the background, so it stays legible on
      // dark and light artwork alike (see ambientColor.js). Before the cover has
      // been sampled the variable is simply absent, and the CSS fallback is a
      // NEUTRAL white — the brand red used to be that fallback, which is why the
      // view flashed red for a moment on open and then settled into the cover's
      // colour. The accent also transitions, so the change reads as a settle
      // rather than a jump.
      style={accent ? { '--immersive-accent': cssRgb(accent) } : undefined}
    >
      {/* Ambient background: blurred cover + dark tint + dominant-color glow */}
      <div className="immersive-bg">
        {coverUrl && <img src={coverUrl} alt="" className="immersive-bg-img" />}
        <div className="immersive-bg-tint" />
        {bgColor ? (
          <div
            className="immersive-bg-glow"
            style={{
              background: `
                radial-gradient(ellipse 85% 65% at 50% 35%, rgba(${bgColor.r}, ${bgColor.g}, ${bgColor.b}, 0.5) 0%, transparent 70%),
                radial-gradient(ellipse 55% 80% at 18% 80%, rgba(${bgColor.r}, ${bgColor.g}, ${bgColor.b}, 0.28) 0%, transparent 65%),
                radial-gradient(ellipse 45% 70% at 82% 75%, rgba(${bgColor.r}, ${bgColor.g}, ${bgColor.b}, 0.2) 0%, transparent 60%)
              `,
            }}
          />
        ) : (
          <div className="immersive-bg-glow immersive-bg-glow--fallback" />
        )}
      </div>

      {/* ── Top bar: cover + track info + zoom + close ── */}
      <div className="immersive-top">
        <div className="immersive-cover-wrap">
          {coverUrl ? (
            <img src={coverUrl} alt="" className={`immersive-cover ${isPlaying ? 'immersive-cover--spin' : ''}`} />
          ) : (
            <div className="immersive-cover-placeholder">
              <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1">
                <path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>
              </svg>
            </div>
          )}
        </div>
        <div className="immersive-track-info">
          <div className="immersive-title">{track?.title || '—'}</div>
          <div className="immersive-artist">{track?.artist || '—'}</div>
        </div>

        <div className="immersive-top-spacer" />

        {/* Zoom controls */}
        <div className="immersive-zoom">
          <button className="immersive-zoom-btn" onClick={zoomOut} disabled={zoom <= ZOOM_STEPS[0]}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"><line x1="5" y1="12" x2="19" y2="12"/></svg>
          </button>
          <span className="immersive-zoom-label mono">{fontSize}px</span>
          <button className="immersive-zoom-btn" onClick={zoomIn} disabled={zoom >= ZOOM_STEPS[ZOOM_STEPS.length - 1]}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
          </button>
        </div>

        <button className="immersive-close-btn" onClick={onClose} title="Exit immersive mode (Esc)">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
            <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
          </svg>
        </button>
      </div>

      {/* ── Center: lyrics ── */}
      {lyrics.length === 0 ? (
        <div className="immersive-no-lyrics">
          <div className="immersive-no-lyrics-cover">
            {coverUrl ? (
              <img src={coverUrl} alt="" className="immersive-no-lyrics-cover-img" />
            ) : (
              <div className="immersive-no-lyrics-cover-p">
                <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="0.8">
                  <path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>
                </svg>
              </div>
            )}
          </div>
          <h2 className="immersive-no-lyrics-title">{track?.title || '—'}</h2>
          <p className="immersive-no-lyrics-artist">{track?.artist || '—'}</p>
          <p className="immersive-no-lyrics-msg">No synced lyrics</p>
          <p className="immersive-no-lyrics-hint">Upload an <code>.lrc</code> file for this track to see time-synced lyrics here</p>
        </div>
      ) : (
        <div className="immersive-lyrics" ref={listRef}>
          {lyrics.map((entry, idx) => {
            const isActive = idx === activeIndex;
            const isPast = idx < activeIndex;
            const isNear = Math.abs(idx - activeIndex) <= 2;
            return (
              <div
                key={idx}
                className={`immersive-line${isActive ? ' immersive-line--active' : ''}${isPast ? ' immersive-line--past' : ''}${!isActive && !isPast && !isNear ? ' immersive-line--distant' : ''}`}
                style={{ fontSize: `${isActive ? fontSize : Math.max(12, fontSize - 6)}px` }}
              >
                <span className="immersive-time mono">{formatTime(entry.time)}</span>
                <span className="immersive-text">{entry.text}</span>
              </div>
            );
          })}
        </div>
      )}

      {/* ── Bottom: progress + controls ── */}
      <div className="immersive-bottom">
        <div className="immersive-progress-section">
          <div className="immersive-progress-bar" onClick={(e) => {
            const rect = e.currentTarget.getBoundingClientRect();
            onSeek((e.clientX - rect.left) / rect.width * duration);
          }}>
            <div className="immersive-progress-fill" style={{ width: `${progress}%` }} />
          </div>
          <div className="immersive-time-row mono">
            <span>{formatTime(currentTime)}</span>
            <span>{formatTime(duration)}</span>
          </div>
        </div>

        <div className="immersive-controls">
          <button className="immersive-ctrl-btn" onClick={onPrev}>
            <svg width="28" height="28" viewBox="0 0 24 24" fill="currentColor">
              <polygon points="19,20 9,12 19,4 19,20"/><rect x="4" y="4" width="3" height="16"/>
            </svg>
          </button>
          <button className="immersive-ctrl-btn immersive-ctrl-btn--play" onClick={onTogglePlay}>
            {isPlaying ? (
              <svg width="40" height="40" viewBox="0 0 24 24" fill="currentColor">
                <rect x="5" y="3" width="5" height="18" rx="1.5"/><rect x="14" y="3" width="5" height="18" rx="1.5"/>
              </svg>
            ) : (
              <svg width="40" height="40" viewBox="0 0 24 24" fill="currentColor">
                <polygon points="6,3 20,12 6,21"/>
              </svg>
            )}
          </button>
          <button className="immersive-ctrl-btn" onClick={onNext}>
            <svg width="28" height="28" viewBox="0 0 24 24" fill="currentColor">
              <polygon points="5,4 15,12 5,20 5,4"/><rect x="17" y="4" width="3" height="16"/>
            </svg>
          </button>
        </div>
      </div>
    </div>
  );
}
