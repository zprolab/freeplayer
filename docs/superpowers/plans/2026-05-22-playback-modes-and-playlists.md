# Playback Modes & Playlists Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three mutually-exclusive playback modes (list loop, repeat-one, shuffle) and a playlist management system with a default "All Tracks" list plus user-created playlists.

**Architecture:** New state in App.jsx drives all playback mode and playlist logic. Two new components (PlaylistModal, PlaylistMenu) handle UI for playlist CRUD and track-to-playlist assignment. Existing components (Sidebar, Library, PlayerBar, NowPlaying) receive new props for mode/playlist rendering. One backend addition (renamePlaylist) completes the CRUD set.

**Tech Stack:** Electron + React (plain JSX) + better-sqlite3 + CSS custom properties (GitLab-inspired design system)

---

## File Structure

| File | Responsibility |
|------|---------------|
| `electron/database.js` | Add `renamePlaylist` function |
| `electron/main.js` | Add `playlist:rename` IPC handler |
| `electron/preload.js` | Expose `renamePlaylist` to renderer |
| `src/components/PlaylistModal.jsx` | **New.** Create / Rename playlist modal |
| `src/components/PlaylistMenu.jsx` | **New.** "Add to Playlist" flyout submenu |
| `src/App.jsx` | Play mode state + handleNext rewrite + playlist state + handlers + top bar enhancement |
| `src/App.css` | All new styles (~200 lines) |
| `src/components/Sidebar.jsx` | Playlists section with context menu |
| `src/components/Library.jsx` | "Add to Playlist" submenu + "Remove from Playlist" in context menu |
| `src/components/PlayerBar.jsx` | Compact play mode icon buttons |
| `src/components/NowPlaying.jsx` | Full play mode segmented buttons |

---

### Task 1: Add renamePlaylist to backend

**Files:**
- Modify: `electron/database.js`
- Modify: `electron/main.js`
- Modify: `electron/preload.js`

- [ ] **Step 1: Add renamePlaylist to database.js**

Add after `deletePlaylist` (line ~311):

```js
function renamePlaylist(id, name) {
  const db = getDatabase();
  return db.prepare(
    'UPDATE playlists SET name = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?'
  ).run(name, id);
}
```

And add `renamePlaylist` to the `module.exports` block. Find the exports at the bottom of database.js:

```js
// Find this block and add renamePlaylist:
module.exports = {
  initDatabase,
  // ... existing exports ...
  deletePlaylist,
  renamePlaylist,       // <-- add this
  getSetting,
  setSetting,
  // ...
};
```

- [ ] **Step 2: Add IPC handler in main.js**

Add after the `playlist:delete` handler (line ~413):

```js
ipcMain.handle('playlist:rename', (_event, { id, name }) => {
  return renamePlaylist(id, name);
});
```

- [ ] **Step 3: Expose in preload.js**

Add after `deletePlaylist` (line ~41):

```js
renamePlaylist: (data) => ipcRenderer.invoke('playlist:rename', data),
```

- [ ] **Step 4: Verify**

```bash
cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer && npx electron . 2>&1 | head -20
```

Expected: App launches without errors. Check console for any missing export errors.

---

### Task 2: Create PlaylistModal component

**Files:**
- Create: `src/components/PlaylistModal.jsx`

- [ ] **Step 1: Create the component**

