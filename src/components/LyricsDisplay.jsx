import { useMemo, useRef } from 'react';
import { parseLRC } from '../utils/lrc';
import { formatTime } from '../utils/format';
import { useActiveLineScroll } from '../hooks/useActiveLineScroll';

export default function LyricsDisplay({
  lrcContent, currentTime = 0, onUpload, onRemove, onImmersive, autoScroll = false,
  onFetchLyrics, fetchingLyrics, lyricsFetchFailed,
}) {
  const lyrics = useMemo(() => parseLRC(lrcContent), [lrcContent]);
  const listRef = useRef(null);

  // Find active line index
  const activeIndex = useMemo(() => {
    if (!lyrics.length) return -1;
    let idx = -1;
    for (let i = 0; i < lyrics.length; i++) {
      if (lyrics[i].time <= currentTime) idx = i;
      else break;
    }
    return idx;
  }, [lyrics, currentTime]);

  // Auto-scroll only when enabled (immersive mode handles its own)
  useActiveLineScroll(listRef, activeIndex, '.lyrics-line--active', autoScroll);

  // Empty state — no LRC file uploaded
  if (!lyrics.length) {
    return (
      <div className="lyrics-container">
        <div className="lyrics-empty">
          <div className="lyrics-empty-icon">
            <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1" strokeLinecap="round" strokeLinejoin="round">
              <path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/>
              <path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/>
              <line x1="8" y1="7" x2="16" y2="7"/>
              <line x1="8" y1="11" x2="14" y2="11"/>
            </svg>
          </div>
          <p className="lyrics-empty-text">No synced lyrics</p>
          <p className="lyrics-empty-hint">
            Upload an <code>.lrc</code> file or fetch from LRCLIB
          </p>
          {onFetchLyrics && (
            <button
              className="lyrics-upload-btn"
              onClick={onFetchLyrics}
              disabled={fetchingLyrics}
            >
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
                <polyline points="7 10 12 15 17 10"/>
                <line x1="12" y1="15" x2="12" y2="3"/>
              </svg>
              {fetchingLyrics ? 'Fetching…' : lyricsFetchFailed ? 'No lyrics found' : 'Fetch Lyrics'}
            </button>
          )}
          {onUpload && (
            <button className="lyrics-upload-btn" onClick={onUpload}>
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
                <polyline points="17 8 12 3 7 8"/>
                <line x1="12" y1="3" x2="12" y2="15"/>
              </svg>
              Upload .lrc File
            </button>
          )}
          {onImmersive && (
            <button className="lyrics-upload-btn" onClick={onImmersive}>
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="15 3 21 3 21 9"/>
                <polyline points="9 21 3 21 3 15"/>
                <line x1="21" y1="3" x2="14" y2="10"/>
                <line x1="3" y1="21" x2="10" y2="14"/>
              </svg>
              Fullscreen View
            </button>
          )}
        </div>
      </div>
    );
  }

  return (
    <div className="lyrics-container">
      {/* Metadata header */}
      <div className="lyrics-meta-header">
        <span className="lyrics-meta-badge">LRC</span>
        <span className="lyrics-meta-count">{lyrics.length} lines</span>
        <div className="lyrics-meta-spacer" />
        {onImmersive && (
          <button className="lyrics-immersive-btn" onClick={onImmersive} title="Immersive mode">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <polyline points="15 3 21 3 21 9"/>
              <polyline points="9 21 3 21 3 15"/>
              <line x1="21" y1="3" x2="14" y2="10"/>
              <line x1="3" y1="21" x2="10" y2="14"/>
            </svg>
          </button>
        )}
        {onRemove && (
          <button className="lyrics-remove-btn" onClick={onRemove} title="Remove lyrics">
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
              <polyline points="3 6 5 6 21 6"/>
              <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>
            </svg>
          </button>
        )}
      </div>

      {/* Lyrics list */}
      <div className="lyrics-list" ref={listRef}>
        {lyrics.map((entry, idx) => {
          const isActive = idx === activeIndex;
          const isPast = idx < activeIndex;
          const isNear = Math.abs(idx - activeIndex) <= 2;

          return (
            <div
              key={idx}
              className={
                `lyrics-line${isActive ? ' lyrics-line--active' : ''}${isPast ? ' lyrics-line--past' : ''}${!isActive && !isPast && !isNear ? ' lyrics-line--distant' : ''}`
              }
            >
              <span className="lyrics-time mono">{formatTime(entry.time)}</span>
              <span className="lyrics-text">{entry.text}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}
