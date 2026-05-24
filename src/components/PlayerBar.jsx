import React from 'react';

function formatTime(seconds) {
  if (!seconds || !isFinite(seconds)) return '0:00';
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, '0')}`;
}

export default function PlayerBar({
  currentTrack, isPlaying, currentTime, duration,
  onTogglePlay, onNext, onPrev, onSeek, volume, onVolumeChange,
  playMode, onPlayModeChange,
}) {
  const progress = duration > 0 ? (currentTime / duration) * 100 : 0;

  const handleProgressClick = (e) => {
    const rect = e.currentTarget.getBoundingClientRect();
    const ratio = (e.clientX - rect.left) / rect.width;
    onSeek(ratio * duration);
  };

  return (
    <footer className={`player-bar ${currentTrack ? 'player-bar--active' : ''}`}>
      {/* Progress bar thin line at top of player */}
      <div className="player-progress-track" onClick={handleProgressClick}>
        <div className="player-progress-fill" style={{ width: `${progress}%` }} />
        <div className="player-progress-thumb" style={{ left: `${progress}%` }} />
      </div>

      <div className="player-inner">
        {/* Track info */}
        <div className="player-track-info">
          {currentTrack ? (
            <>
              <div className="player-cover">
                <CoverArt track={currentTrack} />
              </div>
              <div className="player-meta">
                <span className="player-title">{currentTrack.title}</span>
                <span className="player-artist">{currentTrack.artist}</span>
              </div>
            </>
          ) : (
            <div className="player-meta">
              <span className="player-title player-title--empty">No track selected</span>
              <span className="player-artist">Select a track from your library</span>
            </div>
          )}
        </div>

        {/* Controls */}
        <div className="player-controls">
          <button className="ctrl-btn" onClick={onPrev} title="Previous">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
              <polygon points="19,20 9,12 19,4 19,20"/>
              <rect x="4" y="4" width="3" height="16"/>
            </svg>
          </button>
          <button className="ctrl-btn ctrl-btn--play" onClick={onTogglePlay} title={isPlaying ? 'Pause' : 'Play'}>
            {isPlaying ? (
              <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
                <rect x="5" y="3" width="5" height="18" rx="1"/>
                <rect x="14" y="3" width="5" height="18" rx="1"/>
              </svg>
            ) : (
              <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
                <polygon points="6,3 20,12 6,21"/>
              </svg>
            )}
          </button>
          <button className="ctrl-btn" onClick={onNext} title="Next">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
              <polygon points="5,4 15,12 5,20 5,4"/>
              <rect x="17" y="4" width="3" height="16"/>
            </svg>
          </button>
        </div>

        {/* Time & Volume */}
        <div className="player-extras">
          <div className="play-mode-btns">
            <button
              className={`play-mode-btn ${playMode === 'sequential' ? 'play-mode-btn--active' : ''}`}
              onClick={() => onPlayModeChange('sequential')}
              title="List Loop"
            >
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="1 4 1 10 7 10"/>
                <path d="M3.51 15a9 9 0 1 0 2.13-9.36L1 10"/>
              </svg>
            </button>
            <button
              className={`play-mode-btn ${playMode === 'repeat-one' ? 'play-mode-btn--active' : ''}`}
              onClick={() => onPlayModeChange('repeat-one')}
              title="Repeat One"
            >
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="1 4 1 10 7 10"/>
                <path d="M3.51 15a9 9 0 1 0 2.13-9.36L1 10"/>
                <path d="M13 15v-4l-1.5 1.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
              </svg>
            </button>
            <button
              className={`play-mode-btn ${playMode === 'shuffle' ? 'play-mode-btn--active' : ''}`}
              onClick={() => onPlayModeChange('shuffle')}
              title="Shuffle"
            >
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="16 3 21 3 21 8"/>
                <line x1="4" y1="20" x2="21" y2="3"/>
                <polyline points="21 16 21 21 16 21"/>
                <line x1="15" y1="15" x2="21" y2="21"/>
                <line x1="4" y1="4" x2="9" y2="9"/>
              </svg>
            </button>
          </div>
          <span className="player-time mono">
            {formatTime(currentTime)} / {formatTime(duration)}
          </span>
          <div className="volume-control">
            <svg className="volume-icon" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
              <polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/>
              {volume > 0 && <path d="M15.54 8.46a5 5 0 0 1 0 7.07"/>}
              {volume > 0.5 && <path d="M19.07 4.93a10 10 0 0 1 0 14.14"/>}
            </svg>
            <input
              type="range"
              min="0"
              max="1"
              step="0.01"
              value={volume}
              onChange={(e) => onVolumeChange(parseFloat(e.target.value))}
              className="volume-slider"
            />
          </div>
        </div>
      </div>
    </footer>
  );
}

function CoverArt({ track }) {
  const [coverUrl, setCoverUrl] = React.useState(null);

  React.useEffect(() => {
    let mounted = true;
    if (track && track.cover_path) {
      window.freeplayer.getCover(track.cover_path).then((url) => {
        if (mounted && url) setCoverUrl(url);
      });
    } else {
      setCoverUrl(null);
    }
    return () => { mounted = false; };
  }, [track]);

  if (coverUrl) {
    return <img src={coverUrl} alt="" className="cover-img" />;
  }

  return (
    <div className="cover-placeholder">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <path d="M9 18V5l12-2v13"/>
        <circle cx="6" cy="18" r="3"/>
        <circle cx="18" cy="16" r="3"/>
      </svg>
    </div>
  );
}