```jsx
import React, { useState, useEffect, useRef } from 'react';

export default function PlaylistModal({ mode, playlist, onClose, onSubmit }) {
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const inputRef = useRef(null);

  useEffect(() => {
    if (mode === 'rename' && playlist) {
      setName(playlist.name || '');
    }
  }, [mode, playlist]);

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  const handleSubmit = (e) => {
    e.preventDefault();
    const trimmed = name.trim();
    if (!trimmed) return;
    onSubmit({ name: trimmed, description: description.trim() });
  };

  const handleKeyDown = (e) => {
    if (e.key === 'Escape') onClose();
  };

  return (
    <div className="modal-overlay" onClick={onClose} onKeyDown={handleKeyDown}>
      <div className="modal" onClick={(e) => e.stopPropagation()} style={{ width: '420px' }}>
        <div className="modal-header">
          <h2 className="modal-title">
            {mode === 'create' ? 'New Playlist' : 'Rename Playlist'}
          </h2>
          <button className="modal-close btn-icon" onClick={onClose}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
              <line x1="18" y1="6" x2="6" y2="18"/>
              <line x1="6" y1="6" x2="18" y2="18"/>
            </svg>
          </button>
        </div>

        <form onSubmit={handleSubmit}>
          <div className="modal-body">
            <div className="edit-fields">
              <div className="edit-field">
                <label className="edit-label">Name</label>
                <input
                  ref={inputRef}
                  type="text"
                  className="edit-input"
                  placeholder="My Playlist"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  maxLength={200}
                  autoFocus
                />
              </div>
              {mode === 'create' && (
                <div className="edit-field">
                  <label className="edit-label">
                    Description <span style={{ fontWeight: 400, textTransform: 'none', letterSpacing: 0 }}>(optional)</span>
                  </label>
                  <input
                    type="text"
                    className="edit-input"
                    placeholder="A few words about this playlist..."
                    value={description}
                    onChange={(e) => setDescription(e.target.value)}
                    maxLength={500}
                  />
                </div>
              )}
            </div>
          </div>

          <div className="modal-footer">
            <button type="button" className="btn btn-secondary" onClick={onClose}>Cancel</button>
            <button type="submit" className="btn btn-primary" disabled={!name.trim()}>
              {mode === 'create' ? 'Create' : 'Rename'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Verify component exists**

```bash
ls -la /Users/eason/Documents/Coding/hi-zcy/FreePlayer/src/components/PlaylistModal.jsx
```

---

### Task 3: Create PlaylistMenu submenu component

**Files:**
- Create: `src/components/PlaylistMenu.jsx`

- [ ] **Step 1: Create the component**

```jsx
import React from 'react';

