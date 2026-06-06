import React, { useEffect, useRef, useState, useMemo, useCallback } from 'react';

/* ── LRC Parser (shared — mirror of LyricsDisplay) ── */

function parseLRC(raw) {
  if (!raw) return [];
  const lines = raw.split(/\r?\n/);
  const entries = [];
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    const timeRegex = /\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]/g;
    const times = [];
    let match;
    while ((match = timeRegex.exec(trimmed)) !== null) {
      const minutes = parseInt(match[1], 10);
      const seconds = parseInt(match[2], 10);
      const centiseconds = match[3] ? parseInt(match[3].padEnd(2, '0').slice(0, 2), 10) : 0;
      times.push(minutes * 60 + seconds + centiseconds / 100);
    }
    if (times.length === 0) continue;
    const textStart = trimmed.lastIndexOf(']') + 1;
    const text = trimmed.slice(textStart).trim();
    if (!text) continue;
    for (const time of times) entries.push({ time, text });
  }
  entries.sort((a, b) => a.time - b.time);
  const deduped = [];
  for (let i = 0; i < entries.length; i++) {
    if (i === 0 || entries[i].text !== entries[i - 1].text) deduped.push(entries[i]);
  }
  return deduped;
}

function formatTime(seconds) {
  if (!seconds || !isFinite(seconds)) return '0:00';
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, '0')}`;
}

/* ── Color extraction from cover image ── */

function extractColorFromCover(coverUrl) {
  return new Promise((resolve) => {
    if (!coverUrl) { resolve('160,140,100'); return; }
    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.onload = () => {
      const canvas = document.createElement('canvas');
      const size = 4; // tiny sample
      canvas.width = size;
      canvas.height = size;
      const ctx = canvas.getContext('2d');
      try {
        ctx.drawImage(img, 0, 0, size, size);
        const data = ctx.getImageData(0, 0, size, size).data;
        let r = 0, g = 0, b = 0, count = 0;
        for (let i = 0; i < data.length; i += 4) {
          r += data[i];
          g += data[i + 1];
          b += data[i + 2];
          count++;
        }
        resolve(`${Math.round(r / count)},${Math.round(g / count)},${Math.round(b / count)}`);
      } catch (_) {
        resolve('160,140,100');
      }
    };
    img.onerror = () => resolve('160,140,100');
    img.src = coverUrl;
  });
}

export default function ImmersiveMode({
  track, lrcContent, currentTime, duration, coverUrl,
  isPlaying, onSeek, onTogglePlay, onNext, onPrev, onClose,
}) {
  const lyrics = useMemo(() => parseLRC(lrcContent), [lrcContent]);
  const listRef = useRef(null);
  const prevActiveRef = useRef(-1);
  const [bgColor, setBgColor] = useState('30,25,18');
  const [zoom, setZoom] = useState(0); // 0=normal, each ±1 = step
  const ZOOM_STEPS = [-2, -1, 0, 1, 2, 3, 4];
  const baseSize = 22;
  const fontSize = baseSize + zoom * 4;

  // Extract dominant color from cover for background
  useEffect(() => {
    let stale = false;
    extractColorFromCover(coverUrl).then((c) => { if (!stale) setBgColor(c); });
    return () => { stale = true; };
  }, [coverUrl]);

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
  useEffect(() => {
    if (activeIndex !== prevActiveRef.current && listRef.current) {
      const el = listRef.current.querySelector('.immersive-line--active');
      if (el) el.scrollIntoView({ behavior: 'smooth', block: 'center' });
      prevActiveRef.current = activeIndex;
    }
  }, [activeIndex]);

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

  return (
    <div
      className="immersive-overlay"
      style={{
        '--im-bg-rgb': bgColor,
      }}
    >
      {/* Animated background gradient */}
      <div
        className="immersive-bg"
        style={{
          background: `
            radial-gradient(ellipse 80% 60% at 50% 40%, rgba(${bgColor},0.22) 0%, transparent 70%),
            radial-gradient(ellipse 50% 80% at 20% 20%, rgba(${bgColor},0.12) 0%, transparent 60%),
            radial-gradient(ellipse 40% 60% at 80% 80%, rgba(${bgColor},0.08) 0%, transparent 50%),
            #0d0d10
          `,
        }}
      />

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
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><line x1="5" y1="12" x2="19" y2="12"/></svg>
          </button>
          <span className="immersive-zoom-label mono">{fontSize}px</span>
          <button className="immersive-zoom-btn" onClick={zoomIn} disabled={zoom >= ZOOM_STEPS[ZOOM_STEPS.length - 1]}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
          </button>
        </div>

        <button className="immersive-close-btn" onClick={onClose} title="Exit immersive mode (Esc)">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
            <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
          </svg>
        </button>
      </div>

      {/* ── Center: lyrics ── */}
      <div className="immersive-lyrics" ref={listRef}>
        {lyrics.length === 0 ? (
          <div className="immersive-no-lyrics">
            <p>No synced lyrics available</p>
          </div>
        ) : (
          lyrics.map((entry, idx) => {
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
          })
        )}
      </div>

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
