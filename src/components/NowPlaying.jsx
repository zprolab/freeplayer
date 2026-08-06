import React, { useState, useEffect, useCallback } from 'react';
import WaveformVisualizer from './WaveformVisualizer';
import LyricsDisplay from './LyricsDisplay';
import ImmersiveMode from './ImmersiveMode';
import { getCachedCover, setCachedCover } from '../coverCache';

function formatTime(seconds) {
  if (!seconds || !isFinite(seconds)) return '0:00';
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, '0')}`;
}

export default function NowPlaying({
  currentTrack, isPlaying, currentTime, duration,
  onSeek, onTogglePlay, onNext, onPrev,
  queue, queueIndex, onPlayFromQueue,
  audioElement,
  visualizerMode, onVisualizerModeChange,
}) {
  const [coverUrl, setCoverUrl] = useState(null);
  const [lrcContent, setLrcContent] = useState(null);
  const [lrcPath, setLrcPath] = useState(null);
  const [isImmersive, setIsImmersive] = useState(false);
  const [tab, setTab] = useState('overview');
  const [queueOpen, setQueueOpen] = useState(false);

  useEffect(() => {
    let stale = false;
    if (currentTrack && currentTrack.cover_path) {
      const cached = getCachedCover(currentTrack.cover_path);
      if (cached) {
        setCoverUrl(cached);
        return;
      }
      window.freeplayer.getCover(currentTrack.cover_path).then((url) => {
        if (!stale && url) {
          setCachedCover(currentTrack.cover_path, url);
          setCoverUrl(url);
        }
      });
    } else {
      setCoverUrl(null);
    }
    return () => { stale = true; };
  }, [currentTrack]);

  // Fetch LRC lyrics when track changes
  useEffect(() => {
    let stale = false;
    if (currentTrack?.id) {
      window.freeplayer.getLrc(currentTrack.id).then((result) => {
        if (!stale) {
          if (result && result.content) {
            setLrcContent(result.content);
            setLrcPath(result.path);
          } else {
            setLrcContent(null);
            setLrcPath(null);
          }
        }
      }).catch(() => {
        if (!stale) {
          setLrcContent(null);
          setLrcPath(null);
        }
      });
    } else {
      setLrcContent(null);
      setLrcPath(null);
    }
    return () => { stale = true; };
  }, [currentTrack]);

  const handleUploadLrc = useCallback(async () => {
    if (!currentTrack?.id) return;
    const result = await window.freeplayer.uploadLrc(currentTrack.id);
    if (result && result.success) {
      const lrcResult = await window.freeplayer.getLrc(currentTrack.id);
      if (lrcResult && lrcResult.content) {
        setLrcContent(lrcResult.content);
        setLrcPath(lrcResult.path);
      }
    }
  }, [currentTrack]);

  const handleRemoveLrc = useCallback(async () => {
    if (!currentTrack?.id) return;
    await window.freeplayer.removeLrc(currentTrack.id);
    setLrcContent(null);
    setLrcPath(null);
  }, [currentTrack]);

  if (!currentTrack) {
    return (
      <div className="empty-state">
        <div className="empty-state-icon">
          <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.2">
            <circle cx="12" cy="12" r="10"/>
            <polygon points="10 8 16 12 10 16 10 8" fill="currentColor" stroke="none"/>
          </svg>
        </div>
        <h3>Nothing playing</h3>
        <p>Select a track from your library to start listening.</p>
      </div>
    );
  }

  const specRows = [];
  if (currentTrack.file_format) specRows.push(['Format', currentTrack.file_format.toUpperCase()]);
  if (currentTrack.bitrate) specRows.push(['Bitrate', `${currentTrack.bitrate} kbps`]);
  if (currentTrack.sample_rate) specRows.push(['Sample', `${(currentTrack.sample_rate / 1000).toFixed(1)} kHz`]);
  if (currentTrack.year) specRows.push(['Year', currentTrack.year]);
  if (currentTrack.genre) specRows.push(['Genre', currentTrack.genre]);

  const lyrics = (
    <LyricsDisplay
      lrcContent={lrcContent}
      currentTime={currentTime}
      isPlaying={isPlaying}
      onUpload={handleUploadLrc}
      onImmersive={() => setIsImmersive(true)}
      onRemove={handleRemoveLrc}
      autoScroll
    />
  );

  return (
    <div className="now-playing">
      {/* View tabs */}
      <div className="np-tabs" role="tablist">
        <button
          className={`np-tab-btn ${tab === 'overview' ? 'np-tab-btn--active' : ''}`}
          onClick={() => setTab('overview')}
        >
          Overview
        </button>
        <button
          className={`np-tab-btn ${tab === 'lyrics' ? 'np-tab-btn--active' : ''}`}
          onClick={() => setTab('lyrics')}
        >
          Lyrics
        </button>
        <button
          className={`np-tab-btn ${tab === 'scope' ? 'np-tab-btn--active' : ''}`}
          onClick={() => setTab('scope')}
        >
          Scope
        </button>
      </div>

      {/* ── Overview: cover + track sheet (left) / lyrics (right) ── */}
      {tab === 'overview' && (
        <div className="np-overview">
          <div className="np-left">
            <div className="np-cover">
              {coverUrl ? (
                <img src={coverUrl} alt="" className="np-cover-img" />
              ) : (
                <div className="np-cover-placeholder">
                  <svg width="56" height="56" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1">
                    <path d="M9 18V5l12-2v13"/>
                    <circle cx="6" cy="18" r="3"/>
                    <circle cx="18" cy="16" r="3"/>
                  </svg>
                </div>
              )}
            </div>

            <div className="np-info">
              <h2 className="np-title">{currentTrack.title}</h2>
              <p className="np-artist">{currentTrack.artist}</p>
              {currentTrack.album !== 'Unknown Album' && (
                <p className="np-album">{currentTrack.album}</p>
              )}
              {specRows.length > 0 && (
                <dl className="np-spec">
                  {specRows.map(([label, value]) => (
                    <React.Fragment key={label}>
                      <dt className="np-spec-label">{label}</dt>
                      <dd className="np-spec-value">{value}</dd>
                    </React.Fragment>
                  ))}
                </dl>
              )}
            </div>
          </div>

          <div className="np-lyrics-pane">{lyrics}</div>
        </div>
      )}

      {/* ── Full lyrics ── */}
      {tab === 'lyrics' && (
        <div className="np-lyrics-tab">{lyrics}</div>
      )}

      {/* ── Scope: full-size visualizer ── */}
      {tab === 'scope' && (
        <div className="np-scope">
          <div className="np-scope-track mono">
            <span className="np-scope-label">MONITORING</span>
            <span className="np-scope-sep">·</span>
            <span className="np-scope-title">{currentTrack.title}</span>
            <span className="np-scope-sep">—</span>
            <span className="np-scope-artist">{currentTrack.artist}</span>
            {currentTrack.file_format && (
              <span className="np-scope-format">{currentTrack.file_format.toUpperCase()}</span>
            )}
          </div>
          <WaveformVisualizer
            audioElement={audioElement}
            isPlaying={isPlaying}
            trackId={currentTrack?.id}
            mode={visualizerMode}
            onModeChange={onVisualizerModeChange}
          />
        </div>
      )}

      {/* ── Queue (overview only, collapsible) ── */}
      {tab === 'overview' && queue.length > 1 && (
        <div className="np-queue">
          <button className="np-queue-toggle" onClick={() => setQueueOpen((o) => !o)}>
            <h3 className="np-section-title">Queue</h3>
            <span className="np-queue-count mono">{queue.length}</span>
            <svg
              className={`np-queue-chevron ${queueOpen ? 'np-queue-chevron--open' : ''}`}
              width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor"
              strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"
            >
              <polyline points="6 9 12 15 18 9"/>
            </svg>
          </button>
          {queueOpen && (
            <div className="queue-list">
              {queue.map((track, idx) => (
                <button
                  key={`${track.id}-${idx}`}
                  className={`queue-item ${idx === queueIndex ? 'queue-item--active' : ''} ${idx < queueIndex ? 'queue-item--played' : ''}`}
                  onClick={() => onPlayFromQueue(track, queue)}
                >
                  <span className="queue-idx mono">
                    {idx === queueIndex && isPlaying ? (
                      <span className="playing-indicator">
                        <span className="eq-bar" />
                        <span className="eq-bar" />
                        <span className="eq-bar" />
                      </span>
                    ) : (
                      idx + 1
                    )}
                  </span>
                  <span className="queue-title">{track.title}</span>
                  <span className="queue-artist">{track.artist}</span>
                  <span className="queue-duration mono">{formatTime(track.duration)}</span>
                </button>
              ))}
            </div>
          )}
        </div>
      )}

      {/* Immersive Mode Overlay */}
      {isImmersive && (
        <ImmersiveMode
          track={currentTrack}
          lrcContent={lrcContent}
          currentTime={currentTime}
          duration={duration}
          coverUrl={coverUrl}
          isPlaying={isPlaying}
          onSeek={onSeek}
          onTogglePlay={onTogglePlay}
          onNext={onNext}
          onPrev={onPrev}
          onClose={() => setIsImmersive(false)}
        />
      )}
    </div>
  );
}