export default function PlaylistMenu({ track, playlists, onAdd, onCreateNew, onClose, position }) {
  const userPlaylists = playlists || [];

  return (
    <>
      <div className="overlay" onClick={onClose} />
      <div
        className="context-menu playlist-submenu"
        style={{ left: position.x, top: position.y }}
      >
        {userPlaylists.length === 0 ? (
          <div className="submenu-empty">No playlists yet</div>
        ) : (
          userPlaylists.map((pl) => (
            <button
              key={pl.id}
              className="context-menu-item"
              onClick={() => { onAdd(pl.id, track.id); onClose(); }}
            >
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M9 18V5l12-2v13"/>
                <circle cx="6" cy="18" r="3"/>
                <circle cx="18" cy="16" r="3"/>
              </svg>
              {pl.name}
            </button>
          ))
        )}
        <div className="context-menu-divider" />
        <button
          className="context-menu-item submenu-new"
          onClick={() => { onCreateNew(); onClose(); }}
        >
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
            <line x1="12" y1="5" x2="12" y2="19"/>
            <line x1="5" y1="12" x2="19" y2="12"/>
          </svg>
          New Playlist...
        </button>
      </div>
    </>
  );
}
```

- [ ] **Step 2: Verify component exists**

```bash
ls -la /Users/eason/Documents/Coding/hi-zcy/FreePlayer/src/components/PlaylistMenu.jsx
```

---

### Task 4: Add play mode state and rewrite playback logic in App.jsx

**Files:**
- Modify: `src/App.jsx`

- [ ] **Step 1: Add playMode and shuffledQueue state**

Find the existing state declarations (~line 39) and add after `const [importMode, setImportMode] = useState('copy');`:

```jsx
const [playMode, setPlayMode] = useState('sequential'); // 'sequential' | 'repeat-one' | 'shuffle'
const [shuffledQueue, setShuffledQueue] = useState([]);
```

- [ ] **Step 2: Rewrite handleNext**

Replace the existing `handleNext` function (lines ~206-212):

```jsx
const handleNext = () => {
  if (!queue.length) return;

  if (playMode === 'repeat-one') {
    audioRef.current.currentTime = 0;
    audioRef.current.play().catch(console.error);
    return;
  }

  let nextIdx;
  if (playMode === 'shuffle') {
    const shuffled = shuffledQueue.length > 0 ? shuffledQueue : queue;
    const currentShuffledIdx = shuffled.findIndex(t => t.id === queue[queueIndex]?.id);
    if (currentShuffledIdx < shuffled.length - 1) {
      nextIdx = queue.findIndex(t => t.id === shuffled[currentShuffledIdx + 1].id);
    } else {
      // Re-shuffle and start over
      const reshuffled = [...queue].sort(() => Math.random() - 0.5);
      setShuffledQueue(reshuffled);
      nextIdx = queue.findIndex(t => t.id === reshuffled[0].id);
    }
  } else {
    // sequential with loop
    if (queueIndex < queue.length - 1) {
      nextIdx = queueIndex + 1;
    } else {
      nextIdx = 0;
    }
  }

  setQueueIndex(nextIdx);
  playTrack(queue[nextIdx]);
};
```

- [ ] **Step 3: Rewrite handlePrev**

Replace the existing `handlePrev` function (lines ~214-223):

```jsx
const handlePrev = () => {
  if (!queue.length) return;

  const audio = audioRef.current;
  if (audio.currentTime > 3) {
    audio.currentTime = 0;
    return;
  }

  let prevIdx;
  if (playMode === 'shuffle') {
    const shuffled = shuffledQueue.length > 0 ? shuffledQueue : queue;
    const currentShuffledIdx = shuffled.findIndex(t => t.id === queue[queueIndex]?.id);
    if (currentShuffledIdx > 0) {
      prevIdx = queue.findIndex(t => t.id === shuffled[currentShuffledIdx - 1].id);
    } else {
      prevIdx = queue.findIndex(t => t.id === shuffled[shuffled.length - 1].id);
    }
  } else {
    if (queueIndex > 0) {
      prevIdx = queueIndex - 1;
    } else {
      prevIdx = queue.length - 1;
    }
  }

  setQueueIndex(prevIdx);
  playTrack(queue[prevIdx]);
};
```

- [ ] **Step 4: Update playTrackFromList to handle shuffle**

Replace the existing `playTrackFromList` (lines ~235-239):

```jsx
const playTrackFromList = async (track, trackList) => {
  setQueue(trackList);
  const idx = trackList.findIndex(t => t.id === track.id);
  setQueueIndex(idx);

  if (playMode === 'shuffle') {
    const shuffled = [...trackList].sort(() => Math.random() - 0.5);
    // Ensure clicked track is first in shuffled order
    const clickedIdx = shuffled.findIndex(t => t.id === track.id);
    if (clickedIdx > 0) {
      [shuffled[0], shuffled[clickedIdx]] = [shuffled[clickedIdx], shuffled[0]];
    }
    setShuffledQueue(shuffled);
  } else {
    setShuffledQueue([]);
  }

  await playTrack(track);
};
```

- [ ] **Step 5: Verify app compiles**

```bash
cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer && npx vite build 2>&1 | tail -5
```

Expected: Build succeeds with no errors.

---

### Task 5: Add playlist state and handlers in App.jsx

**Files:**
- Modify: `src/App.jsx`

- [ ] **Step 1: Add import for PlaylistModal**

Add at top of imports (~line 8):

```jsx
import PlaylistModal from './components/PlaylistModal';
```

- [ ] **Step 2: Add playlist state**

Add after the playMode state from Task 4:

```jsx
const [playlists, setPlaylists] = useState([]);
const [activePlaylistId, setActivePlaylistId] = useState(null); // null = All Tracks
const [playlistTracks, setPlaylistTracks] = useState([]); // tracks of selected playlist
const [playlistModal, setPlaylistModal] = useState(null); // { mode, playlist } or null
const [pendingAddTrack, setPendingAddTrack] = useState(null); // track to add after creating new playlist
```

- [ ] **Step 3: Add loadPlaylists and call on mount**

Add after existing `loadTracks` definition (~line 81):

```jsx
const loadPlaylists = useCallback(async () => {
  try {
    const data = await window.freeplayer.getPlaylists();
    setPlaylists(data || []);
  } catch (err) {
    console.error('Failed to load playlists:', err);
  }
}, []);
```

In the setup `useEffect` (~line 48), add `await loadPlaylists();` after `await loadTracks();`:

```jsx
if (result.setup) {
  await loadTracks();
  await loadPlaylists();
}
```

- [ ] **Step 4: Add playlist handlers**

Add after `loadPlaylists`:

```jsx
const handleSelectPlaylist = async (playlistId) => {
  setActivePlaylistId(playlistId);
  if (playlistId === null) {
    await loadTracks();
    setView(VIEWS.LIBRARY);
  } else {
    const tracks = await window.freeplayer.getPlaylistTracks(playlistId);
    setPlaylistTracks(tracks || []);
    setView(VIEWS.LIBRARY);
  }
};

