import React, { useState, useEffect } from 'react';
import WaveformVisualizer from './WaveformVisualizer';

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
  playMode, onPlayModeChange,
}) {
  const [coverUrl, setCoverUrl] = useState(null);

  useEffect(() => {
    let stale = false;
    if (currentTrack && currentTrack.cover_path) {
      window.freeplayer.getCover(currentTrack.cover_path).then((url) => {
        if (!stale && url) setCoverUrl(url);
      });
    } else {
      setCoverUrl(null);
    }
    return () => { stale = true; };
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

  const progress = duration > 0 ? (currentTime / duration) * 100 : 0;

  return (
    <div className="now-playing">
      {/* Waveform Visualizer — hero element */}
      <WaveformVisualizer
        audioElement={audioElement}
        isPlaying={isPlaying}
        trackId={currentTrack?.id}
        mode={visualizerMode}
        onModeChange={onVisualizerModeChange}
      />

      {/* Track info + cover */}
      <div className="np-hero">
        <div className={`np-cover ${isPlaying ? 'np-cover--spinning' : ''}`}>
          {coverUrl ? (
            <img src={coverUrl} alt="" className="np-cover-img" />
          ) : (
            <div className="np-cover-placeholder">
              <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1">
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
          <div className="np-meta-tags">
            {currentTrack.year && <span className="meta-tag">{currentTrack.year}</span>}
            {currentTrack.genre && <span className="meta-tag">{currentTrack.genre}</span>}
            <span className="meta-tag">{currentTrack.file_format?.toUpperCase()}</span>
            {currentTrack.bitrate && <span className="meta-tag">{currentTrack.bitrate} kbps</span>}
            {currentTrack.sample_rate && (
              <span className="meta-tag">{((currentTrack.sample_rate) / 1000).toFixed(1)} kHz</span>
            )}
          </div>
        </div>
      </div>

      {/* Progress */}
      <div className="np-progress-section">
        <div className="np-progress-bar" onClick={(e) => {
          const rect = e.currentTarget.getBoundingClientRect();
          onSeek((e.clientX - rect.left) / rect.width * duration);
        }}>
          <div className="np-progress-fill" style={{ width: `${progress}%` }} />
        </div>
        <div className="np-time-row mono">
          <span>{formatTime(currentTime)}</span>
          <span>{formatTime(duration)}</span>
        </div>
      </div>

      {/* Controls */}
      <div className="np-controls">
        <button className="np-ctrl-btn" onClick={onPrev}>
          <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor">
            <polygon points="19,20 9,12 19,4 19,20"/>
            <rect x="4" y="4" width="3" height="16"/>
          </svg>
        </button>
        <button className="np-ctrl-btn np-ctrl-btn--play" onClick={onTogglePlay}>
          {isPlaying ? (
            <svg width="32" height="32" viewBox="0 0 24 24" fill="currentColor">
              <rect x="5" y="3" width="5" height="18" rx="1.5"/>
              <rect x="14" y="3" width="5" height="18" rx="1.5"/>
            </svg>
          ) : (
            <svg width="32" height="32" viewBox="0 0 24 24" fill="currentColor">
              <polygon points="6,3 20,12 6,21"/>
            </svg>
          )}
        </button>
        <button className="np-ctrl-btn" onClick={onNext}>
          <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor">
            <polygon points="5,4 15,12 5,20 5,4"/>
            <rect x="17" y="4" width="3" height="16"/>
          </svg>
        </button>
      </div>

      {/* Play Mode */}
      <div className="np-play-mode">
        <div className="np-play-mode-group">
          <button
            className={`np-play-mode-btn ${playMode === 'sequential' ? 'np-play-mode-btn--active' : ''}`}
            onClick={() => onPlayModeChange('sequential')}
          >
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <polyline points="1 4 1 10 7 10"/>
              <path d="M3.51 15a9 9 0 1 0 2.13-9.36L1 10"/>
            </svg>
            List Loop
          </button>
          <button
            className={`np-play-mode-btn ${playMode === 'repeat-one' ? 'np-play-mode-btn--active' : ''}`}
            onClick={() => onPlayModeChange('repeat-one')}
          >
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <polyline points="1 4 1 10 7 10"/>
              <path d="M3.51 15a9 9 0 1 0 2.13-9.36L1 10"/>
              <path d="M13 15v-4l-1.5 1.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
            </svg>
            Repeat One
          </button>
          <button
            className={`np-play-mode-btn ${playMode === 'shuffle' ? 'np-play-mode-btn--active' : ''}`}
            onClick={() => onPlayModeChange('shuffle')}
          >
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <polyline points="16 3 21 3 21 8"/>
              <line x1="4" y1="20" x2="21" y2="3"/>
              <polyline points="21 16 21 21 16 21"/>
              <line x1="15" y1="15" x2="21" y2="21"/>
              <line x1="4" y1="4" x2="9" y2="9"/>
            </svg>
            Shuffle
          </button>
        </div>
      </div>

      {/* Queue */}
      {queue.length > 1 && (
        <div className="np-queue">
          <h3 className="np-section-title">Queue</h3>
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
        </div>
      )}
    </div>
  );
}
