import React, { useMemo, useRef, useEffect } from 'react';

/**
 * Parse raw LRC text into an array of { time, text } entries.
 * Handles: [mm:ss.xx]text, [mm:ss]text, multi-timestamp lines,
 * and metadata tags like [ti:], [ar:], [al:], [length:].
 */
function parseLRC(raw) {
  if (!raw) return [];

  const lines = raw.split(/\r?\n/);
  const entries = [];

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;

    // Collect all time tags on this line
    const timeRegex = /\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]/g;
    const times = [];
    let match;
    while ((match = timeRegex.exec(trimmed)) !== null) {
      const minutes = parseInt(match[1], 10);
      const seconds = parseInt(match[2], 10);
      const centiseconds = match[3]
        ? parseInt(match[3].padEnd(2, '0').slice(0, 2), 10)
        : 0;
      times.push(minutes * 60 + seconds + centiseconds / 100);
    }

    if (times.length === 0) continue; // metadata line, skip

    // Get the text after the last time tag
    const textStart = trimmed.lastIndexOf(']') + 1;
    const text = sanitizeText(trimmed.slice(textStart).trim());
    if (!text) continue; // skip empty lyric lines

    for (const time of times) {
      entries.push({ time, text });
    }
  }

  // Sort by time
  entries.sort((a, b) => a.time - b.time);

  // Deduplicate adjacent entries with same text
  const deduped = [];
  for (let i = 0; i < entries.length; i++) {
    if (i === 0 || entries[i].text !== entries[i - 1].text) {
      deduped.push(entries[i]);
    }
  }

  return deduped;
}

/**
 * Sanitize lyric text: replace control chars and non-renderable glyphs
 * with spaces so we never show tofu (□) or ? as placeholders.
 */
function sanitizeText(text) {
  if (!text) return text;
  let result = '';
  for (let i = 0; i < text.length; i++) {
    const cp = text.codePointAt(i);
    // Skip surrogate pair trailing half so we don't double-process
    if (cp > 0xFFFF) i++;
    if (
      cp <= 0x08 ||                           // C0 controls (except \t=0x09, \n=0x0A, \r=0x0D)
      cp === 0x0B || cp === 0x0C ||           // VT, FF
      (cp >= 0x0E && cp <= 0x1F) ||           // rest of C0
      (cp >= 0x7F && cp <= 0x9F) ||           // DEL + C1 controls
      (cp >= 0x200B && cp <= 0x200F) ||       // zero-width space & joiners
      (cp >= 0x2028 && cp <= 0x202E) ||       // line/paragraph sep, bidi controls
      (cp >= 0x2060 && cp <= 0x206F) ||       // word joiner, invisible operators
      cp === 0xFEFF ||                        // BOM / zero-width no-break space
      cp === 0xFFFD                           // replacement character
    ) {
      result += ' ';
    } else {
      result += text[i];
    }
  }
  return result;
}

function formatTime(seconds) {
  if (!seconds || !isFinite(seconds)) return '0:00';
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, '0')}`;
}

export default function LyricsDisplay({ lrcContent, currentTime = 0, isPlaying, onUpload, onRemove }) {
  const lyrics = useMemo(() => parseLRC(lrcContent), [lrcContent]);
  const listRef = useRef(null);
  const prevActiveRef = useRef(-1);

  // Find active line index
  const activeIndex = useMemo(() => {
    if (!lyrics.length) return -1;
    // Find the last line whose time <= currentTime
    let idx = -1;
    for (let i = 0; i < lyrics.length; i++) {
      if (lyrics[i].time <= currentTime) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }, [lyrics, currentTime]);

  // Auto-scroll active line into view (centered)
  useEffect(() => {
    if (activeIndex !== prevActiveRef.current && listRef.current) {
      const activeEl = listRef.current.querySelector('.lyrics-line--active');
      if (activeEl) {
        activeEl.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }
      prevActiveRef.current = activeIndex;
    }
  }, [activeIndex]);

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
            Upload an <code>.lrc</code> file to see time-synced lyrics
          </p>
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
              <span className="lyrics-text">{sanitizeText(entry.text)}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}