const handleCreatePlaylist = async ({ name, description }) => {
  const result = await window.freeplayer.createPlaylist({ name, description });
  await loadPlaylists();
  setPlaylistModal(null);
  if (pendingAddTrack) {
    await window.freeplayer.addToPlaylist({ playlistId: result.lastInsertRowid || result.id, trackId: pendingAddTrack.id });
    setPendingAddTrack(null);
  }
};

const handleRenamePlaylist = async ({ name }) => {
  if (playlistModal?.playlist) {
    await window.freeplayer.renamePlaylist({ id: playlistModal.playlist.id, name });
    await loadPlaylists();
    setPlaylistModal(null);
  }
};

const handleDeletePlaylist = async (playlistId) => {
  await window.freeplayer.deletePlaylist(playlistId);
  if (activePlaylistId === playlistId) {
    setActivePlaylistId(null);
    await loadTracks();
  }
  await loadPlaylists();
};

const handleAddToPlaylist = async (playlistId, trackId) => {
  await window.freeplayer.addToPlaylist({ playlistId, trackId });
  // If currently viewing that playlist, refresh its tracks
  if (activePlaylistId === playlistId) {
    const tracks = await window.freeplayer.getPlaylistTracks(playlistId);
    setPlaylistTracks(tracks || []);
  }
};

const handleRemoveFromPlaylist = async (trackId) => {
  if (activePlaylistId === null) return;
  await window.freeplayer.removeFromPlaylist({ playlistId: activePlaylistId, trackId });
  const tracks = await window.freeplayer.getPlaylistTracks(activePlaylistId);
  setPlaylistTracks(tracks || []);
};

const handleOpenCreateForTrack = (track) => {
  setPendingAddTrack(track);
  setPlaylistModal({ mode: 'create', playlist: null });
};
```

- [ ] **Step 5: Render PlaylistModal**

Add in the JSX return, after the ImportModal closing tag and before the closing `</div>` of `.app`:

```jsx
{playlistModal && (
  <PlaylistModal
    mode={playlistModal.mode}
    playlist={playlistModal.playlist}
    onClose={() => {
      setPlaylistModal(null);
      setPendingAddTrack(null);
    }}
    onSubmit={playlistModal.mode === 'create' ? handleCreatePlaylist : handleRenamePlaylist}
  />
)}
```

- [ ] **Step 6: Determine display tracks for Library**

In the JSX where Library is rendered (~line 438), change the tracks prop to use the correct source:

```jsx
{view === VIEWS.LIBRARY && (
  <Library
    tracks={activePlaylistId === null ? tracks : playlistTracks}
    onPlay={playTrackFromList}
    currentTrack={currentTrack}
    isPlaying={isPlaying}
    sortBy={sortBy}
    sortDir={sortDir}
    onTracksChanged={activePlaylistId === null ? loadTracks : () => handleSelectPlaylist(activePlaylistId)}
    onSort={(col) => {
      if (sortBy === col) {
        setSortDir(sortDir === 'ASC' ? 'DESC' : 'ASC');
      } else {
        setSortBy(col);
        setSortDir(col === 'title' || col === 'artist' ? 'ASC' : 'DESC');
      }
    }}
    activePlaylistId={activePlaylistId}
    playlists={playlists}
    onAddToPlaylist={handleAddToPlaylist}
    onRemoveFromPlaylist={handleRemoveFromPlaylist}
    onCreatePlaylistForTrack={handleOpenCreateForTrack}
  />
)}
```

- [ ] **Step 7: Pass playlists and playlistModal handler to Sidebar**

Update the Sidebar JSX (~line 338):

```jsx
<Sidebar
  currentView={view}
  onNavigate={setView}
  trackCount={tracks.length}
  onImport={() => setImportModalOpen(true)}
  playlists={playlists}
  activePlaylistId={activePlaylistId}
  onSelectPlaylist={handleSelectPlaylist}
  onCreatePlaylist={() => setPlaylistModal({ mode: 'create', playlist: null })}
  onRenamePlaylist={(playlist) => setPlaylistModal({ mode: 'rename', playlist })}
  onDeletePlaylist={handleDeletePlaylist}
