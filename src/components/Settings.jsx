import { useState, useEffect, memo } from 'react';
import ToggleSwitch from './ToggleSwitch';
import SegmentedControl from './SegmentedControl';
import { useTraySettings } from '../hooks/useTraySettings';
import { applyMonoFont } from '../utils/fonts';
import logoUrl from '../../assets/logo.svg';
import licenseText from '../../LICENSE?raw';
import noticesText from '../../THIRD-PARTY-NOTICES.txt?raw';
import { version } from '../../package.json';

const MONO_FONTS = [
  { value: '', label: 'System default' },
  { value: 'JetBrains Mono', label: 'JetBrains Mono' },
  { value: 'Fira Code', label: 'Fira Code' },
  { value: 'SF Mono', label: 'SF Mono' },
  { value: 'Menlo', label: 'Menlo' },
  { value: 'Monaco', label: 'Monaco' },
  { value: 'Cascadia Code', label: 'Cascadia Code' },
  { value: 'Consolas', label: 'Consolas' },
];

const Settings = memo(function Settings({
  importMode,
  onImportModeChange,
  libraryDir,
  onLibraryDirChange,
  defaultVolume,
  onDefaultVolumeChange,
  defaultVisualizer,
  onDefaultVisualizerChange,
  onResetDatabase,
}) {
  const [showResetConfirm, setShowResetConfirm] = useState(false);
  const [monoFont, setMonoFont] = useState('');
  const [legalModal, setLegalModal] = useState(null); // 'license' | 'notices' | null
  const [legalText, setLegalText] = useState('');
  const {
    settingsLoaded,
    trayEnabled,
    trayNotify,
    startOnBoot,
    startHidden,
    settingsError,
    changeTrayEnabled,
    changeTrayNotify,
    changeStartOnBoot,
    changeStartHidden,
  } = useTraySettings();

  useEffect(() => {
    let cancelled = false;
    window.freeplayer.getSetting('mono_font')
      .then((v) => {
        if (cancelled) return;
        setMonoFont(typeof v === 'string' ? v : '');
      })
      .catch(() => {});
    return () => { cancelled = true; };
  }, []);

  const handleMonoFontChange = async (value) => {
    setMonoFont(value);
    applyMonoFont(value);
    await window.freeplayer.setSetting({ key: 'mono_font', value });
  };

  const openLegal = (which) => {
    setLegalModal(which);
    setLegalText(which === 'license' ? licenseText : noticesText);
  };

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
          <svg className="library-dir-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
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
          <SegmentedControl
            options={[
              { value: 'waveform', label: 'Waveform' },
              { value: 'spectrogram', label: 'Spectrogram' },
              { value: 'off', label: 'Off' },
            ]}
            value={defaultVisualizer}
            onChange={onDefaultVisualizerChange}
            disabled={settingsLoaded === false}
          />
        </div>

        <div className="playback-row">
          <div className="playback-label-group">
            <span className="playback-label">Close to Tray</span>
            <span className="playback-hint">Minimize to system tray instead of quitting when closing the window</span>
          </div>
          <ToggleSwitch
            checked={trayEnabled}
            disabled={!settingsLoaded}
            onChange={changeTrayEnabled}
            label="Close to Tray"
          />
        </div>

        {settingsError && (
          <div className="settings-error" role="alert">{settingsError}</div>
        )}

        {trayEnabled && (
          <>
            <div className="playback-row">
              <div className="playback-label-group">
                <span className="playback-label">Tray Notification</span>
                <span className="playback-hint">Show a notification when the app is minimized to the system tray</span>
              </div>
              <ToggleSwitch
                checked={trayNotify}
                disabled={!settingsLoaded}
                onChange={changeTrayNotify}
                label="Tray Notification"
              />
            </div>

            <div className="playback-row">
              <div className="playback-label-group">
                <span className="playback-label">Launch at Login</span>
                <span className="playback-hint">Automatically start FreePlayer when you log in</span>
              </div>
              <ToggleSwitch
                checked={startOnBoot}
                disabled={!settingsLoaded}
                onChange={changeStartOnBoot}
                label="Launch at Login"
              />
            </div>

            {startOnBoot && (
              <div className="playback-row">
                <div className="playback-label-group">
                  <span className="playback-label">Launch at Login Hidden</span>
                  <span className="playback-hint">Start in the tray without a window when launched at login</span>
                </div>
                <ToggleSwitch
                  checked={startHidden}
                  disabled={!settingsLoaded}
                  onChange={changeStartHidden}
                  label="Launch at Login Hidden"
                />
              </div>
            )}
          </>
        )}
      </div>

      {/* Appearance */}
      <div className="settings-section">
        <div className="section-header">
          <h3 className="section-title">Appearance</h3>
          <p className="section-desc">UI fonts are resolved from fonts installed on this Mac — nothing is downloaded.</p>
        </div>

        <div className="playback-row">
          <div className="playback-label-group">
            <span className="playback-label">Mono Font</span>
            <span className="playback-hint">Font used for durations, timestamps, and the spectrogram labels</span>
          </div>
          <select
            className="plugin-select"
            value={monoFont}
            onChange={(e) => handleMonoFontChange(e.target.value)}
          >
            {MONO_FONTS.map((f) => (
              <option key={f.value || 'default'} value={f.value}>{f.label}</option>
            ))}
          </select>
        </div>
      </div>

      {/* About / Legal — GPL §0 requires an interactive interface to display
          the copyright, no-warranty statement and how to view the license. */}
      <div className="settings-section">
        <div className="section-header">
          <h3 className="section-title">About</h3>
        </div>

        <div className="about-info">
          <div className="about-brand"><span className="brand-tile"><img src={logoUrl} width={56} height={56} alt="" /></span></div>
          <div className="about-row"><span className="about-label">FreePlayer</span><span className="about-value">v{version}</span></div>
          <div className="about-row"><span className="about-label">License</span><span className="about-value">GPL-3.0-or-later</span></div>
          <p className="about-statement">
            Copyright (C) 2026 zprolab.
            FreePlayer is free software: you can redistribute it and/or modify it under
            the terms of the GNU General Public License as published by the Free Software
            Foundation, either version 3 of the License, or (at your option) any later version.
            This program is distributed in the hope that it will be useful, but
            <strong> WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
            or FITNESS FOR A PARTICULAR PURPOSE</strong>.
          </p>
        </div>

        <div className="about-actions">
          <button className="btn btn-secondary" onClick={() => openLegal('license')}>
            View License
          </button>
          <button className="btn btn-secondary" onClick={() => openLegal('notices')}>
            Third-Party Notices
          </button>
        </div>
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

      {/* Legal text dialog */}
      {legalModal && (
        <div className="confirm-overlay" onClick={() => setLegalModal(null)}>
          <div className="confirm-dialog" onClick={(e) => e.stopPropagation()}>
            <h3 className="confirm-title">
              {legalModal === 'license' ? 'GNU General Public License v3' : 'Third-Party Notices'}
            </h3>
            <pre className="legal-text">{legalText}</pre>
            <div className="confirm-actions">
              <button className="btn btn-secondary" onClick={() => setLegalModal(null)}>
                Close
              </button>
            </div>
          </div>
        </div>
      )}

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
});

export default Settings;
