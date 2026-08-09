import { useState, useEffect } from 'react';
import { fetchLyricsForTrack, fetchCoverForTrack } from '../services/metaFetch';

let batchRunning = false;

export default function Settings({
  importMode,
  onImportModeChange,
  libraryDir,
  onLibraryDirChange,
  defaultVolume,
  onDefaultVolumeChange,
  defaultVisualizer,
  onDefaultVisualizerChange,
  autoFetchMeta, onAutoFetchMetaChange, tracks,
  onResetDatabase,
}) {
  const [showResetConfirm, setShowResetConfirm] = useState(false);
  const [batchProgress, setBatchProgress] = useState(null); // { done, total, ok, fail, noMatch }
  const [batchActive, setBatchActive] = useState(batchRunning);
  const [trayEnabled, setTrayEnabled] = useState(true); // default true
  const [trayNotify, setTrayNotify] = useState(true);
  const [startOnBoot, setStartOnBoot] = useState(false);

  const coerceBool = (val) => {
    if (val === true || val === 1) return true;
    if (val === false || val === 0 || val == null) return false;
    if (typeof val === 'string') {
      const s = val.toLowerCase();
      return s === 'true' || s === '1' || s === '1.0' || s === 'yes' || s === 'on';
    }
    return false;
  };

  useEffect(() => {
    window.freeplayer.getSetting('tray_enabled').then(val => {
      setTrayEnabled(coerceBool(val));
    }).catch(() => {});
    window.freeplayer.getSetting('tray_notify').then(val => {
      setTrayNotify(coerceBool(val));
    }).catch(() => {});
    window.freeplayer.getLoginItemSettings().then(settings => {
      setStartOnBoot(settings.openAtLogin);
    }).catch(() => {});
  }, []);

  const handleChangeLibraryDir = async () => {
    const result = await window.freeplayer.selectLibraryDir();
    if (!result.canceled) {
      await window.freeplayer.setSetting({ key: 'library_dir', value: result.path });
      onLibraryDirChange(result.path);
    }
  };

  const handleReset = async () => {
    await window.freeplayer.resetDatabase();
    setShowResetConfirm(false);
    onResetDatabase();
  };

  const handleFetchMissing = async () => {
    if (batchRunning) return;
    const total = tracks?.length || 0;
    if (!total) return;
    batchRunning = true;
    setBatchActive(true);
    let ok = 0;
    let fail = 0;
    let noMatch = 0;
    let done = 0;
    setBatchProgress({ done: 0, total, ok: 0, fail: 0, noMatch: 0 });
    const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
    // ~1.5s/track keeps both APIs (LRCLIB ~50/min, iTunes ~20/min) under
    // their rate limits; the services' own pacing + 429/403 cooldowns also
    // apply on top of this.
    for (const t of tracks) {
      let saved = false;
      let threw = false;
      let hadMissing = false;
      try {
        const coverMissing = !t.cover_path
          || !(await window.freeplayer.getCover(t.cover_path).catch(() => null));
        if (coverMissing) {
          hadMissing = true;
          const cover = await fetchCoverForTrack(t);
          if (cover) {
            const res = await window.freeplayer.saveCover(t.id, cover);
            if (res && res.success) { ok++; saved = true; }
          }
        }
        const lrc = await window.freeplayer.getLrc(t.id);
        if (!lrc || !lrc.content) {
          hadMissing = true;
          const lyrics = await fetchLyricsForTrack(t);
          if (lyrics) {
            const res = await window.freeplayer.saveLrcContent(t.id, lyrics);
            if (res && res.success) { ok++; saved = true; }
          }
        }
      } catch {
        threw = true;
      }
      // noMatch only counts when something WAS missing but nothing got saved
      // (complete tracks must not inflate the bucket)
      if (threw) fail++;
      else if (hadMissing && !saved) noMatch++;
      done++;
      setBatchProgress({ done, total, ok, fail, noMatch });
      await sleep(1500);
    }
    batchRunning = false;
    setBatchActive(false);
    setBatchProgress(null);
  };

  return (
    <div className="settings">
      {/* Import Mode */}
      <div className="settings-section">
        <div className="section-header">
          <h3 className="section-title">Import Mode</h3>
          <p className="section-desc">
            Choose how files are added to your library when importing music.
          </p>
        </div>

        <div className="import-mode-options">
          <button
            className={`import-mode-card ${importMode === 'copy' ? 'import-mode-card--selected' : ''}`}
            onClick={() => onImportModeChange('copy')}
          >
            <div className="import-mode-radio">
              <div className="import-mode-radio-dot" />
            </div>
            <div>
              <div className="import-mode-label">Copy Files</div>
              <div className="import-mode-hint">Duplicate files into library directory</div>
            </div>
          </button>

          <button
            className={`import-mode-card ${importMode === 'symlink' ? 'import-mode-card--selected' : ''}`}
            onClick={() => onImportModeChange('symlink')}
          >
            <div className="import-mode-radio">
              <div className="import-mode-radio-dot" />
            </div>
            <div>
              <div className="import-mode-label">Symlink</div>
              <div className="import-mode-hint">Create symbolic links (saves disk space)</div>
            </div>
          </button>
        </div>
      </div>

      {/* Library Directory */}
      <div className="settings-section">
        <div className="section-header">
          <h3 className="section-title">Library Directory</h3>
          <p className="section-desc">
            Where your organized music files and symlinks are stored.
          </p>
        </div>

        <div className="library-dir-display">
          <svg className="library-dir-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
            <path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/>
          </svg>
          {libraryDir ? (
            <span className="library-dir-path">{libraryDir}</span>
          ) : (
            <span className="library-dir-empty">No library directory set</span>
          )}
          <button className="btn btn-secondary" onClick={handleChangeLibraryDir} style={{ flexShrink: 0 }}>
            Change...
          </button>
        </div>
      </div>

      {/* Playback */}
      <div className="settings-section">
        <div className="section-header">
          <h3 className="section-title">Playback</h3>
          <p className="section-desc">Default playback preferences.</p>
        </div>

        <div className="playback-row">
          <div className="playback-label-group">
            <span className="playback-label">Default Volume</span>
            <span className="playback-hint">Set the starting volume for playback</span>
          </div>
          <div className="volume-setting">
            <input
              type="range"
              min="0"
              max="100"
              value={Math.round(defaultVolume * 100)}
              onChange={(e) => onDefaultVolumeChange(Number(e.target.value) / 100)}
            />
            <span className="volume-value">{Math.round(defaultVolume * 100)}%</span>
          </div>
        </div>

        <div className="playback-row">
          <div className="playback-label-group">
            <span className="playback-label">Default Visualizer</span>
            <span className="playback-hint">Visualization shown on Now Playing view</span>
          </div>
          <div className="vis-mode-group--settings">
            {['waveform', 'spectrogram', 'off'].map((mode) => (
              <button
                key={mode}
                className={`vis-mode-btn--settings ${defaultVisualizer === mode ? 'vis-mode-btn--settings--active' : ''}`}
                onClick={() => onDefaultVisualizerChange(mode)}
              >
                {mode === 'waveform' ? 'Waveform' : mode === 'spectrogram' ? 'Spectrogram' : 'Off'}
              </button>
            ))}
          </div>
        </div>

        <div className="playback-row">
          <div className="playback-label-group">
            <span className="playback-label">Auto-Fetch Lyrics & Covers</span>
            <span className="playback-hint">Automatically download missing lyrics (LRCLIB) and album art (iTunes) when playing a track</span>
          </div>
          <label className="toggle-switch">
            <input
              type="checkbox"
              checked={autoFetchMeta}
              onChange={(e) => onAutoFetchMetaChange(e.target.checked)}
            />
            <span className="toggle-slider" />
          </label>
        </div>

        <div className="playback-row">
          <div className="playback-label-group">
            <span className="playback-label">Backfill Missing Metadata</span>
            <span className="playback-hint">
              {batchProgress
                ? `Fetching ${batchProgress.done}/${batchProgress.total} · ${batchProgress.ok} saved${batchProgress.fail ? ` · ${batchProgress.fail} failed` : ''}${batchProgress.noMatch ? ` · ${batchProgress.noMatch} no match` : ''}`
                : batchActive
                  ? 'A metadata fetch is already running…'
                  : `Fetch lyrics and covers for ${tracks?.length || 0} tracks that are missing them`}
            </span>
          </div>
          <button
            className="btn"
            disabled={!!batchProgress || batchActive}
            onClick={handleFetchMissing}
          >
            {batchProgress || batchActive ? 'Fetching…' : 'Fetch Missing'}
          </button>
        </div>

        <div className="playback-row">
          <div className="playback-label-group">
            <span className="playback-label">Close to Tray</span>
            <span className="playback-hint">Minimize to system tray instead of quitting when closing the window</span>
          </div>
          <label className="toggle-switch">
            <input
              type="checkbox"
              checked={trayEnabled}
              onChange={(e) => {
                const val = e.target.checked;
                setTrayEnabled(val);
                window.freeplayer.setSetting({ key: 'tray_enabled', value: val });
              }}
            />
            <span className="toggle-slider" />
          </label>
        </div>

        {trayEnabled && (
          <>
            <div className="playback-row">
              <div className="playback-label-group">
                <span className="playback-label">Tray Notification</span>
                <span className="playback-hint">Show a notification when the app is minimized to the system tray</span>
              </div>
              <label className="toggle-switch">
                <input
                  type="checkbox"
                  checked={trayNotify}
                  onChange={(e) => {
                    const val = e.target.checked;
                    setTrayNotify(val);
                    window.freeplayer.setSetting({ key: 'tray_notify', value: val });
                  }}
                />
                <span className="toggle-slider" />
              </label>
            </div>

            <div className="playback-row">
              <div className="playback-label-group">
                <span className="playback-label">Launch at Login</span>
                <span className="playback-hint">Automatically start FreePlayer when you log in</span>
              </div>
              <label className="toggle-switch">
                <input
                  type="checkbox"
                  checked={startOnBoot}
                  onChange={(e) => {
                    const val = e.target.checked;
                    setStartOnBoot(val);
                    window.freeplayer.setSetting({ key: 'start_on_boot', value: val });
                    window.freeplayer.setLoginItemSettings({ openAtLogin: val, openAsHidden: true });
                  }}
                />
                <span className="toggle-slider" />
              </label>
            </div>
          </>
        )}
      </div>

      {/* Danger Zone */}
      <div className="settings-section settings-section--danger">
        <div className="section-header">
          <h3 className="section-title section-title--danger">Danger Zone</h3>
          <p className="section-desc">Irreversible actions. Proceed with caution.</p>
        </div>

        <div className="danger-row">
          <div className="danger-info">
            <span className="danger-label">Reset Database</span>
            <span className="danger-hint">
              Remove all tracks, play history, and playlists. Files on disk are not affected.
            </span>
          </div>
          <button className="btn-danger" onClick={() => setShowResetConfirm(true)}>
            Reset...
          </button>
        </div>
      </div>

      {/* Reset Confirmation Dialog */}
      {showResetConfirm && (
        <div className="confirm-overlay" onClick={() => setShowResetConfirm(false)}>
          <div className="confirm-dialog" onClick={(e) => e.stopPropagation()}>
            <h3 className="confirm-title">Reset Database</h3>
            <p className="confirm-message">
              This will permanently delete all tracks, play history, playlists, and settings from the database.
              Your music files on disk will not be touched.
              <br /><br />
              This action cannot be undone.
            </p>
            <div className="confirm-actions">
              <button className="btn btn-secondary" onClick={() => setShowResetConfirm(false)}>
                Cancel
              </button>
              <button className="btn btn-primary" onClick={handleReset}>
                Reset Everything
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