/>
```

- [ ] **Step 8: Update top bar title for playlist context**

Change the page title line (~line 349):

```jsx
<h1 className="page-title">
  {view === VIEWS.LIBRARY && (activePlaylistId !== null
    ? (playlists.find(p => p.id === activePlaylistId)?.name || 'Playlist')
    : 'Library'
  )}
  {view === VIEWS.NOW_PLAYING && 'Now Playing'}
  {view === VIEWS.STATS && 'Statistics'}
  {view === VIEWS.SETTINGS && 'Settings'}
</h1>
```

And update the track count badge (~line 354):

```jsx
{view === VIEWS.LIBRARY && (
  <span className="track-count-badge">
    {activePlaylistId === null ? tracks.length : playlistTracks.length} tracks
  </span>
)}
```

- [ ] **Step 9: Pass playMode to NowPlaying and PlayerBar**

Update NowPlaying JSX (~line 457):

```jsx
<NowPlaying
  currentTrack={currentTrack}
  isPlaying={isPlaying}
  currentTime={currentTime}
  duration={duration}
  onSeek={handleSeek}
  onTogglePlay={togglePlayPause}
  onNext={handleNext}
  onPrev={handlePrev}
  queue={queue}
  queueIndex={queueIndex}
  onPlayFromQueue={playTrackFromList}
  audioElement={audioRef.current}
  visualizerMode={visualizerMode}
  onVisualizerModeChange={setVisualizerMode}
  playMode={playMode}
  onPlayModeChange={setPlayMode}
/>
```

Update PlayerBar JSX (~line 481):

```jsx
<PlayerBar
  currentTrack={currentTrack}
  isPlaying={isPlaying}
  currentTime={currentTime}
  duration={duration}
  onTogglePlay={togglePlayPause}
  onNext={handleNext}
  onPrev={handlePrev}
  onSeek={handleSeek}
  volume={volume}
  onVolumeChange={handleVolumeChange}
  playMode={playMode}
  onPlayModeChange={setPlayMode}
