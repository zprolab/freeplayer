import { useState, useEffect, useCallback, Fragment } from 'react';
import WaveformVisualizer from './WaveformVisualizer';
import LyricsDisplay from './LyricsDisplay';
import ImmersiveMode from './ImmersiveMode';
import CoverArt from './CoverArt';
import { formatTime } from '../utils/format';
import { useCoverArt } from '../hooks/useCoverArt';
import { sourceLabel, sourceKind } from '../utils/provenance';
import { fetchAndSaveLyrics, fetchAndSaveCover } from '../services/metaPersistence';

export default function NowPlaying({
  currentTrack, isPlaying, currentTime, duration,
  onSeek, onTogglePlay, onNext, onPrev,
  queue, queueIndex, onPlayFromQueue,
  audioElement,
  visualizerMode, onVisualizerModeChange,
  onCoverSaved,
  onTrackReset,
  meta,
}) {
  const [lrcContent, setLrcContent] = useState(null);
  const [lrcSource, setLrcSource] = useState(null);
  const [isImmersive, setIsImmersive] = useState(false);
  const [tab, setTab] = useState('overview');
  const [queueOpen, setQueueOpen] = useState(false);
  const [fetchingLyrics, setFetchingLyrics] = useState(false);
  const [lyricsFailReason, setLyricsFailReason] = useState(null);
  const [fetchingCover, setFetchingCover] = useState(false);
  const [coverFailReason, setCoverFailReason] = useState(null);
  const [resetting, setResetting] = useState(false);
  const [resetError, setResetError] = useState(null);

  const coverUrl = useCoverArt(currentTrack);

  // Fetch LRC lyrics when track changes
  useEffect(() => {
    let stale = false;
    if (currentTrack?.id) {
      window.freeplayer.getLrc(currentTrack.id).then((result) => {
        if (!stale) {
          const content = result && result.content ? result.content : null;
          setLrcContent(content);
          setLrcSource(content ? (result.source || null) : null);
        }
      }).catch((err) => {
        console.warn('Failed to load lyrics:', err);
        if (!stale) {
          setLrcContent(null);
          setLrcSource(null);
        }
      });
    } else {
      setLrcContent(null);
      setLrcSource(null);
    }
    setLyricsFailReason(null);
    setCoverFailReason(null);
    setResetError(null);
    return () => { stale = true; };
  }, [currentTrack]);

  const handleUploadLrc = useCallback(async () => {
    if (!currentTrack?.id) return;
    const result = await window.freeplayer.uploadLrc(currentTrack.id);
    if (result && result.success) {
      const lrcResult = await window.freeplayer.getLrc(currentTrack.id);
      if (lrcResult && lrcResult.content) {
        setLrcContent(lrcResult.content);
        setLrcSource(lrcResult.source || 'sidecar');
      }
    }
  }, [currentTrack]);

  const handleRemoveLrc = useCallback(async () => {
    if (!currentTrack?.id) return;
    await window.freeplayer.removeLrc(currentTrack.id);
    setLrcContent(null);
    setLrcSource(null);
  }, [currentTrack]);

  const handleFetchLyrics = useCallback(async () => {
    if (!currentTrack?.id || fetchingLyrics) return;
    setFetchingLyrics(true);
    setLyricsFailReason(null);
    // try/finally: a rejected native save/getSetting would otherwise skip the
    // reset and leave the button stuck disabled on "Fetching…" forever.
    try {
      const { saved, reason } = await fetchAndSaveLyrics(currentTrack, meta);
      if (saved) {
        const lrcResult = await window.freeplayer.getLrc(currentTrack.id);
        if (lrcResult && lrcResult.content) {
          setLrcContent(lrcResult.content);
          setLrcSource(lrcResult.source || 'plugin');
        }
      } else {
        setLyricsFailReason(reason || 'not-found');
      }
    } catch (err) {
      setLyricsFailReason(err?.message || 'error');
    } finally {
      setFetchingLyrics(false);
    }
  }, [currentTrack, fetchingLyrics, meta]);

  const handleFetchCover = useCallback(async () => {
    if (!currentTrack?.id || fetchingCover) return;
    setFetchingCover(true);
    setCoverFailReason(null);
    try {
      const { saved, coverPath, reason } = await fetchAndSaveCover(currentTrack, meta);
      if (saved && coverPath) {
        onCoverSaved(coverPath);
      } else {
        setCoverFailReason(reason || 'not-found');
      }
    } catch (err) {
      setCoverFailReason(err?.message || 'error');
    } finally {
      setFetchingCover(false);
    }
  }, [currentTrack, fetchingCover, onCoverSaved, meta]);

  // Make the audio file's own metadata the baseline again: embedded tags,
  // artwork and lyrics replace whatever an online backend or an earlier edit
  // left behind. The row is refreshed from the shell afterwards.
  const handleResetFromFile = useCallback(async () => {
    if (!currentTrack?.id || resetting) return;
    setResetting(true);
    setResetError(null);
    try {
      const result = await window.freeplayer.resetTrackFromFile(currentTrack.id);
      if (!result || result.success === false) {
        setResetError(result?.error || 'reset failed');
        return;
      }
      const fresh = await window.freeplayer.getTrack(currentTrack.id).catch(() => null);
      if (fresh && onTrackReset) onTrackReset(fresh);
      const lrcResult = await window.freeplayer.getLrc(currentTrack.id).catch(() => null);
      setLrcContent(lrcResult && lrcResult.content ? lrcResult.content : null);
      setLrcSource(lrcResult && lrcResult.content ? (lrcResult.source || null) : null);
    } catch (err) {
      setResetError(err?.message || 'error');
    } finally {
      setResetting(false);
    }
  }, [currentTrack, resetting, onTrackReset]);

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

  // Only the values whose provenance the shell actually recorded (rows
  // imported before the columns existed have none yet).
  const provenanceItems = [
    ['Tags', currentTrack.meta_source],
    ['Cover', currentTrack.cover_source],
    ['Lyrics', lrcSource],
  ].filter(([, source]) => !!source);

  const lyrics = (
    <LyricsDisplay
      lrcContent={lrcContent}
      currentTime={currentTime}
      onUpload={handleUploadLrc}
      onFetchLyrics={handleFetchLyrics}
      fetchingLyrics={fetchingLyrics}
      lyricsFailReason={lyricsFailReason}
      onImmersive={() => setIsImmersive(true)}
      onRemove={handleRemoveLrc}
      lyricsSource={lrcSource}
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
              <CoverArt
                track={currentTrack}
                variant="np"
                onFetchCover={handleFetchCover}
                fetchingCover={fetchingCover}
                coverFailReason={coverFailReason}
              />
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
                    <Fragment key={label}>
                      <dt className="np-spec-label">{label}</dt>
                      <dd className="np-spec-value">{value}</dd>
                    </Fragment>
                  ))}
                </dl>
              )}

              {/* Provenance of each value: the audio file itself is the
                  baseline, online backends and manual edits are labelled so
                  the user can see (and undo) a fill-in. */}
              <div className="np-baseline">
                {provenanceItems.length > 0 && (
                  <div className="np-baseline-sources">
                    {provenanceItems.map(([label, source]) => (
                      <span className="np-baseline-item" key={label}>
                        <span className="np-baseline-label">{label}</span>
                        <span className={`np-source np-source--${sourceKind(source)}`}>
                          {sourceLabel(source)}
                        </span>
                      </span>
                    ))}
                  </div>
                )}
                <button
                  className="np-reset-btn"
                  onClick={handleResetFromFile}
                  disabled={resetting}
                  title="Re-read the tags, artwork and lyrics embedded in the audio file"
                >
                  {resetting ? 'Resetting…' : 'Reset from file'}
                </button>
                {resetError && <span className="np-reset-error">{resetError}</span>}
              </div>
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
              strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"
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
