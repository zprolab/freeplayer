# Import Symlink Mode & Settings Page — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add symlink-based music import and a full settings page with import mode, library directory, default volume, default visualizer, and database reset.

**Architecture:** Electron main process handles symlink creation in `music:import-files` (branching on `import_mode` setting) plus two new IPC handlers for directory picking and DB reset. React frontend gets a new `Settings` component organized as stacked cards, a sidebar nav entry, and settings state loaded on app mount.

**Tech Stack:** Electron 33, React 18, better-sqlite3, Vite

---

### Task 1: Add `music:select-library-dir` IPC handler and preload exposure

**Files:**
- Modify: `electron/main.js:345-346` (after `music:is-setup` handler)
- Modify: `electron/preload.js:28-31` (in settings block)

- [ ] **Step 1: Add IPC handler in main.js**

Insert after line 346 (after the `music:is-setup` handler's closing `});`):

```js
  // Select library directory (for settings page)
  ipcMain.handle('music:select-library-dir', async () => {
    const result = await dialog.showOpenDialog(mainWindow, {
      properties: ['openDirectory', 'createDirectory'],
      title: 'Select Library Directory',
    });
    if (result.canceled || result.filePaths.length === 0) {
      return { canceled: true };
    }
    return { canceled: false, path: result.filePaths[0] };
  });
```

- [ ] **Step 2: Expose in preload.js**

In the settings block of `electron/preload.js`, add after line 31 (`isSetup: ...`):

```js
  selectLibraryDir: () => ipcRenderer.invoke('music:select-library-dir'),
```

Full settings block should read:

```js
  // Settings
  getSetting: (key) => ipcRenderer.invoke('music:get-setting', key),
  setSetting: (data) => ipcRenderer.invoke('music:set-setting', data),
  isSetup: () => ipcRenderer.invoke('music:is-setup'),
  selectLibraryDir: () => ipcRenderer.invoke('music:select-library-dir'),
```

- [ ] **Step 3: Verify app compiles**

Run: `cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer && npx vite build 2>&1 | tail -5`
Expected: Build succeeds with no errors.

---

### Task 2: Add `music:reset-database` IPC handler and database function

**Files:**
- Modify: `electron/database.js:326-328` (add `resetDatabase` export)
- Modify: `electron/main.js` (add IPC handler + import)

- [ ] **Step 1: Add `resetDatabase` function in database.js**

Insert before the `module.exports` block at line 328:

```js
function resetDatabase() {
  const db = getDatabase();
  db.exec(`
    DELETE FROM playlist_tracks;
    DELETE FROM play_history;
    DELETE FROM playlists;
    DELETE FROM tracks;
    DELETE FROM settings;
  `);
}
```

- [ ] **Step 2: Export `resetDatabase`**

In the `module.exports` at line 328, add:

```js
  resetDatabase,
```

- [ ] **Step 3: Import `resetDatabase` in main.js**

In `electron/main.js` line 25 (the destructured import from `./database`), add `resetDatabase`:

```js
const {
  initDatabase,
  closeDatabase,
  insertTrack,
  getAllTracks,
  getTrackById,
  updateTrack,
  deleteTrack,
  getTrackCount,
  startPlaySession,
  endPlaySession,
  getPlayHistory,
  getListeningStats,
  createPlaylist,
  getAllPlaylists,
  addTrackToPlaylist,
  getPlaylistTracks,
  removeTrackFromPlaylist,
  deletePlaylist,
  getSetting,
  setSetting,
  resetDatabase,
} = require('./database');
```

- [ ] **Step 4: Add IPC handler in main.js**

Insert after the `music:select-library-dir` handler added in Task 1:

```js
  // Reset database
  ipcMain.handle('music:reset-database', () => {
    resetDatabase();
    return { success: true };
  });
```

- [ ] **Step 5: Expose in preload.js**

In the settings block, add after `selectLibraryDir`:

```js
  resetDatabase: () => ipcRenderer.invoke('music:reset-database'),
```

- [ ] **Step 6: Verify app compiles**

Run: `cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer && npx vite build 2>&1 | tail -5`
Expected: Build succeeds.

---

### Task 3: Modify `music:import-files` to support symlink mode

**Files:**
- Modify: `electron/main.js:178-271` (the `music:import-files` handler)

- [ ] **Step 1: Read import_mode setting at top of handler, branch on copy vs symlink**

In `electron/main.js`, inside the `music:import-files` handler (starts ~line 178), add after the `const musicMetadata = await import('music-metadata');` line (currently line 179):

```js
        const importMode = getSetting('import_mode', 'copy'); // 'copy' | 'symlink'
```

- [ ] **Step 2: Branch file operation inside the per-file loop**

Find the block inside the loop (~lines 207-210) that handles copying:

```js
        // Copy file to library
        const targetPath = path.join(albumDir, baseName);
        if (!fs.existsSync(targetPath)) {
          fs.copyFileSync(filePath, targetPath);
        }
```

Replace with:

```js
        // Copy or symlink file to library
        const targetPath = path.join(albumDir, baseName);
        if (!fs.existsSync(targetPath)) {
          if (importMode === 'symlink') {
            fs.symlinkSync(filePath, targetPath);
          } else {
            fs.copyFileSync(filePath, targetPath);
          }
        }
```

- [ ] **Step 3: Verify app compiles**

Run: `cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer && npx vite build 2>&1 | tail -5`
Expected: Build succeeds.

---

### Task 4: Add settings page CSS styles

**Files:**
- Modify: `src/App.css` (append at end)

- [ ] **Step 1: Append settings CSS to App.css**

```css
/* ═══════════════════════════════════════════════════════════════════
   Settings Page
   ═══════════════════════════════════════════════════════════════════ */

.settings {
  max-width: 640px;
  margin: 0 auto;
  padding: 24px 24px 40px;
}

.settings-section {
  background: var(--gl-white);
  border: 1px solid var(--gl-border);
  border-radius: var(--gl-radius-md);
  padding: 20px;
  margin-bottom: 16px;
}

.settings-section--danger {
  border-color: var(--gl-red);
}

.section-header {
  margin-bottom: 16px;
}

.section-title {
  font-size: 14px;
  font-weight: 600;
  color: var(--gl-text-primary);
  margin-bottom: 2px;
  letter-spacing: -0.01em;
}

.section-title--danger {
  color: var(--gl-red);
}

.section-desc {
  font-size: 12px;
  color: var(--gl-text-secondary);
  line-height: 1.5;
}

/* Import mode radio cards */
.import-mode-options {
  display: flex;
  gap: 12px;
}

.import-mode-card {
  flex: 1;
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 14px;
  border: 2px solid var(--gl-border);
  border-radius: var(--gl-radius-md);
  cursor: pointer;
  background: transparent;
  transition: border-color 0.15s ease, background 0.15s ease;
  font-family: var(--font-ui);
  text-align: left;
}

.import-mode-card:hover {
  border-color: #ccc;
}

.import-mode-card--selected {
  border-color: var(--gl-orange);
  background: var(--gl-orange-light);
}

.import-mode-card--selected:hover {
  border-color: var(--gl-orange-hover);
}

.import-mode-radio {
  width: 20px;
  height: 20px;
  border-radius: 50%;
  border: 2px solid var(--gl-border);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  transition: border-color 0.15s ease;
}

.import-mode-card--selected .import-mode-radio {
  border-color: var(--gl-orange);
}

.import-mode-radio-dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  background: var(--gl-orange);
  transform: scale(0);
  transition: transform 0.15s ease;
}

.import-mode-card--selected .import-mode-radio-dot {
  transform: scale(1);
}

.import-mode-label {
  font-size: 13px;
  font-weight: 600;
  color: var(--gl-text-primary);
  margin-bottom: 1px;
}

.import-mode-hint {
  font-size: 11px;
  color: var(--gl-text-secondary);
}

/* Library directory display */
.library-dir-display {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 12px;
  background: #fafafa;
  border: 1px solid var(--gl-border-light);
  border-radius: var(--gl-radius-sm);
}

.library-dir-icon {
  color: var(--gl-text-tertiary);
  flex-shrink: 0;
}

.library-dir-path {
  font-size: 12px;
  color: var(--gl-text-primary);
  font-family: var(--font-mono);
  flex: 1;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.library-dir-empty {
  font-size: 12px;
  color: var(--gl-text-tertiary);
  flex: 1;
}

/* Playback settings row */
.playback-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 0;
}

.playback-row + .playback-row {
  border-top: 1px solid var(--gl-border-light);
}

.playback-label-group {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.playback-label {
  font-size: 13px;
  font-weight: 500;
  color: var(--gl-text-primary);
}

.playback-hint {
  font-size: 11px;
  color: var(--gl-text-tertiary);
}

/* Volume slider row */
.volume-setting {
  display: flex;
  align-items: center;
  gap: 10px;
}

.volume-setting input[type="range"] {
  width: 100px;
}

.volume-value {
  font-size: 12px;
  font-family: var(--font-mono);
  color: var(--gl-text-secondary);
  width: 32px;
  text-align: right;
}

/* Visualizer segmented button */
.vis-mode-group--settings {
  display: flex;
  border: 1px solid var(--gl-border);
  border-radius: var(--gl-radius-sm);
  overflow: hidden;
}

.vis-mode-btn--settings {
  padding: 5px 12px;
  border: none;
  background: transparent;
  color: var(--gl-text-secondary);
  font-family: var(--font-ui);
  font-size: 11px;
  font-weight: 500;
  cursor: pointer;
  transition: background 0.12s, color 0.12s;
}

.vis-mode-btn--settings + .vis-mode-btn--settings {
  border-left: 1px solid var(--gl-border);
}

.vis-mode-btn--settings:hover {
  background: var(--gl-border-light);
}

.vis-mode-btn--settings--active {
  background: var(--gl-orange);
  color: #fff;
}

.vis-mode-btn--settings--active:hover {
  background: var(--gl-orange-hover);
}

/* Danger zone */
.danger-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.danger-info {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.danger-label {
  font-size: 13px;
  font-weight: 500;
  color: var(--gl-text-primary);
}

.danger-hint {
  font-size: 11px;
  color: var(--gl-text-tertiary);
}

.btn-danger {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 6px 14px;
  border-radius: var(--gl-radius-sm);
  font-family: var(--font-ui);
  font-size: 13px;
  font-weight: 500;
  cursor: pointer;
  border: 1px solid var(--gl-red);
  background: transparent;
  color: var(--gl-red);
  transition: background 0.12s, color 0.12s;
  white-space: nowrap;
  flex-shrink: 0;
}

.btn-danger:hover {
  background: var(--gl-red);
  color: #fff;
}

/* Reset confirmation dialog */
.confirm-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.5);
  z-index: 250;
  display: flex;
  align-items: center;
  justify-content: center;
  animation: fadeIn 0.15s ease;
}

.confirm-dialog {
  background: var(--gl-white);
  border-radius: var(--gl-radius-lg);
  box-shadow: var(--gl-shadow-xl);
  width: 380px;
  padding: 24px;
  animation: slideUp 0.2s ease;
}

.confirm-title {
  font-size: 16px;
  font-weight: 600;
  color: var(--gl-text-primary);
  margin-bottom: 8px;
}

.confirm-message {
  font-size: 13px;
  color: var(--gl-text-secondary);
  line-height: 1.6;
  margin-bottom: 20px;
}

.confirm-actions {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
}

/* Import mode badge in import modal */
.import-mode-badge {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: 11px;
  font-weight: 500;
  padding: 3px 10px;
  border-radius: 10px;
  background: var(--gl-blue-light);
  color: var(--gl-blue);
  font-family: var(--font-mono);
}
```

- [ ] **Step 2: Verify build**

Run: `cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer && npx vite build 2>&1 | tail -5`
Expected: Build succeeds (CSS is always valid, but verify no tooling issues).

---

### Task 5: Create Settings.jsx component

**Files:**
- Create: `src/components/Settings.jsx`

- [ ] **Step 1: Write the Settings component**

```jsx
import React, { useState } from 'react';

export default function Settings({
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
```

- [ ] **Step 2: Verify build**

Run: `cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer && npx vite build 2>&1 | tail -5`
Expected: Build succeeds.

---

### Task 6: Update Sidebar.jsx with Settings nav item

**Files:**
- Modify: `src/components/Sidebar.jsx:38-65` (nav items and nav section)

- [ ] **Step 1: Add Settings to nav items array**

In `src/components/Sidebar.jsx`, after the `stats` nav item object (line 36 `},`), insert:

```js
    {
      id: 'settings',
      label: 'Settings',
      icon: (
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="12" cy="12" r="3"/>
          <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>
        </svg>
      ),
    },
```

- [ ] **Step 2: Remove trackCount badge condition for non-library views**

No change needed — the existing logic `item.id === 'library' && trackCount > 0` already skips Settings. But update the nav label logic: the `nav-badge` only shows for library, which is correct.

- [ ] **Step 3: Verify build**

Run: `cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer && npx vite build 2>&1 | tail -5`
Expected: Build succeeds.

---

### Task 7: Update App.jsx with Settings view and settings state

**Files:**
- Modify: `src/App.jsx:1-373` (multiple sections)

- [ ] **Step 1: Add SETTINGS to VIEWS constant**

At `src/App.jsx` line 14, add after `STATS: 'stats',`:

```js
  SETTINGS: 'settings',
```

- [ ] **Step 2: Add settings state variables**

After the `visualizerMode` state (line 33), add:

```js
  const [importMode, setImportMode] = useState('copy');
  const [defaultVolume, setDefaultVolume] = useState(0.8);
  const [defaultVisualizer, setDefaultVisualizer] = useState('waveform');
```

- [ ] **Step 3: Load settings on mount**

Inside the `checkSetup` function (line 41), after `setLibraryDir(result.libraryDir || '');` (line 46), add:

```js
          // Load other settings
          const impMode = await window.freeplayer.getSetting('import_mode');
          if (impMode) setImportMode(impMode);
          const defVol = await window.freeplayer.getSetting('default_volume');
          if (defVol) {
            const vol = parseFloat(defVol);
            setDefaultVolume(vol);
            setVolume(vol);
            audioRef.current.volume = vol;
          }
          const defVis = await window.freeplayer.getSetting('default_visualizer');
          if (defVis) {
            setDefaultVisualizer(defVis);
            setVisualizerMode(defVis);
          }
```

- [ ] **Step 4: Add setting change handlers**

After the `handleImportComplete` function (~line 228), add:

```js
  const handleImportModeChange = async (mode) => {
    setImportMode(mode);
    await window.freeplayer.setSetting({ key: 'import_mode', value: mode });
  };

  const handleLibraryDirChange = (dir) => {
    setLibraryDir(dir);
  };

  const handleDefaultVolumeChange = async (vol) => {
    setDefaultVolume(vol);
    await window.freeplayer.setSetting({ key: 'default_volume', value: String(vol) });
  };

  const handleDefaultVisualizerChange = async (mode) => {
    setDefaultVisualizer(mode);
    await window.freeplayer.setSetting({ key: 'default_visualizer', value: mode });
  };

  const handleResetDatabase = async () => {
    setTracks([]);
    setCurrentTrack(null);
    setIsPlaying(false);
    setQueue([]);
    setQueueIndex(-1);
    setLibraryDir('');
    setIsSetup(false);
    setImportMode('copy');
    setDefaultVolume(0.8);
    setDefaultVisualizer('waveform');
    setVisualizerMode('waveform');
    audioRef.current.src = '';
  };
```

- [ ] **Step 5: Add Settings view rendering**

In the content-area div (~line 291), replace the existing conditional structure. The Settings view should be accessible even before library setup. Find:

```jsx
        <div className="content-area">
          {!isSetup ? (
            <div className="empty-state">
```

Change the conditional to check Settings first, then fall through to the setup gate:

```jsx
        <div className="content-area">
          {view === VIEWS.SETTINGS ? (
            <Settings
              importMode={importMode}
              onImportModeChange={handleImportModeChange}
              libraryDir={libraryDir}
              onLibraryDirChange={handleLibraryDirChange}
              defaultVolume={defaultVolume}
              onDefaultVolumeChange={handleDefaultVolumeChange}
              defaultVisualizer={defaultVisualizer}
              onDefaultVisualizerChange={handleDefaultVisualizerChange}
              onResetDatabase={handleResetDatabase}
            />
          ) : !isSetup ? (
            <div className="empty-state">
              ...existing empty state JSX...
            </div>
          ) : (
            <>
              {view === VIEWS.LIBRARY && (
                ...existing Library JSX...
              )}
              {view === VIEWS.NOW_PLAYING && (
                ...existing NowPlaying JSX...
              )}
              {view === VIEWS.STATS && <Stats />}
            </>
          )}
        </div>
```

This nests: Settings check → setup gate → view routing. Only the conditional wrapper changes; the inner JSX for Library, NowPlaying, and Stats stays identical.

- [ ] **Step 6: Add Settings import at top**

After the ImportModal import (line 7), add:

```js
import Settings from './components/Settings';
```

- [ ] **Step 7: Update page title for Settings view**

In the top-bar header, add after the STATS line (~line 253):

```js
              {view === VIEWS.SETTINGS && 'Settings'}
```

- [ ] **Step 8: Verify build**

Run: `cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer && npx vite build 2>&1 | tail -5`
Expected: Build succeeds.

---

### Task 8: Update ImportModal.jsx with import mode badge

**Files:**
- Modify: `src/components/ImportModal.jsx:3-13,86-96` (component function and modal header)

- [ ] **Step 1: Accept importMode prop**

Change the component signature from:

```jsx
export default function ImportModal({ onClose, onComplete }) {
```

To:

```jsx
export default function ImportModal({ onClose, onComplete, importMode }) {
```

- [ ] **Step 2: Add import mode badge in modal header**

After the modal-title `<h2>` (line 87), add:

```jsx
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <span className="import-mode-badge">
              {importMode === 'symlink' ? (
                <>
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                    <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/>
                    <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>
                  </svg>
                  Symlink Mode
                </>
              ) : (
                <>
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                    <rect x="9" y="9" width="13" height="13" rx="2" ry="2"/>
                    <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>
                  </svg>
                  Copy Mode
                </>
              )}
            </span>
          </div>
```

- [ ] **Step 3: Pass importMode prop in App.jsx**

In `src/App.jsx`, find the `<ImportModal` usage (~line 365) and add the `importMode` prop:

```jsx
        <ImportModal
          onClose={() => setImportModalOpen(false)}
          onComplete={handleImportComplete}
          importMode={importMode}
        />
```

- [ ] **Step 4: Verify build**

Run: `cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer && npx vite build 2>&1 | tail -5`
Expected: Build succeeds.

---

### Task 9: Final integration verification

- [ ] **Step 1: Full build**

Run: `cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer && npx vite build 2>&1`
Expected: Build succeeds with no warnings or errors.

- [ ] **Step 2: Check all imports resolve**

Run: `cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer && node -e "require('./electron/database.js')" 2>&1`
Expected: Error (expected — runs outside Electron), but should not be a syntax error.

- [ ] **Step 3: Manual smoke test checklist**

Launch the app with `npm run dev` and verify:
- Settings appears in sidebar with gear icon
- Clicking Settings shows the settings page
- Import mode radio cards switch between Copy and Symlink (check DB with sqlite3)
- Library directory displays current path, "Change..." opens native picker
- Default volume slider works, persists across restart
- Default visualizer segmented button works, persists across restart
- Reset Database shows confirmation, cancelling does nothing, confirming clears everything
- Import modal shows "Copy Mode" or "Symlink Mode" badge matching the setting