/>
```

- [ ] **Step 10: Verify build**

```bash
cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer && npx vite build 2>&1 | tail -5
```

Expected: Build succeeds.

---

### Task 6: Update PlayerBar with compact play mode buttons

**Files:**
- Modify: `src/components/PlayerBar.jsx`

- [ ] **Step 1: Add playMode props and render mode buttons**

Change the function signature to accept new props:

```jsx
export default function PlayerBar({
  currentTrack, isPlaying, currentTime, duration,
  onTogglePlay, onNext, onPrev, onSeek, volume, onVolumeChange,
  playMode, onPlayModeChange,
}) {
```

Add the mode buttons inside `.player-extras`, before the time display. Find the `player-extras` div (~line 801) and insert the mode buttons:

```jsx
<div className="player-extras">
  {/* Play mode buttons */}
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
        <text x="10" y="20" fill="currentColor" stroke="none" fontFamily="sans-serif" fontSize="9" fontWeight="700">1</text>
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
  {/* ... rest of volume control ... */}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer && npx vite build 2>&1 | tail -5
```

---

### Task 7: Update NowPlaying with full play mode buttons

**Files:**
- Modify: `src/components/NowPlaying.jsx`

- [ ] **Step 1: Add playMode props and render segmented buttons**

Change function signature:

```jsx
export default function NowPlaying({
  currentTrack, isPlaying, currentTime, duration,
  onSeek, onTogglePlay, onNext, onPrev,
  queue, queueIndex, onPlayFromQueue,
  audioElement,
  visualizerMode, onVisualizerModeChange,
  playMode, onPlayModeChange,
}) {
```

Add the mode buttons after the controls div (`.np-controls`, ~line 133), before the Queue section:

```jsx
{/* Play Mode */}
<div className="np-play-mode">
  <div className="vis-mode-group--settings" style={{ display: 'inline-flex', border: '1px solid var(--gl-border)', borderRadius: 'var(--gl-radius-sm)', overflow: 'hidden' }}>
    <button
      className={`vis-mode-btn--settings ${playMode === 'sequential' ? 'vis-mode-btn--settings--active' : ''}`}
      onClick={() => onPlayModeChange('sequential')}
    >
      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ marginRight: 4 }}>
        <polyline points="1 4 1 10 7 10"/>
        <path d="M3.51 15a9 9 0 1 0 2.13-9.36L1 10"/>
      </svg>
      List Loop
    </button>
    <button
      className={`vis-mode-btn--settings ${playMode === 'repeat-one' ? 'vis-mode-btn--settings--active' : ''}`}
      onClick={() => onPlayModeChange('repeat-one')}
    >
      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ marginRight: 4 }}>
        <polyline points="1 4 1 10 7 10"/>
        <path d="M3.51 15a9 9 0 1 0 2.13-9.36L1 10"/>
      </svg>
      Repeat One
    </button>
    <button
      className={`vis-mode-btn--settings ${playMode === 'shuffle' ? 'vis-mode-btn--settings--active' : ''}`}
      onClick={() => onPlayModeChange('shuffle')}
    >
      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ marginRight: 4 }}>
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
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer && npx vite build 2>&1 | tail -5
```

---

### Task 8: Update Sidebar with playlists section

**Files:**
- Modify: `src/components/Sidebar.jsx`

- [ ] **Step 1: Add playlist props and context menu state**

Change function signature:

```jsx
export default function Sidebar({
  currentView, onNavigate, trackCount, onImport,
  playlists, activePlaylistId, onSelectPlaylist,
  onCreatePlaylist, onRenamePlaylist, onDeletePlaylist,
}) {
```

Add context menu state at top of component:

```jsx
const [playlistContextMenu, setPlaylistContextMenu] = React.useState(null);
```

- [ ] **Step 2: Render playlists section**

After the `</nav>` closing tag and before `<div className="sidebar-footer">`, add:

```jsx
<div className="sidebar-playlists">
  <div className="sidebar-playlists-header">
    <span className="sidebar-playlists-label">Playlists</span>
    <button
      className="sidebar-playlists-add"
      onClick={onCreatePlaylist}
      title="New Playlist"
    >
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
        <line x1="12" y1="5" x2="12" y2="19"/>
        <line x1="5" y1="12" x2="19" y2="12"/>
      </svg>
    </button>
  </div>

  <div className="sidebar-playlists-list">
    {/* All Tracks — always present */}
    <button
      className={`nav-item ${activePlaylistId === null ? 'nav-item--active' : ''}`}
      onClick={() => onSelectPlaylist(null)}
    >
      <span className="nav-icon">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
          <path d="M9 18V5l12-2v13"/>
          <circle cx="6" cy="18" r="3"/>
          <circle cx="18" cy="16" r="3"/>
        </svg>
      </span>
      <span className="nav-label">All Tracks</span>
      {trackCount > 0 && <span className="nav-badge">{trackCount}</span>}
    </button>

    {/* User playlists */}
    {playlists && playlists.map((pl) => (
      <button
        key={pl.id}
        className={`nav-item ${activePlaylistId === pl.id ? 'nav-item--active' : ''}`}
        onClick={() => onSelectPlaylist(pl.id)}
        onContextMenu={(e) => {
          e.preventDefault();
          setPlaylistContextMenu({ x: e.clientX, y: e.clientY, playlist: pl });
        }}
      >
        <span className="nav-icon">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <path d="M9 18V5l12-2v13"/>
            <circle cx="6" cy="18" r="3"/>
            <circle cx="18" cy="16" r="3"/>
          </svg>
        </span>
        <span className="nav-label">{pl.name}</span>
      </button>
    ))}
  </div>
</div>
```

- [ ] **Step 3: Add playlist context menu**

Add after the `</aside>` closing tag (but inside the return):

```jsx
{/* Playlist context menu */}
{playlistContextMenu && (
  <>
    <div className="overlay" onClick={() => setPlaylistContextMenu(null)} />
    <div
      className="context-menu"
      style={{ left: playlistContextMenu.x, top: playlistContextMenu.y }}
    >
      <button className="context-menu-item" onClick={() => {
        onRenamePlaylist(playlistContextMenu.playlist);
        setPlaylistContextMenu(null);
      }}>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/>
          <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/>
        </svg>
        Rename
      </button>
      <button className="context-menu-item" onClick={() => {
        onDeletePlaylist(playlistContextMenu.playlist.id);
        setPlaylistContextMenu(null);
      }}>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
          <polyline points="3 6 5 6 21 6"/>
          <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>
        </svg>
        Delete
      </button>
    </div>
  </>
)}
```

- [ ] **Step 4: Verify build**

```bash
cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer && npx vite build 2>&1 | tail -5
```

---

### Task 9: Update Library with playlist context menu options

**Files:**
- Modify: `src/components/Library.jsx`

- [ ] **Step 1: Update imports and props**

Add import at top:

```jsx
import PlaylistMenu from './PlaylistMenu';
```

Change function signature:

```jsx
export default function Library({
  tracks, onPlay, currentTrack, isPlaying, sortBy, sortDir, onSort, onTracksChanged,
  activePlaylistId, playlists, onAddToPlaylist, onRemoveFromPlaylist, onCreatePlaylistForTrack,
}) {
```

Add submenu state alongside existing state:

```jsx
const [playlistSubmenu, setPlaylistSubmenu] = useState(null); // { track, x, y }
```

- [ ] **Step 2: Add "Add to Playlist" and "Remove from Playlist" to context menu**

In the existing context menu JSX (after the "Edit Metadata" button, before "Delete Track"), add:

```jsx
<button
  className="context-menu-item"
  onClick={(e) => {
    const rect = e.currentTarget.getBoundingClientRect();
    setPlaylistSubmenu({ track: contextMenu.track, x: rect.right + 4, y: rect.top });
  }}
>
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <line x1="12" y1="5" x2="12" y2="19"/>
    <line x1="5" y1="12" x2="19" y2="12"/>
  </svg>
  Add to Playlist
</button>
```

And after "Delete Track", add conditional "Remove from Playlist":

```jsx
{activePlaylistId !== null && (
  <button className="context-menu-item" onClick={handleRemoveFromPlaylist}>
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
      <line x1="18" y1="6" x2="6" y2="18"/>
      <line x1="6" y1="6" x2="18" y2="18"/>
    </svg>
    Remove from Playlist
  </button>
)}
```

- [ ] **Step 3: Add handleRemoveFromPlaylist handler**

Add before the return statement:

```jsx
const handleRemoveFromPlaylist = async () => {
  if (contextMenu && activePlaylistId !== null) {
    onRemoveFromPlaylist(contextMenu.track.id);
    setContextMenu(null);
  }
};
```

- [ ] **Step 4: Render PlaylistMenu**

Add after the context menu JSX and before the Edit modal:

```jsx
{playlistSubmenu && (
  <PlaylistMenu
    track={playlistSubmenu.track}
    playlists={playlists}
    onAdd={(playlistId, trackId) => {
      onAddToPlaylist(playlistId, trackId);
      setPlaylistSubmenu(null);
    }}
    onCreateNew={() => {
      setContextMenu(null);
      onCreatePlaylistForTrack(playlistSubmenu.track);
      setPlaylistSubmenu(null);
    }}
    onClose={() => setPlaylistSubmenu(null)}
    position={{ x: playlistSubmenu.x, y: playlistSubmenu.y }}
  />
)}
```

- [ ] **Step 5: Verify build**

```bash
cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer && npx vite build 2>&1 | tail -5
```

---

### Task 10: Add all CSS styles

**Files:**
- Modify: `src/App.css`

- [ ] **Step 1: Add play mode buttons — PlayerBar compact styles**

Add after the `.volume-slider::-webkit-slider-thumb:hover` block (~line 850):

```css
/* ── Play Mode Buttons (PlayerBar compact) ── */

.play-mode-btns {
  display: flex;
  align-items: center;
  gap: 1px;
}

.play-mode-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 26px;
  height: 26px;
  border: none;
  background: transparent;
  color: var(--gl-text-tertiary);
  cursor: pointer;
  border-radius: var(--gl-radius-sm);
  transition: color 0.12s, background 0.12s;
}

.play-mode-btn:hover {
  color: var(--gl-text-secondary);
  background: var(--gl-border-light);
}

.play-mode-btn--active {
  color: var(--gl-orange);
}

.play-mode-btn--active:hover {
  color: var(--gl-orange-hover);
}
```

- [ ] **Step 2: Add play mode buttons — NowPlaying full styles**

Add after the `.np-ctrl-btn--play:hover` block (~line 1163):

```css
/* ── Play Mode (NowPlaying) ── */

.np-play-mode {
  display: flex;
  justify-content: center;
  margin-bottom: 32px;
}
```

- [ ] **Step 3: Add sidebar playlists section styles**

Add after the `.sidebar-footer` block (~line 250):

```css
/* ── Sidebar Playlists ── */

.sidebar-playlists {
  flex: 1;
  display: flex;
  flex-direction: column;
  min-height: 0;
  -webkit-app-region: no-drag;
}

.sidebar-playlists-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 8px 22px 2px;
}

.sidebar-playlists-label {
  font-size: 10px;
  font-weight: 600;
  color: #8c8c93;
  text-transform: uppercase;
  letter-spacing: 0.08em;
}

.sidebar-playlists-add {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 20px;
  height: 20px;
  border: none;
  background: transparent;
  color: #8c8c93;
  cursor: pointer;
  border-radius: var(--gl-radius-sm);
  transition: color 0.12s, background 0.12s;
}

.sidebar-playlists-add:hover {
  color: #d4d4d8;
  background: var(--gl-sidebar-hover);
}

.sidebar-playlists-list {
  display: flex;
  flex-direction: column;
  gap: 2px;
  padding: 4px 10px 8px;
  overflow-y: auto;
  flex: 1;
}
```

- [ ] **Step 4: Add submenu styles**

Add after the `.context-menu-item:hover` block (~line 1834):

```css
/* ── Playlist Submenu ── */

.context-menu-divider {
  height: 1px;
  background: var(--gl-border-light);
  margin: 4px;
}

.submenu-empty {
  padding: 8px 12px;
  font-size: 12px;
  color: var(--gl-text-tertiary);
}

.submenu-new {
  color: var(--gl-orange);
}

.submenu-new:hover {
  background: var(--gl-orange-light);
  color: var(--gl-orange-hover);
}

.playlist-submenu {
  min-width: 180px;
}
```

- [ ] **Step 5: Verify full build**

```bash
cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer && npx vite build 2>&1 | tail -5
```

Expected: Build succeeds with no errors or warnings.

---

### Task 11: Final integration test

- [ ] **Step 1: Launch the app**

```bash
cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer && npx electron . 2>&1 | head -20
```

- [ ] **Step 2: Manual verification checklist**

1. **Play modes in PlayerBar:** Click each mode button (List Loop / Repeat One / Shuffle). Verify active state changes with orange highlight.
2. **Play modes in NowPlaying:** Navigate to Now Playing, verify mode buttons there sync with PlayerBar. Switch modes from NowPlaying, verify PlayerBar updates.
3. **HandleNext — sequential:** Play a track, let it finish. Verify it advances to next track. At end of queue, verify it loops to first track.
4. **HandleNext — repeat-one:** Enable repeat-one. Let track play to end. Verify it replays from start.
5. **HandleNext — shuffle:** Enable shuffle. Play tracks. Verify order is randomized. At end of shuffled queue, verify re-shuffle.
6. **Playlist create:** Click "+" in sidebar playlists. Enter name, click Create. Verify playlist appears in sidebar.
7. **Add track to playlist:** Right-click a track in Library, click "Add to Playlist", select a playlist. Verify no errors in console.
8. **View playlist:** Click a playlist in sidebar. Verify Library shows playlist name in top bar and correct tracks.
9. **Remove from playlist:** Right-click track in playlist view, click "Remove from Playlist". Verify track disappears.
10. **Rename playlist:** Right-click playlist in sidebar, click Rename. Enter new name. Verify it updates.
11. **Delete playlist:** Right-click playlist in sidebar, click Delete. Verify it disappears from sidebar and view resets to All Tracks if it was active.

- [ ] **Step 3: Check for console errors**

Open DevTools (Cmd+Opt+I in Electron) and verify no errors appear during all the above operations.

---

## Self-Review Checklist

- [x] Spec coverage: Every spec requirement maps to a task (modes → Tasks 4,6,7; playlists → Tasks 1,2,3,5,8,9; styles → Task 10)
- [x] No placeholders: All steps have complete code
- [x] Type consistency: Props match across all component calls (playMode, playlists, activePlaylistId, etc.)
- [x] Internal consistency: handleNext rewrite in Task 4 compatible with UI in Tasks 6,7; playlist state in Task 5 compatible with Sidebar (Task 8) and Library (Task 9)
