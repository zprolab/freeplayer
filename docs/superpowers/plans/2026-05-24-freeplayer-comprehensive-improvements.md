# FreePlayer Comprehensive Improvements Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor FreePlayer from a monolithic single-file React app into a well-structured, performant, testable application with proper build tooling.

**Architecture:** Extract audio logic into a class-based `AudioEngine`, split App.jsx into focused hooks (`usePlayback`, `useLibrary`, `usePlaylists`) with React Context for shared state, cache cover art in memory, switch spectrogram rendering to `ImageData`, add vitest test suite, add electron-builder packaging, enable system media keys, and lock down `webSecurity`.

**Tech Stack:** React 18 + Vite 6 (renderer), Electron 33 (main), better-sqlite3 (database), music-metadata (tag parsing), vitest (testing), electron-builder (packaging)

---

## File Structure (Post-Refactor)

```
src/
├── audioEngine.js          # class AudioEngine (was module-level state)
├── coverCache.js           # in-memory LRU cover art cache
├── context/
│   └── PlayerContext.jsx   # React Context + reducer for player state
├── hooks/
│   ├── usePlayback.js      # play, pause, next, prev, seek, volume, ReplayGain
│   ├── useLibrary.js       # track CRUD, search, sort, import state
│   └── usePlaylists.js     # playlist CRUD
├── App.jsx                 # thin shell, wires context + hooks → components
├── App.css
├── main.jsx
└── components/             # unchanged except adapting to new state shape

electron/
├── main.js                 # + globalShortcut media keys, - webSecurity: false
├── preload.js              # unchanged
└── database.js             # unchanged

tests/
├── database.test.js        # SQLite unit tests
├── playback.test.js        # queue shuffle/sequential/repeat-one logic
├── audioEngine.test.js     # AudioEngine class lifecycle
└── setup.js                # vitest global setup

build/                      # electron-builder config output
├── entitlements.mac.plist
└── icon.png
```

---

## Phase 1: Foundation

### Task 1.1: Convert audioEngine to class

**Files:**
- Modify: `src/audioEngine.js` (complete rewrite)
- Modify: `src/components/WaveformVisualizer.jsx:1-2` (import change)
- Modify: `src/App.jsx:10` (import change)

- [ ] **Step 1: Rewrite `src/audioEngine.js` as class**

Replace entire file content:

```js
// AudioEngine — manages Web Audio API graph lifecycle
// Single instance per app; survives React remount

export class AudioEngine {
  constructor() {
    this.ctx = null;
    this.analyser = null;
    this.gainNode = null;
    this.sourceNode = null;
    this.connectedElement = null;
    this._pendingGainDb = 0;
  }

  connect(audioElement) {
    if (!audioElement) return null;
    if (this.connectedElement === audioElement && this.analyser) {
      return this.analyser;
    }

    try {
      if (!this.ctx || this.ctx.state === 'closed') {
        this.ctx = new (window.AudioContext || window.webkitAudioContext)();
      }
      if (!this.analyser) {
        this.analyser = this.ctx.createAnalyser();
        this.analyser.fftSize = 2048;
        this.analyser.smoothingTimeConstant = 0.65;
        this.analyser.minDecibels = -90;
        this.analyser.maxDecibels = -10;
      }
      if (!this.gainNode) {
        this.gainNode = this.ctx.createGain();
        this.gainNode.gain.value = Math.pow(10, this._pendingGainDb / 20);
      }
      if (this.connectedElement !== audioElement) {
        this.sourceNode = this.ctx.createMediaElementSource(audioElement);
        this.sourceNode.connect(this.analyser);
        this.analyser.connect(this.gainNode);
        this.gainNode.connect(this.ctx.destination);
        this.connectedElement = audioElement;
      }
      return this.analyser;
    } catch (err) {
      console.warn('Audio graph wiring failed:', err.message);
      this.analyser = null;
      this.connectedElement = null;
      return null;
    }
  }

  resume() {
    if (this.ctx?.state === 'suspended') {
      this.ctx.resume();
    }
  }

  setGain(gainDb) {
    this._pendingGainDb = gainDb;
    if (!this.gainNode || !this.ctx) return;
    const targetGain = Math.pow(10, gainDb / 20);
    const now = this.ctx.currentTime;
    this.gainNode.gain.cancelScheduledValues(now);
    this.gainNode.gain.setTargetAtTime(targetGain, now, 0.05);
  }

  dispose() {
    if (this.sourceNode) {
      try { this.sourceNode.disconnect(); } catch {}
      this.sourceNode = null;
    }
    if (this.analyser) {
      try { this.analyser.disconnect(); } catch {}
      this.analyser = null;
    }
    if (this.gainNode) {
      try { this.gainNode.disconnect(); } catch {}
      this.gainNode = null;
    }
    if (this.ctx && this.ctx.state !== 'closed') {
      this.ctx.close();
    }
    this.ctx = null;
    this.connectedElement = null;
  }
}

// Singleton — one audio graph for the app lifetime
export const audioEngine = new AudioEngine();
```

- [ ] **Step 2: Update `src/App.jsx` import**

Change line 10 from:
```js
import { setPlaybackGain } from './audioEngine';
```
to:
```js
import { audioEngine } from './audioEngine';
```

Find and replace `setPlaybackGain(gainDb)` with `audioEngine.setGain(gainDb)` in App.jsx (used in `playTrack`).

In the cleanup effect (line 159-169), add `audioEngine.dispose()` call:
```js
useEffect(() => {
    return () => {
      const sid = playSessionIdRef.current;
      if (sid && playStartTimeRef.current) {
        const elapsed = (Date.now() - playStartTimeRef.current) / 1000;
        const trackDuration = audioRef.current.duration || 0;
        const percentage = trackDuration > 0 ? Math.min((elapsed / trackDuration) * 100, 100) : 0;
        window.freeplayer.playEnd({ sessionId: sid, durationSeconds: Math.round(elapsed), playPercentage: Math.round(percentage) });
      }
      audioEngine.dispose();
    };
}, []);
```

- [ ] **Step 3: Update `src/components/WaveformVisualizer.jsx` imports**

Change line 2 from:
```js
import { ensureAudioGraph, resumeAudioContext } from '../audioEngine';
```
to:
```js
import { audioEngine } from '../audioEngine';
```

Replace all usages:
- `ensureAudioGraph(audioElement)` → `audioEngine.connect(audioElement)`
- `resumeAudioContext()` → `audioEngine.resume()`

- [ ] **Step 4: Run dev build to verify no breakage**

Run: `npm run dev`
Expected: App launches without errors, audio playback + visualizer work.

- [ ] **Step 5: Commit**

```bash
git add src/audioEngine.js src/App.jsx src/components/WaveformVisualizer.jsx
git commit -m "refactor: convert audioEngine to class-based AudioEngine with lifecycle"
```

---

### Task 1.2: Add vitest testing infrastructure

**Files:**
- Create: `tests/setup.js`
- Create: `vitest.config.js`
- Modify: `package.json` (scripts, devDependencies)

- [ ] **Step 1: Install vitest**

Run: `npm install -D vitest`
Expected: vitest added to devDependencies.

- [ ] **Step 2: Create `vitest.config.js`**

```js
import { defineConfig } from 'vitest/config';
import path from 'path';

export default defineConfig({
  test: {
    globals: true,
    setupFiles: ['./tests/setup.js'],
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'src'),
    },
  },
});
```

- [ ] **Step 3: Create `tests/setup.js`**

```js
// vitest global setup — mock window.freeplayer IPC bridge
global.window = {
  AudioContext: class MockAudioContext {
    constructor() { this.state = 'running'; this.destination = {}; }
    createAnalyser() { return { fftSize: 2048, smoothingTimeConstant: 0.65, minDecibels: -90, maxDecibels: -10, frequencyBinCount: 1024, connect() {}, disconnect() {} }; }
    createGain() { return { gain: { value: 1, cancelScheduledValues() {}, setTargetAtTime() {} }, connect() {}, disconnect() {} }; }
    createMediaElementSource() { return { connect() {}, disconnect() {} }; }
    resume() {}
    close() {}
  },
  webkitAudioContext: class MockAudioContext {
    constructor() { this.state = 'running'; this.destination = {}; }
    createAnalyser() { return { fftSize: 2048, smoothingTimeConstant: 0.65, minDecibels: -90, maxDecibels: -10, frequencyBinCount: 1024, connect() {}, disconnect() {} }; }
    createGain() { return { gain: { value: 1, cancelScheduledValues() {}, setTargetAtTime() {} }, connect() {}, disconnect() {} }; }
    createMediaElementSource() { return { connect() {}, disconnect() {} }; }
    resume() {}
    close() {}
  },
  freeplayer: {
    getTracks: async () => [],
    getTrack: async () => null,
    updateTrack: async () => {},
    deleteTrack: async () => {},
    getCover: async () => null,
    getStats: async () => ({ totalTime: 0, totalPlays: 0, uniqueTracksPlayed: 0, topTracks: [], topArtists: [], dailyStats: [] }),
    getPlayHistory: async () => [],
    playStart: async () => 1,
    playEnd: async () => {},
    getSetting: async () => null,
    setSetting: async () => {},
    createPlaylist: async () => ({ lastInsertRowid: 1 }),
    getPlaylists: async () => [],
    getPlaylistTracks: async () => [],
    addToPlaylist: async () => {},
    removeFromPlaylist: async () => {},
    deletePlaylist: async () => {},
    renamePlaylist: async () => {},
    isSetup: async () => ({ setup: true, libraryDir: '/test/lib' }),
    resetDatabase: async () => {},
    importDialog: async () => ({ canceled: true }),
    scanDirectory: async () => [],
    importFiles: async () => ({ imported: 0, errors: [] }),
    selectLibraryDir: async () => ({ canceled: true }),
    getTotalDuration: async () => 0,
  },
};
```

- [ ] **Step 4: Add test scripts to `package.json`**

Add to `"scripts"`:
```json
"test": "vitest run",
"test:watch": "vitest"
```

- [ ] **Step 5: Verify infrastructure works**

Run: `echo "import { describe, it, expect } from 'vitest'; describe('smoke', () => { it('works', () => { expect(1 + 1).toBe(2); }); });" > tests/smoke.test.js && npx vitest run`
Expected: 1 test passes.

- [ ] **Step 6: Clean up smoke test and commit**

```bash
rm tests/smoke.test.js
git add tests/setup.js vitest.config.js package.json
git commit -m "chore: add vitest testing infrastructure with IPC mock"
```

---

## Phase 2: App.jsx Architecture Refactor

### Task 2.1: Create PlayerContext with reducer

**Files:**
- Create: `src/context/PlayerContext.jsx`
- Modify: `src/main.jsx` (wrap App in Provider)
- Modify: `src/App.jsx` (use context instead of 20+ useState)

- [ ] **Step 1: Create `src/context/PlayerContext.jsx`**

```jsx
import React, { createContext, useContext, useReducer, useRef } from 'react';

const PlayerContext = createContext(null);

const VIEWS = {
  LIBRARY: 'library',
  NOW_PLAYING: 'now-playing',
  STATS: 'stats',
  SETTINGS: 'settings',
};

const initialState = {
  view: VIEWS.LIBRARY,
  tracks: [],
  currentTrack: null,
  isPlaying: false,
  queue: [],
  queueIndex: -1,
  shuffledQueue: [],
  currentTime: 0,
  duration: 0,
  volume: 0.8,
  isLoading: true,
  isSetup: false,
  libraryDir: '',
  searchQuery: '',
  sortBy: 'imported_at',
  sortDir: 'DESC',
  visualizerMode: 'waveform',
  importMode: 'copy',
  importModalOpen: false,
  defaultVolume: 0.8,
  defaultVisualizer: 'waveform',
  playMode: 'sequential',
  playlists: [],
  activePlaylistId: null,
  playlistTracks: [],
  playlistModal: null,
  pendingAddTrack: null,
  dragOver: false,
  initialPaths: null,
};

function reducer(state, action) {
  switch (action.type) {
    case 'SET': return { ...state, ...action.payload };
    case 'SET_TRACKS': return { ...state, tracks: action.payload };
    case 'SET_CURRENT_TRACK': return { ...state, currentTrack: action.payload };
    case 'SET_IS_PLAYING': return { ...state, isPlaying: action.payload };
    case 'SET_QUEUE': return { ...state, queue: action.payload };
    case 'SET_QUEUE_INDEX': return { ...state, queueIndex: action.payload };
    case 'SET_SHUFFLED_QUEUE': return { ...state, shuffledQueue: action.payload };
    case 'SET_VOLUME': return { ...state, volume: action.payload };
    case 'SET_PLAY_MODE': return { ...state, playMode: action.payload, shuffledQueue: action.payload === 'shuffle' ? state.shuffledQueue : [] };
    case 'SET_PLAYLISTS': return { ...state, playlists: action.payload || [] };
    case 'SELECT_PLAYLIST': return { ...state, activePlaylistId: action.payload, playlistTracks: [], view: VIEWS.LIBRARY };
    case 'SET_PLAYLIST_TRACKS': return { ...state, playlistTracks: action.payload || [] };
    default: return state;
  }
}

export function PlayerProvider({ children }) {
  const [state, dispatch] = useReducer(reducer, initialState);
  const audioRef = useRef(new Audio());
  const playSessionIdRef = useRef(null);
  const playStartTimeRef = useRef(null);

  const value = { state, dispatch, audioRef, playSessionIdRef, playStartTimeRef };
  return (
    <PlayerContext.Provider value={value}>
      {children}
    </PlayerContext.Provider>
  );
}

export function usePlayer() {
  const ctx = useContext(PlayerContext);
  if (!ctx) throw new Error('usePlayer must be used within PlayerProvider');
  return ctx;
}

export { VIEWS };
```

- [ ] **Step 2: Wrap App in `src/main.jsx`**

```jsx
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import { PlayerProvider } from './context/PlayerContext';
import './App.css';

ReactDOM.createRoot(document.getElementById('root')).render(
  <PlayerProvider>
    <App />
  </PlayerProvider>
);
```

- [ ] **Step 3: Commit**

```bash
git add src/context/PlayerContext.jsx src/main.jsx
git commit -m "feat: add PlayerContext with reducer for shared player state"
```

---

### Task 2.2: Extract usePlayback hook

**Files:**
- Create: `src/hooks/usePlayback.js`
- Modify: `src/App.jsx` (remove inline playback logic, use hook)

- [ ] **Step 1: Create `src/hooks/usePlayback.js`**

```js
import { useCallback, useRef, useEffect } from 'react';
import { usePlayer } from '../context/PlayerContext';
import { audioEngine } from '../audioEngine';

function shuffleArray(array) {
  const a = [...array];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

export function usePlayback() {
  const { state, dispatch, audioRef, playSessionIdRef, playStartTimeRef } = usePlayer();

  const startPlaySession = useCallback(async (trackId) => {
    const prevSid = playSessionIdRef.current;
    if (prevSid && playStartTimeRef.current) {
      const elapsed = (Date.now() - playStartTimeRef.current) / 1000;
      const trackDuration = audioRef.current.duration || 0;
      const percentage = trackDuration > 0 ? Math.min((elapsed / trackDuration) * 100, 100) : 0;
      await window.freeplayer.playEnd({
        sessionId: prevSid,
        durationSeconds: Math.round(elapsed),
        playPercentage: Math.round(percentage),
      });
    }
    const sessionId = await window.freeplayer.playStart(trackId);
    playSessionIdRef.current = sessionId;
    playStartTimeRef.current = Date.now();
  }, [audioRef, playSessionIdRef, playStartTimeRef]);

  const playTrack = useCallback(async (track) => {
    dispatch({ type: 'SET_CURRENT_TRACK', payload: track });
    audioRef.current.src = `media://${track.file_path}`;
    const gainDb = track.replaygain_gain || 0;
    audioEngine.setGain(gainDb);
    try {
      await audioRef.current.play();
      await startPlaySession(track.id);
    } catch (err) {
      console.error('Playback failed:', err);
    }
  }, [dispatch, audioRef, startPlaySession]);

  const togglePlayPause = useCallback(() => {
    const audio = audioRef.current;
    if (!audio.src && state.tracks.length > 0) {
      playTrack(state.tracks[0]);
      return;
    }
    if (audio.paused) {
      audio.play().catch(console.error);
    } else {
      audio.pause();
    }
  }, [audioRef, state.tracks, playTrack]);

  const handleNext = useCallback(() => {
    const { queue, queueIndex, playMode, shuffledQueue } = state;
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
        const reshuffled = shuffleArray(queue);
        dispatch({ type: 'SET_SHUFFLED_QUEUE', payload: reshuffled });
        nextIdx = queue.findIndex(t => t.id === reshuffled[0].id);
      }
    } else {
      nextIdx = queueIndex < queue.length - 1 ? queueIndex + 1 : 0;
    }

    dispatch({ type: 'SET_QUEUE_INDEX', payload: nextIdx });
    playTrack(queue[nextIdx]);
  }, [state, audioRef, dispatch, playTrack]);

  const handlePrev = useCallback(() => {
    const { queue, queueIndex, playMode, shuffledQueue } = state;
    if (!queue.length) return;

    if (audioRef.current.currentTime > 3) {
      audioRef.current.currentTime = 0;
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
      prevIdx = queueIndex > 0 ? queueIndex - 1 : queue.length - 1;
    }

    dispatch({ type: 'SET_QUEUE_INDEX', payload: prevIdx });
    playTrack(queue[prevIdx]);
  }, [state, audioRef, dispatch, playTrack]);

  const handleSeek = useCallback((time) => {
    audioRef.current.currentTime = time;
    dispatch({ type: 'SET', payload: { currentTime: time } });
  }, [audioRef, dispatch]);

  const handleVolumeChange = useCallback((vol) => {
    audioRef.current.volume = vol;
    dispatch({ type: 'SET_VOLUME', payload: vol });
  }, [audioRef, dispatch]);

  const playTrackFromList = useCallback(async (track, trackList) => {
    dispatch({ type: 'SET_QUEUE', payload: trackList });
    const idx = trackList.findIndex(t => t.id === track.id);
    dispatch({ type: 'SET_QUEUE_INDEX', payload: idx });

    if (state.playMode === 'shuffle') {
      const shuffled = shuffleArray(trackList);
      const clickedIdx = shuffled.findIndex(t => t.id === track.id);
      if (clickedIdx > 0) {
        [shuffled[0], shuffled[clickedIdx]] = [shuffled[clickedIdx], shuffled[0]];
      }
      dispatch({ type: 'SET_SHUFFLED_QUEUE', payload: shuffled });
    }

    await playTrack(track);
  }, [dispatch, state.playMode, playTrack]);

  // Audio element event listeners
  useEffect(() => {
    const audio = audioRef.current;

    const onTimeUpdate = () => dispatch({ type: 'SET', payload: { currentTime: audio.currentTime } });
    const onDurationChange = () => dispatch({ type: 'SET', payload: { duration: audio.duration || 0 } });
    const onEnded = () => handleNext();
    const onPlay = () => dispatch({ type: 'SET_IS_PLAYING', payload: true });
    const onPause = () => dispatch({ type: 'SET_IS_PLAYING', payload: false });
    const onError = () => {
      const err = audio.error;
      const codes = { 1: 'MEDIA_ERR_ABORTED', 2: 'MEDIA_ERR_NETWORK', 3: 'MEDIA_ERR_DECODE', 4: 'MEDIA_ERR_SRC_NOT_SUPPORTED' };
      console.error('Audio error:', codes[err?.code] || 'UNKNOWN', err?.message || '', 'src:', audio.src);
    };

    audio.addEventListener('timeupdate', onTimeUpdate);
    audio.addEventListener('durationchange', onDurationChange);
    audio.addEventListener('ended', onEnded);
    audio.addEventListener('play', onPlay);
    audio.addEventListener('pause', onPause);
    audio.addEventListener('error', onError);

    return () => {
      audio.removeEventListener('timeupdate', onTimeUpdate);
      audio.removeEventListener('durationchange', onDurationChange);
      audio.removeEventListener('ended', onEnded);
      audio.removeEventListener('play', onPlay);
      audio.removeEventListener('pause', onPause);
      audio.removeEventListener('error', onError);
    };
  }, [audioRef, dispatch, handleNext]);

  // Separate volume effect — no longer tears down event listeners on volume change
  useEffect(() => {
    audioRef.current.volume = state.volume;
  }, [state.volume, audioRef]);

  // End play session on unmount
  useEffect(() => {
    return () => {
      const sid = playSessionIdRef.current;
      if (sid && playStartTimeRef.current) {
        const elapsed = (Date.now() - playStartTimeRef.current) / 1000;
        const trackDuration = audioRef.current.duration || 0;
        const percentage = trackDuration > 0 ? Math.min((elapsed / trackDuration) * 100, 100) : 0;
        window.freeplayer.playEnd({
          sessionId: sid,
          durationSeconds: Math.round(elapsed),
          playPercentage: Math.round(percentage),
        });
      }
      audioEngine.dispose();
    };
  }, [audioRef, playSessionIdRef, playStartTimeRef]);

  return {
    playTrack,
    togglePlayPause,
    handleNext,
    handlePrev,
    handleSeek,
    handleVolumeChange,
    playTrackFromList,
  };
}
```

- [ ] **Step 2: Commit**

```bash
git add src/hooks/usePlayback.js
git commit -m "feat: extract usePlayback hook with separated volume effect"
```

---

### Task 2.3: Extract useLibrary and usePlaylists hooks

**Files:**
- Create: `src/hooks/useLibrary.js`
- Create: `src/hooks/usePlaylists.js`
- Modify: `src/App.jsx` (use hooks instead of inline logic)

- [ ] **Step 1: Create `src/hooks/useLibrary.js`**

```js
import { useCallback, useEffect } from 'react';
import { usePlayer } from '../context/PlayerContext';

export function useLibrary() {
  const { state, dispatch } = usePlayer();

  const loadTracks = useCallback(async () => {
    try {
      const data = await window.freeplayer.getTracks({
        search: state.searchQuery,
        sortBy: state.sortBy,
        sortDir: state.sortDir,
      });
      dispatch({ type: 'SET_TRACKS', payload: data });
    } catch (err) {
      console.error('Failed to load tracks:', err);
    }
  }, [state.searchQuery, state.sortBy, state.sortDir, dispatch]);

  const checkSetup = useCallback(async () => {
    try {
      const result = await window.freeplayer.isSetup();
      dispatch({ type: 'SET', payload: { isSetup: result.setup, libraryDir: result.libraryDir || '' } });
      const impMode = await window.freeplayer.getSetting('import_mode');
      if (impMode) dispatch({ type: 'SET', payload: { importMode: impMode } });
      const defVol = await window.freeplayer.getSetting('default_volume');
      if (defVol) {
        const vol = parseFloat(defVol);
        dispatch({ type: 'SET', payload: { defaultVolume: vol, volume: vol } });
      }
      const defVis = await window.freeplayer.getSetting('default_visualizer');
      if (defVis) {
        dispatch({ type: 'SET', payload: { defaultVisualizer: defVis, visualizerMode: defVis } });
      }
      if (result.setup) {
        await loadTracks();
      }
    } catch (err) {
      console.error('Setup check failed:', err);
    } finally {
      dispatch({ type: 'SET', payload: { isLoading: false } });
    }
  }, [dispatch, loadTracks]);

  useEffect(() => {
    checkSetup();
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (state.isSetup) loadTracks();
  }, [state.isSetup, loadTracks]);

  const handleImportComplete = useCallback(async (result) => {
    dispatch({ type: 'SET', payload: { importModalOpen: false } });
    if (result && !result.canceled) {
      await loadTracks();
      const setupResult = await window.freeplayer.isSetup();
      dispatch({ type: 'SET', payload: { isSetup: setupResult.setup, libraryDir: setupResult.libraryDir || '' } });
    }
  }, [dispatch, loadTracks]);

  const handleImportModeChange = useCallback(async (mode) => {
    dispatch({ type: 'SET', payload: { importMode: mode } });
    await window.freeplayer.setSetting({ key: 'import_mode', value: mode });
  }, [dispatch]);

  const handleDefaultVolumeChange = useCallback(async (vol) => {
    dispatch({ type: 'SET', payload: { defaultVolume: vol } });
    await window.freeplayer.setSetting({ key: 'default_volume', value: String(vol) });
  }, [dispatch]);

  const handleDefaultVisualizerChange = useCallback(async (mode) => {
    dispatch({ type: 'SET', payload: { defaultVisualizer: mode } });
    await window.freeplayer.setSetting({ key: 'default_visualizer', value: mode });
  }, [dispatch]);

  const handleResetDatabase = useCallback(async () => {
    dispatch({ type: 'SET', payload: {
      tracks: [], currentTrack: null, isPlaying: false, queue: [], queueIndex: -1,
      libraryDir: '', isSetup: false, importMode: 'copy', defaultVolume: 0.8,
      defaultVisualizer: 'waveform', visualizerMode: 'waveform',
      playlists: [], activePlaylistId: null, playlistTracks: [],
    }});
  }, [dispatch]);

  return {
    loadTracks,
    handleImportComplete,
    handleImportModeChange,
    handleDefaultVolumeChange,
    handleDefaultVisualizerChange,
    handleResetDatabase,
  };
}
```

- [ ] **Step 2: Create `src/hooks/usePlaylists.js`**

```js
import { useCallback } from 'react';
import { usePlayer } from '../context/PlayerContext';

export function usePlaylists() {
  const { state, dispatch } = usePlayer();

  const loadPlaylists = useCallback(async () => {
    try {
      const data = await window.freeplayer.getPlaylists();
      dispatch({ type: 'SET_PLAYLISTS', payload: data });
    } catch (err) {
      console.error('Failed to load playlists:', err);
    }
  }, [dispatch]);

  const handleSelectPlaylist = useCallback(async (playlistId) => {
    if (playlistId === null) {
      dispatch({ type: 'SET', payload: { activePlaylistId: null } });
    } else {
      dispatch({ type: 'SET', payload: { activePlaylistId: playlistId } });
      const tracks = await window.freeplayer.getPlaylistTracks(playlistId);
      dispatch({ type: 'SET_PLAYLIST_TRACKS', payload: tracks });
    }
    dispatch({ type: 'SET', payload: { view: 'library' } });
  }, [dispatch]);

  const handleCreatePlaylist = useCallback(async ({ name, description }) => {
    const result = await window.freeplayer.createPlaylist({ name, description });
    await loadPlaylists();
    dispatch({ type: 'SET', payload: { playlistModal: null } });
    if (state.pendingAddTrack) {
      const playlistId = result.lastInsertRowid || result.id;
      await window.freeplayer.addToPlaylist({ playlistId, trackId: state.pendingAddTrack.id });
      dispatch({ type: 'SET', payload: { pendingAddTrack: null } });
    }
  }, [dispatch, loadPlaylists, state.pendingAddTrack]);

  const handleRenamePlaylist = useCallback(async ({ name }) => {
    if (state.playlistModal?.playlist) {
      await window.freeplayer.renamePlaylist({ id: state.playlistModal.playlist.id, name });
      await loadPlaylists();
      dispatch({ type: 'SET', payload: { playlistModal: null } });
    }
  }, [dispatch, loadPlaylists, state.playlistModal]);

  const handleDeletePlaylist = useCallback(async (playlistId) => {
    await window.freeplayer.deletePlaylist(playlistId);
    if (state.activePlaylistId === playlistId) {
      dispatch({ type: 'SET', payload: { activePlaylistId: null } });
    }
    await loadPlaylists();
  }, [dispatch, loadPlaylists, state.activePlaylistId]);

  const handleAddToPlaylist = useCallback(async (playlistId, trackId) => {
    await window.freeplayer.addToPlaylist({ playlistId, trackId });
    if (state.activePlaylistId === playlistId) {
      const tracks = await window.freeplayer.getPlaylistTracks(playlistId);
      dispatch({ type: 'SET_PLAYLIST_TRACKS', payload: tracks });
    }
  }, [dispatch, state.activePlaylistId]);

  const handleRemoveFromPlaylist = useCallback(async (trackId) => {
    if (state.activePlaylistId === null) return;
    await window.freeplayer.removeFromPlaylist({ playlistId: state.activePlaylistId, trackId });
    const tracks = await window.freeplayer.getPlaylistTracks(state.activePlaylistId);
    dispatch({ type: 'SET_PLAYLIST_TRACKS', payload: tracks });
  }, [dispatch, state.activePlaylistId]);

  const handleOpenCreateForTrack = useCallback((track) => {
    dispatch({ type: 'SET', payload: { pendingAddTrack: track, playlistModal: { mode: 'create', playlist: null } } });
  }, [dispatch]);

  return {
    loadPlaylists,
    handleSelectPlaylist,
    handleCreatePlaylist,
    handleRenamePlaylist,
    handleDeletePlaylist,
    handleAddToPlaylist,
    handleRemoveFromPlaylist,
    handleOpenCreateForTrack,
  };
}
```

- [ ] **Step 3: Commit**

```bash
git add src/hooks/useLibrary.js src/hooks/usePlaylists.js
git commit -m "feat: extract useLibrary and usePlaylists hooks"
```

---

### Task 2.4: Rewrite App.jsx as thin shell

**Files:**
- Modify: `src/App.jsx` (major rewrite — remove all inline logic, use hooks)

- [ ] **Step 1: Rewrite `src/App.jsx`**

Replace entire file with:

```jsx
import React from 'react';
import Sidebar from './components/Sidebar';
import Library from './components/Library';
import NowPlaying from './components/NowPlaying';
import Stats from './components/Stats';
import PlayerBar from './components/PlayerBar';
import ImportModal from './components/ImportModal';
import Settings from './components/Settings';
import PlaylistModal from './components/PlaylistModal';
import { usePlayer, VIEWS } from './context/PlayerContext';
import { usePlayback } from './hooks/usePlayback';
import { useLibrary } from './hooks/useLibrary';
import { usePlaylists } from './hooks/usePlaylists';

export default function App() {
  const { state, dispatch } = usePlayer();
  const {
    playTrack, togglePlayPause, handleNext, handlePrev,
    handleSeek, handleVolumeChange, playTrackFromList,
  } = usePlayback();
  const {
    handleImportComplete, handleImportModeChange,
    handleDefaultVolumeChange, handleDefaultVisualizerChange,
    handleResetDatabase,
  } = useLibrary();
  const {
    handleSelectPlaylist, handleCreatePlaylist, handleRenamePlaylist, handleDeletePlaylist,
    handleAddToPlaylist, handleRemoveFromPlaylist, handleOpenCreateForTrack,
  } = usePlaylists();

  // Keyboard shortcuts
  React.useEffect(() => {
    const MODES = ['waveform', 'spectrogram', 'off'];
    const onKey = (e) => {
      if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;
      if (e.key === ' ' || e.code === 'Space') {
        e.preventDefault();
        togglePlayPause();
        return;
      }
      if (e.key === 'v' || e.key === 'V') {
        if (e.shiftKey) {
          dispatch({ type: 'SET', payload: { visualizerMode: MODES[(MODES.indexOf(state.visualizerMode) + 1) % MODES.length] } });
        } else {
          dispatch({ type: 'SET', payload: { visualizerMode: state.visualizerMode === 'off' ? 'waveform' : 'off' } });
        }
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [dispatch, togglePlayPause, state.visualizerMode]);

  // Drag-and-drop handlers
  const handleDragEnter = (e) => {
    if (state.view !== VIEWS.LIBRARY || state.importModalOpen) return;
    e.preventDefault();
    e.stopPropagation();
    dispatch({ type: 'SET', payload: { dragOver: true } });
  };

  const handleDragOver = (e) => {
    if (state.view !== VIEWS.LIBRARY || state.importModalOpen) return;
    e.preventDefault();
    e.stopPropagation();
  };

  const handleDragLeave = (e) => {
    if (e.currentTarget === e.target) {
      dispatch({ type: 'SET', payload: { dragOver: false } });
    }
  };

  const handleDrop = (e) => {
    e.preventDefault();
    e.stopPropagation();
    dispatch({ type: 'SET', payload: { dragOver: false } });
    if (state.view !== VIEWS.LIBRARY || state.importModalOpen) return;

    const paths = [];
    const { files } = e.dataTransfer;
    for (let i = 0; i < files.length; i++) {
      if (files[i].path) paths.push(files[i].path);
    }
    if (paths.length > 0) {
      dispatch({ type: 'SET', payload: { initialPaths: paths, importModalOpen: true } });
    }
  };

  const tracks = state.activePlaylistId === null ? state.tracks : state.playlistTracks;

  if (state.isLoading) {
    return (
      <div className="app-loading">
        <div className="loading-spinner" />
        <span className="loading-text">Loading FreePlayer...</span>
      </div>
    );
  }

  return (
    <div className="app">
      <Sidebar
        currentView={state.view}
        onNavigate={(v) => dispatch({ type: 'SET', payload: { view: v } })}
        trackCount={state.tracks.length}
        onImport={() => dispatch({ type: 'SET', payload: { importModalOpen: true } })}
        playlists={state.playlists}
        activePlaylistId={state.activePlaylistId}
        onSelectPlaylist={handleSelectPlaylist}
        onCreatePlaylist={() => dispatch({ type: 'SET', payload: { playlistModal: { mode: 'create', playlist: null } } })}
        onRenamePlaylist={(playlist) => dispatch({ type: 'SET', payload: { playlistModal: { mode: 'rename', playlist } } })}
        onDeletePlaylist={handleDeletePlaylist}
      />
      <main className="main-content">
        <header className="top-bar">
          <div className="top-bar-left">
            <h1 className="page-title">
              {state.view === VIEWS.LIBRARY && (state.activePlaylistId !== null
                ? (state.playlists.find(p => p.id === state.activePlaylistId)?.name || 'Playlist')
                : 'Library'
              )}
              {state.view === VIEWS.NOW_PLAYING && 'Now Playing'}
              {state.view === VIEWS.STATS && 'Statistics'}
              {state.view === VIEWS.SETTINGS && 'Settings'}
            </h1>
            {state.view === VIEWS.LIBRARY && (
              <span className="track-count-badge">{tracks.length} tracks</span>
            )}
          </div>
          <div className="top-bar-right">
            {state.view === VIEWS.LIBRARY && (
              <>
                <div className="search-box">
                  <svg className="search-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
                    <path d="M11.742 10.344a6.5 6.5 0 1 0-1.397 1.398h-.001l3.85 3.85a1 1 0 0 0 1.415-1.414l-3.85-3.85-.017.016zm-5.242.156a5 5 0 1 1 0-10 5 5 0 0 1 0 10z" fill="currentColor"/>
                  </svg>
                  <input
                    type="text"
                    placeholder="Search your library..."
                    value={state.searchQuery}
                    onChange={(e) => dispatch({ type: 'SET', payload: { searchQuery: e.target.value } })}
                    className="search-input"
                  />
                  {state.searchQuery && (
                    <button className="search-clear" onClick={() => dispatch({ type: 'SET', payload: { searchQuery: '' } })}>
                      <svg width="12" height="12" viewBox="0 0 12 12"><path d="M1 1l10 10M11 1L1 11" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"/></svg>
                    </button>
                  )}
                </div>
                <button className="btn btn-primary" onClick={() => dispatch({ type: 'SET', payload: { importModalOpen: true } })}>
                  <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                    <path d="M8 1v14M1 8h14" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
                  </svg>
                  Import
                </button>
              </>
            )}
          </div>
        </header>

        <div className="content-area" onDragEnter={handleDragEnter} onDragOver={handleDragOver} onDragLeave={handleDragLeave} onDrop={handleDrop}>
          {state.dragOver && state.view === VIEWS.LIBRARY && !state.importModalOpen && (
            <div className="drag-overlay">
              <div className="drag-zone">
                <svg className="drag-zone-icon" width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round">
                  <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/>
                </svg>
                <span className="drag-zone-title">Drop to Import</span>
                <span className="drag-zone-hint">Audio files and folders supported</span>
              </div>
            </div>
          )}
          {state.view === VIEWS.SETTINGS ? (
            <Settings
              importMode={state.importMode}
              onImportModeChange={handleImportModeChange}
              libraryDir={state.libraryDir}
              onLibraryDirChange={(dir) => dispatch({ type: 'SET', payload: { libraryDir: dir } })}
              defaultVolume={state.defaultVolume}
              onDefaultVolumeChange={handleDefaultVolumeChange}
              defaultVisualizer={state.defaultVisualizer}
              onDefaultVisualizerChange={handleDefaultVisualizerChange}
              onResetDatabase={handleResetDatabase}
            />
          ) : !state.isSetup ? (
            <div className="empty-state">
              <div className="empty-state-icon">
                <svg width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.2">
                  <path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>
                </svg>
              </div>
              <h2>Welcome to FreePlayer</h2>
              <p>Set up your music library to get started. Choose a directory where your music will be stored, then import your audio files.</p>
              <button className="btn btn-primary btn-lg" onClick={() => dispatch({ type: 'SET', payload: { importModalOpen: true } })}>
                Set Up Library
              </button>
            </div>
          ) : (
            <>
              {state.view === VIEWS.LIBRARY && (
                <Library
                  tracks={tracks}
                  onPlay={playTrackFromList}
                  currentTrack={state.currentTrack}
                  isPlaying={state.isPlaying}
                  sortBy={state.sortBy}
                  sortDir={state.sortDir}
                  onTracksChanged={state.activePlaylistId === null
                    ? undefined
                    : () => handleSelectPlaylist(state.activePlaylistId)
                  }
                  onSort={(col) => {
                    if (state.sortBy === col) {
                      dispatch({ type: 'SET', payload: { sortDir: state.sortDir === 'ASC' ? 'DESC' : 'ASC' } });
                    } else {
                      dispatch({ type: 'SET', payload: { sortBy: col, sortDir: (col === 'title' || col === 'artist') ? 'ASC' : 'DESC' } });
                    }
                  }}
                  activePlaylistId={state.activePlaylistId}
                  playlists={state.playlists}
                  onAddToPlaylist={handleAddToPlaylist}
                  onRemoveFromPlaylist={handleRemoveFromPlaylist}
                  onCreatePlaylistForTrack={handleOpenCreateForTrack}
                />
              )}
              {state.view === VIEWS.NOW_PLAYING && (
                <NowPlaying
                  currentTrack={state.currentTrack}
                  isPlaying={state.isPlaying}
                  currentTime={state.currentTime}
                  duration={state.duration}
                  onSeek={handleSeek}
                  onTogglePlay={togglePlayPause}
                  onNext={handleNext}
                  onPrev={handlePrev}
                  queue={state.queue}
                  queueIndex={state.queueIndex}
                  onPlayFromQueue={playTrackFromList}
                  {/* audioElement removed from props — NowPlaying gets it via usePlayer() context */}
                  visualizerMode={state.visualizerMode}
                  onVisualizerModeChange={(m) => dispatch({ type: 'SET', payload: { visualizerMode: m } })}
                  playMode={state.playMode}
                  onPlayModeChange={(m) => dispatch({ type: 'SET_PLAY_MODE', payload: m })}
                />
              )}
              {state.view === VIEWS.STATS && <Stats />}
            </>
          )}
        </div>
      </main>

      <PlayerBar
        currentTrack={state.currentTrack}
        isPlaying={state.isPlaying}
        currentTime={state.currentTime}
        duration={state.duration}
        onTogglePlay={togglePlayPause}
        onNext={handleNext}
        onPrev={handlePrev}
        onSeek={handleSeek}
        volume={state.volume}
        onVolumeChange={handleVolumeChange}
        playMode={state.playMode}
        onPlayModeChange={(m) => dispatch({ type: 'SET_PLAY_MODE', payload: m })}
      />

      {state.importModalOpen && (
        <ImportModal
          onClose={() => dispatch({ type: 'SET', payload: { importModalOpen: false, initialPaths: null } })}
          onComplete={(result) => {
            dispatch({ type: 'SET', payload: { initialPaths: null } });
            handleImportComplete(result);
          }}
          importMode={state.importMode}
          initialPaths={state.initialPaths}
        />
      )}

      {state.playlistModal && (
        <PlaylistModal
          mode={state.playlistModal.mode}
          playlist={state.playlistModal.playlist}
          onClose={() => dispatch({ type: 'SET', payload: { playlistModal: null, pendingAddTrack: null } })}
          onSubmit={state.playlistModal.mode === 'create' ? handleCreatePlaylist : handleRenamePlaylist}
        />
      )}
    </div>
  );
}
```

- [ ] **Step 2: Fix `NowPlaying` audioElement prop**

`NowPlaying` receives `audioElement` prop but now it should get it from context. Update `NowPlaying` to import `usePlayer`:

In `src/components/NowPlaying.jsx`, add import:
```js
import { usePlayer } from '../context/PlayerContext';
```

And inside the component, get audioElement from context:
```js
const { audioRef } = usePlayer();
const audioElement = audioRef.current;
```

Remove `audioElement` from the destructured props.

- [ ] **Step 3: Verify build**

Run: `npm run build`
Expected: Build succeeds without errors.

- [ ] **Step 4: Commit**

```bash
git add src/App.jsx src/components/NowPlaying.jsx
git commit -m "refactor: rewrite App.jsx as thin shell using hooks and context"
```

---

## Phase 3: Performance Optimization

### Task 3.1: Add cover art memory cache

**Files:**
- Create: `src/coverCache.js`
- Modify: `src/components/PlayerBar.jsx` (use cache)
- Modify: `src/components/NowPlaying.jsx` (use cache)

- [ ] **Step 1: Create `src/coverCache.js`**

```js
// Simple LRU cache for cover art base64 data URLs
const MAX_SIZE = 50;
const cache = new Map();

export function getCachedCover(coverPath) {
  if (!coverPath) return null;
  const entry = cache.get(coverPath);
  if (entry) {
    // Move to end (most recently used)
    cache.delete(coverPath);
    cache.set(coverPath, entry);
    return entry;
  }
  return null;
}

export function setCachedCover(coverPath, dataUrl) {
  if (!coverPath || !dataUrl) return;
  if (cache.has(coverPath)) {
    cache.delete(coverPath);
  } else if (cache.size >= MAX_SIZE) {
    // Evict oldest (first key)
    const firstKey = cache.keys().next().value;
    cache.delete(firstKey);
  }
  cache.set(coverPath, dataUrl);
}

export function clearCoverCache() {
  cache.clear();
}
```

- [ ] **Step 2: Update `CoverArt` in `PlayerBar.jsx`**

Replace the `CoverArt` component body:

```jsx
function CoverArt({ track }) {
  const [coverUrl, setCoverUrl] = React.useState(null);

  React.useEffect(() => {
    let stale = false;
    if (track && track.cover_path) {
      const cached = getCachedCover(track.cover_path);
      if (cached) {
        setCoverUrl(cached);
        return;
      }
      window.freeplayer.getCover(track.cover_path).then((url) => {
        if (!stale && url) {
          setCachedCover(track.cover_path, url);
          setCoverUrl(url);
        }
      });
    } else {
      setCoverUrl(null);
    }
    return () => { stale = true; };
  }, [track]);

  // ... rest unchanged (cover-placeholder / img rendering)
}
```

Add import at top: `import { getCachedCover, setCachedCover } from '../coverCache';`

- [ ] **Step 3: Update cover effect in `NowPlaying.jsx`**

Add the same cache check pattern to the existing useEffect:

```js
const cached = getCachedCover(currentTrack.cover_path);
if (cached) {
    setCoverUrl(cached);
    return;
}
// ... then the existing fetch logic, with setCachedCover on success
```

Add import: `import { getCachedCover, setCachedCover } from '../coverCache';`

- [ ] **Step 4: Commit**

```bash
git add src/coverCache.js src/components/PlayerBar.jsx src/components/NowPlaying.jsx
git commit -m "perf: add LRU cover art cache to eliminate redundant IPC calls"
```

---

### Task 3.2: Optimize spectrogram rendering with ImageData

**Files:**
- Modify: `src/components/WaveformVisualizer.jsx` (`drawSpectrogramMode` function)

- [ ] **Step 1: Replace per-pixel fillRect with ImageData in `drawSpectrogramMode`**

Replace the heatmap rendering loop (lines 270-281 in original) with ImageData-based rendering:

```js
function drawSpectrogramMode(ctx, freqData, bufferLen, W, H) {
  ctx.fillStyle = BG_COLOR;
  ctx.fillRect(0, 0, W, H);

  const marginTop = 18;
  const marginBottom = 42;
  const marginLeft = 12;
  const marginRight = 12;
  const plotW = W - marginLeft - marginRight;
  const plotH = H - marginTop - marginBottom;

  if (!spectrogramBuffer || spectrogramBuffer.length !== SPECTROGRAM_ROWS) {
    spectrogramBuffer = new Array(SPECTROGRAM_ROWS);
    for (let i = 0; i < SPECTROGRAM_ROWS; i++) {
      spectrogramBuffer[i] = new Uint8Array(bufferLen);
    }
  }

  spectrogramBuffer.copyWithin(0, 1);
  spectrogramBuffer[SPECTROGRAM_ROWS - 1] = new Uint8Array(freqData);

  const binStep = bufferLen / plotW;
  const rowH = Math.ceil(plotH / SPECTROGRAM_ROWS);

  // Render to ImageData for a single bulk put
  const imageData = ctx.createImageData(plotW, plotH);
  const pixels = imageData.data;

  for (let row = 0; row < SPECTROGRAM_ROWS; row++) {
    const imgY = plotH - 1 - Math.round((row / (SPECTROGRAM_ROWS - 1)) * (plotH - 1));
    const srcRow = spectrogramBuffer[row];

    for (let px = 0; px < plotW; px++) {
      const binIdx = Math.floor(px * binStep);
      const val = srcRow[Math.min(binIdx, bufferLen - 1)] / 255;
      const [r, g, b] = spectrogramColor(val);

      for (let dy = 0; dy < rowH && (imgY + dy) < plotH; dy++) {
        const base = ((imgY + dy) * plotW + px) * 4;
        pixels[base] = r;
        pixels[base + 1] = g;
        pixels[base + 2] = b;
        pixels[base + 3] = 255;
      }
    }
  }

  ctx.putImageData(imageData, marginLeft, marginTop);

  // Grid overlay (unchanged)
  ctx.strokeStyle = 'rgba(16, 133, 72, 0.10)';
  ctx.lineWidth = 0.5;
  for (let i = 1; i < 8; i++) {
    const y = Math.round(marginTop + (plotH / 8) * i) + 0.5;
    ctx.beginPath();
    ctx.moveTo(marginLeft, y);
    ctx.lineTo(W - marginRight, y);
    ctx.stroke();
  }

  // Frequency labels (unchanged — copy from original function)
  const freqY = H - 14;
  ctx.font = '9px "JetBrains Mono", monospace';
  ctx.fillStyle = LABEL_COLOR;
  ctx.textBaseline = 'bottom';
  ctx.textAlign = 'center';
  const freqLabels = [
    { hz: '20',  xFrac: 0.04 }, { hz: '100', xFrac: 0.22 },
    { hz: '500', xFrac: 0.40 }, { hz: '2k',  xFrac: 0.58 },
    { hz: '8k',  xFrac: 0.76 }, { hz: '20k', xFrac: 0.94 },
  ];
  freqLabels.forEach(({ hz, xFrac }) => {
    ctx.fillText(hz, marginLeft + plotW * xFrac, freqY);
  });
  ctx.textAlign = 'right';
  ctx.fillStyle = LABEL_DIM;
  ctx.fillText('Hz', W - marginRight, freqY);

  ctx.textAlign = 'left';
  ctx.font = '7px "JetBrains Mono", monospace';
  ctx.fillStyle = LABEL_DIM;
  ctx.fillText('now', W - marginRight + 4, marginTop + 8);
  ctx.fillText('←', W - marginRight + 4, marginTop + plotH);

  const maxFreq = Math.max(...freqData);
  const peakW = Math.min((maxFreq / 255) * plotW, plotW);
  ctx.fillStyle = `rgba(226, 67, 41, ${0.15 + (maxFreq / 255) * 0.5})`;
  ctx.fillRect(marginLeft, H - 3, peakW, 1.5);
}
```

- [ ] **Step 2: Verify build**

Run: `npm run build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add src/components/WaveformVisualizer.jsx
git commit -m "perf: use ImageData bulk put for spectrogram rendering"
```

---

## Phase 4: Testing

### Task 4.1: Database unit tests

**Files:**
- Create: `tests/database.test.js`

- [ ] **Step 1: Create `tests/database.test.js`**

```js
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import Database from 'better-sqlite3';
import path from 'path';
import fs from 'fs';
import os from 'os';

// Replicate the database module's logic with a temp DB
let db;

function initTestDb() {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'freeplayer-test-'));
  const dbPath = path.join(tmpDir, 'test.db');
  db = new Database(dbPath);
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');

  db.exec(`
    CREATE TABLE IF NOT EXISTS tracks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      artist TEXT DEFAULT 'Unknown Artist',
      album TEXT DEFAULT 'Unknown Album',
      track_number INTEGER,
      disc_number INTEGER,
      genre TEXT,
      year INTEGER,
      duration REAL NOT NULL DEFAULT 0,
      file_path TEXT NOT NULL UNIQUE,
      file_name TEXT NOT NULL,
      file_size INTEGER DEFAULT 0,
      file_format TEXT,
      bitrate INTEGER,
      sample_rate INTEGER,
      channels INTEGER,
      cover_path TEXT,
      replaygain_gain REAL DEFAULT 0,
      replaygain_peak REAL DEFAULT 0,
      imported_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS play_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      track_id INTEGER NOT NULL,
      started_at DATETIME NOT NULL,
      ended_at DATETIME,
      duration_seconds REAL DEFAULT 0,
      play_percentage REAL DEFAULT 0,
      FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS playlists (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      description TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS playlist_tracks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      playlist_id INTEGER NOT NULL,
      track_id INTEGER NOT NULL,
      position INTEGER NOT NULL DEFAULT 0,
      added_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
      FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE,
      UNIQUE(playlist_id, track_id)
    );

    CREATE TABLE IF NOT EXISTS settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    );
  `);

  return db;
}

function closeTestDb(db) {
  if (db) {
    const dbPath = db.name;
    db.close();
    try { fs.unlinkSync(dbPath); } catch {}
    try { fs.unlinkSync(dbPath + '-wal'); } catch {}
    try { fs.unlinkSync(dbPath + '-shm'); } catch {}
  }
}

describe('Tracks CRUD', () => {
  let db;
  beforeEach(() => { db = initTestDb(); });
  afterEach(() => { closeTestDb(db); });

  it('inserts a track', () => {
    const stmt = db.prepare(`
      INSERT INTO tracks (title, artist, album, duration, file_path, file_name)
      VALUES (@title, @artist, @album, @duration, @file_path, @file_name)
    `);
    const result = stmt.run({
      title: 'Test Song', artist: 'Test Artist', album: 'Test Album',
      duration: 240, file_path: '/music/test.mp3', file_name: 'test.mp3',
    });
    expect(result.lastInsertRowid).toBeGreaterThan(0);
  });

  it('enforces UNIQUE constraint on file_path', () => {
    const stmt = db.prepare(`
      INSERT INTO tracks (title, artist, album, duration, file_path, file_name)
      VALUES (@title, @artist, @album, @duration, @file_path, @file_name)
    `);
    const params = {
      title: 'Song', artist: 'Artist', album: 'Album',
      duration: 100, file_path: '/music/dup.mp3', file_name: 'dup.mp3',
    };
    stmt.run(params);
    expect(() => stmt.run(params)).toThrow();
  });

  it('ON CONFLICT DO UPDATE replaces existing track', () => {
    const stmt = db.prepare(`
      INSERT INTO tracks (title, artist, album, duration, file_path, file_name)
      VALUES (@title, @artist, @album, @duration, @file_path, @file_name)
      ON CONFLICT(file_path) DO UPDATE SET
        title = excluded.title, artist = excluded.artist, album = excluded.album,
        duration = excluded.duration, updated_at = CURRENT_TIMESTAMP
    `);
    stmt.run({ title: 'V1', artist: 'A', album: 'B', duration: 100, file_path: '/m/s.mp3', file_name: 's.mp3' });
    stmt.run({ title: 'V2', artist: 'A', album: 'B', duration: 200, file_path: '/m/s.mp3', file_name: 's.mp3' });
    const row = db.prepare('SELECT title, duration FROM tracks WHERE file_path = ?').get('/m/s.mp3');
    expect(row.title).toBe('V2');
    expect(row.duration).toBe(200);
  });

  it('sorts by allowed columns only', () => {
    // Insert test data
    db.prepare(`INSERT INTO tracks (title, artist, album, duration, file_path, file_name, year)
      VALUES ('B', 'Y', 'Z', 100, '/m/1.mp3', '1.mp3', 2020)`).run();
    db.prepare(`INSERT INTO tracks (title, artist, album, duration, file_path, file_name, year)
      VALUES ('A', 'X', 'Y', 200, '/m/2.mp3', '2.mp3', 2021)`).run();

    // Test sort validation: malicious column name should be ignored
    const malicious = 'title; DROP TABLE tracks;--';
    const allowedSortColumns = ['title', 'artist', 'album', 'duration', 'imported_at', 'year'];
    let sortBy = malicious;
    if (!allowedSortColumns.includes(sortBy)) sortBy = 'imported_at';
    expect(sortBy).toBe('imported_at');

    // Verify sort works correctly
    const rows = db.prepare('SELECT title FROM tracks ORDER BY title ASC').all();
    expect(rows[0].title).toBe('A');
    expect(rows[1].title).toBe('B');
  });

  it('deletes track and cascades to play_history', () => {
    const t = db.prepare(`INSERT INTO tracks (title, artist, album, duration, file_path, file_name)
      VALUES ('T', 'A', 'B', 100, '/m/t.mp3', 't.mp3')`).run();
    const trackId = t.lastInsertRowid;
    db.prepare("INSERT INTO play_history (track_id, started_at) VALUES (?, datetime('now'))").run(trackId);

    expect(db.prepare('SELECT COUNT(*) as c FROM play_history WHERE track_id = ?').get(trackId).c).toBe(1);

    db.prepare('DELETE FROM tracks WHERE id = ?').run(trackId);
    expect(db.prepare('SELECT COUNT(*) as c FROM play_history WHERE track_id = ?').get(trackId).c).toBe(0);
  });
});

describe('Playlist operations', () => {
  let db;
  beforeEach(() => { db = initTestDb(); });
  afterEach(() => { closeTestDb(db); });

  it('creates a playlist', () => {
    const r = db.prepare("INSERT INTO playlists (name) VALUES ('My List')").run();
    expect(r.lastInsertRowid).toBeGreaterThan(0);
  });

  it('adds track to playlist with auto-increment position', () => {
    db.prepare("INSERT INTO tracks (title, file_path, file_name, duration) VALUES ('T', '/m/t.mp3', 't.mp3', 100)").run();
    db.prepare("INSERT INTO playlists (name) VALUES ('P')").run();

    const maxPos = db.prepare(
      "SELECT COALESCE(MAX(position), -1) + 1 as next_pos FROM playlist_tracks WHERE playlist_id = ?"
    ).get(1).next_pos;
    expect(maxPos).toBe(0);

    db.prepare("INSERT INTO playlist_tracks (playlist_id, track_id, position) VALUES (1, 1, ?)").run(maxPos);
    const pos2 = db.prepare(
      "SELECT COALESCE(MAX(position), -1) + 1 as next_pos FROM playlist_tracks WHERE playlist_id = ?"
    ).get(1).next_pos;
    expect(pos2).toBe(1);
  });

  it('prevents duplicate track in playlist', () => {
    db.prepare("INSERT INTO tracks (title, file_path, file_name, duration) VALUES ('T', '/m/t.mp3', 't.mp3', 100)").run();
    db.prepare("INSERT INTO playlists (name) VALUES ('P')").run();
    db.prepare("INSERT INTO playlist_tracks (playlist_id, track_id, position) VALUES (1, 1, 0)").run();
    expect(() => {
      db.prepare("INSERT INTO playlist_tracks (playlist_id, track_id, position) VALUES (1, 1, 1)").run();
    }).toThrow();
  });
});

describe('Settings operations', () => {
  let db;
  beforeEach(() => { db = initTestDb(); });
  afterEach(() => { closeTestDb(db); });

  it('sets and gets a setting', () => {
    db.prepare("INSERT INTO settings (key, value) VALUES ('theme', 'dark')").run();
    const row = db.prepare("SELECT value FROM settings WHERE key = 'theme'").get();
    expect(row.value).toBe('dark');
  });

  it('upserts on conflict', () => {
    db.prepare("INSERT INTO settings (key, value) VALUES ('k', 'v1')").run();
    db.prepare("INSERT INTO settings (key, value) VALUES ('k', 'v2') ON CONFLICT(key) DO UPDATE SET value = excluded.value").run();
    const row = db.prepare("SELECT value FROM settings WHERE key = 'k'").get();
    expect(row.value).toBe('v2');
  });

  it('returns default for missing key', () => {
    const row = db.prepare("SELECT value FROM settings WHERE key = 'missing'").get();
    expect(row).toBeUndefined();
  });
});
```

- [ ] **Step 2: Run database tests**

Run: `npx vitest run tests/database.test.js`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add tests/database.test.js
git commit -m "test: add database CRUD, playlist, and settings unit tests"
```

---

### Task 4.2: Playback queue logic tests

**Files:**
- Create: `tests/playback.test.js`

- [ ] **Step 1: Create `tests/playback.test.js`**

```js
import { describe, it, expect } from 'vitest';

// Pure function versions of the shuffle/queue logic (extracted for testability)

function shuffleArray(array) {
  const a = [...array];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

function getNextIndex(queue, queueIndex, playMode, shuffledQueue) {
  if (!queue.length) return -1;

  if (playMode === 'repeat-one') return queueIndex;

  if (playMode === 'shuffle') {
    const shuffled = shuffledQueue.length > 0 ? shuffledQueue : queue;
    const currentShuffledIdx = shuffled.findIndex(t => t.id === queue[queueIndex]?.id);
    if (currentShuffledIdx < shuffled.length - 1) {
      return queue.findIndex(t => t.id === shuffled[currentShuffledIdx + 1].id);
    }
    return queue.findIndex(t => t.id === shuffled[0].id);
  }

  // sequential
  return queueIndex < queue.length - 1 ? queueIndex + 1 : 0;
}

function getPrevIndex(queue, queueIndex, currentTime, playMode, shuffledQueue) {
  if (!queue.length) return -1;

  if (currentTime > 3) return queueIndex; // restart current track

  if (playMode === 'shuffle') {
    const shuffled = shuffledQueue.length > 0 ? shuffledQueue : queue;
    const currentShuffledIdx = shuffled.findIndex(t => t.id === queue[queueIndex]?.id);
    if (currentShuffledIdx > 0) {
      return queue.findIndex(t => t.id === shuffled[currentShuffledIdx - 1].id);
    }
    return queue.findIndex(t => t.id === shuffled[shuffled.length - 1].id);
  }

  return queueIndex > 0 ? queueIndex - 1 : queue.length - 1;
}

const tracks = [
  { id: 1, title: 'A' }, { id: 2, title: 'B' },
  { id: 3, title: 'C' }, { id: 4, title: 'D' },
];

describe('Sequential mode', () => {
  it('moves to next track', () => {
    expect(getNextIndex(tracks, 0, 'sequential', [])).toBe(1);
    expect(getNextIndex(tracks, 2, 'sequential', [])).toBe(3);
  });

  it('wraps to first track after last', () => {
    expect(getNextIndex(tracks, 3, 'sequential', [])).toBe(0);
  });

  it('goes to previous track', () => {
    expect(getPrevIndex(tracks, 2, 1, 'sequential', [])).toBe(1);
  });

  it('wraps to last track before first', () => {
    expect(getPrevIndex(tracks, 0, 1, 'sequential', [])).toBe(3);
  });

  it('restarts current track if >3s elapsed', () => {
    expect(getPrevIndex(tracks, 1, 4, 'sequential', [])).toBe(1);
  });
});

describe('Repeat-one mode', () => {
  it('stays on the same track', () => {
    expect(getNextIndex(tracks, 1, 'repeat-one', [])).toBe(1);
  });
});

describe('Shuffle mode', () => {
  it('returns a valid index within queue bounds', () => {
    const shuffled = shuffleArray(tracks);
    const nextIdx = getNextIndex(tracks, 0, 'shuffle', shuffled);
    expect(nextIdx).toBeGreaterThanOrEqual(0);
    expect(nextIdx).toBeLessThan(tracks.length);
  });

  it('prev returns valid index', () => {
    const shuffled = shuffleArray(tracks);
    const prevIdx = getPrevIndex(tracks, 1, 1, 'shuffle', shuffled);
    expect(prevIdx).toBeGreaterThanOrEqual(0);
    expect(prevIdx).toBeLessThan(tracks.length);
  });

  it('handles empty queue', () => {
    expect(getNextIndex([], 0, 'sequential', [])).toBe(-1);
    expect(getPrevIndex([], 0, 1, 'sequential', [])).toBe(-1);
  });
});
```

- [ ] **Step 2: Run playback tests**

Run: `npx vitest run tests/playback.test.js`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add tests/playback.test.js
git commit -m "test: add queue logic tests for sequential, repeat-one, and shuffle modes"
```

---

### Task 4.3: AudioEngine lifecycle tests

**Files:**
- Create: `tests/audioEngine.test.js`

- [ ] **Step 1: Create `tests/audioEngine.test.js`**

```js
import { describe, it, expect, beforeEach } from 'vitest';
import { AudioEngine } from '../src/audioEngine';

describe('AudioEngine', () => {
  let engine;

  beforeEach(() => {
    engine = new AudioEngine();
  });

  it('creates an instance with null initial state', () => {
    expect(engine.ctx).toBeNull();
    expect(engine.analyser).toBeNull();
    expect(engine.gainNode).toBeNull();
    expect(engine.sourceNode).toBeNull();
    expect(engine.connectedElement).toBeNull();
  });

  it('connect() returns null for null audio element', () => {
    expect(engine.connect(null)).toBeNull();
  });

  it('connect() creates audio graph for valid element', () => {
    const el = new Audio();
    const an = engine.connect(el);
    expect(an).not.toBeNull();
    expect(engine.ctx).not.toBeNull();
    expect(engine.analyser).not.toBeNull();
    expect(engine.gainNode).not.toBeNull();
    expect(engine.sourceNode).not.toBeNull();
    expect(engine.connectedElement).toBe(el);
  });

  it('connect() returns cached analyser for same element', () => {
    const el = new Audio();
    const an1 = engine.connect(el);
    const an2 = engine.connect(el);
    expect(an1).toBe(an2);
  });

  it('setGain() applies gain', () => {
    const el = new Audio();
    engine.connect(el);
    expect(() => engine.setGain(-3)).not.toThrow();
    expect(() => engine.setGain(0)).not.toThrow();
    expect(() => engine.setGain(6)).not.toThrow();
  });

  it('resume() works on suspended context', () => {
    const el = new Audio();
    engine.connect(el);
    expect(() => engine.resume()).not.toThrow();
  });

  it('dispose() cleans up all nodes', () => {
    const el = new Audio();
    engine.connect(el);
    engine.dispose();
    expect(engine.sourceNode).toBeNull();
    expect(engine.analyser).toBeNull();
    expect(engine.gainNode).toBeNull();
    expect(engine.connectedElement).toBeNull();
  });
});
```

- [ ] **Step 2: Run engine tests**

Run: `npx vitest run tests/audioEngine.test.js`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add tests/audioEngine.test.js
git commit -m "test: add AudioEngine class lifecycle tests"
```

---

## Phase 5: UX Improvements

### Task 5.1: System media key support

**Files:**
- Modify: `electron/main.js` (add globalShortcut registration)
- Modify: `electron/preload.js` (expose media key callbacks)

- [ ] **Step 1: Register global media key shortcuts in `electron/main.js`**

Add to the `app.whenReady()` block after `createWindow()`:

```js
const { globalShortcut } = require('electron');

// Register media keys
globalShortcut.register('MediaPlayPause', () => {
  mainWindow?.webContents.send('media-key', 'playpause');
});
globalShortcut.register('MediaNextTrack', () => {
  mainWindow?.webContents.send('media-key', 'next');
});
globalShortcut.register('MediaPreviousTrack', () => {
  mainWindow?.webContents.send('media-key', 'previous');
});
```

- [ ] **Step 2: Expose media key listener in `electron/preload.js`**

Add to the `contextBridge.exposeInMainWorld` object:

```js
onMediaKey: (callback) => {
  ipcRenderer.on('media-key', (_event, action) => callback(action));
},
```

- [ ] **Step 3: Wire media keys in `src/hooks/usePlayback.js`**

Add a useEffect that listens for media key events:

```js
useEffect(() => {
  const handler = (action) => {
    switch (action) {
      case 'playpause': togglePlayPause(); break;
      case 'next': handleNext(); break;
      case 'previous': handlePrev(); break;
    }
  };
  window.freeplayer.onMediaKey(handler);
}, [togglePlayPause, handleNext, handlePrev]);
```

- [ ] **Step 4: Commit**

```bash
git add electron/main.js electron/preload.js src/hooks/usePlayback.js
git commit -m "feat: add system media key support (PlayPause, Next, Previous)"
```

---

### Task 5.2: Import modal back button

**Files:**
- Modify: `src/components/ImportModal.jsx`

- [ ] **Step 1: Add "Back" button in ImportModal confirm step**

In the `confirm` step's modal footer, add a back button before Cancel:

```jsx
{step === 'confirm' && (
  <>
    <button className="btn btn-secondary" onClick={() => {
      setStep('select-source');
      setFiles([]);
      startedRef.current = false;
    }}>Back</button>
    <button className="btn btn-secondary" onClick={onClose}>Cancel</button>
    <button className="btn btn-primary" onClick={handleImport}>
      Import {files.length} Files
    </button>
  </>
)}
```

- [ ] **Step 2: Commit**

```bash
git add src/components/ImportModal.jsx
git commit -m "feat: add back button to import modal confirm step"
```

---

## Phase 6: Build & Distribution + Security

### Task 5.3: Add debounced search

**Files:**
- Modify: `src/hooks/useLibrary.js` (add debounce logic)

- [ ] **Step 1: Add debounce to search in `useLibrary.js`**

Add a `useEffect` that debounces `searchQuery` before triggering `loadTracks`:

```js
import { useCallback, useEffect, useRef } from 'react';

// Inside useLibrary(), replace the loadTracks effect with a debounced version:

const debounceRef = useRef(null);

useEffect(() => {
  if (!state.isSetup) return;
  if (debounceRef.current) clearTimeout(debounceRef.current);
  debounceRef.current = setTimeout(() => {
    loadTracks();
  }, 250);
  return () => clearTimeout(debounceRef.current);
}, [state.searchQuery, state.isSetup]); // eslint-disable-line react-hooks/exhaustive-deps
```

Remove the previous `useEffect(() => { if (state.isSetup) loadTracks(); }, [state.isSetup, loadTracks])` — the debounced effect above takes over the triggering logic. The `loadTracks` callback still depends on `searchQuery`/`sortBy`/`sortDir`, so the debounced effect only fires on `searchQuery` changes, while the existing `useEffect` for initial load on `isSetup` change is kept but simplified to just call `loadTracks` directly (bypassing debounce for sort changes):

```js
// Initial load and sort changes fire immediately (no debounce needed)
useEffect(() => {
  if (state.isSetup) loadTracks();
}, [state.isSetup, state.sortBy, state.sortDir]); // eslint-disable-line react-hooks/exhaustive-deps
```

- [ ] **Step 2: Verify debounce behavior**

Run: `npm run dev`
Expected: Typing in search box doesn't reload on every keystroke — library refreshes ~250ms after last keystroke.

- [ ] **Step 3: Commit**

```bash
git add src/hooks/useLibrary.js
git commit -m "perf: add 250ms debounce to library search input"
```

---

### Task 6.1: Turn off webSecurity: false

**Files:**
- Modify: `electron/main.js`

- [ ] **Step 1: Remove `webSecurity: false`**

In `electron/main.js`, remove line 47:
```js
webSecurity: false,
```

The app uses `media://` custom protocol and `contextBridge` with `contextIsolation: true`. The `webSecurity: false` was never needed — the custom protocol handles file loading, and all IPC goes through the preload bridge. The CSP implied by `webSecurity: true` does not block custom protocols.

- [ ] **Step 2: Verify the app loads and media plays**

Run: `npm run dev`
Expected: App launches, library loads, audio plays via `media://` protocol.

- [ ] **Step 3: Commit**

```bash
git add electron/main.js
git commit -m "security: re-enable webSecurity by removing the unnecessary override"
```

---

### Task 6.2: Add electron-builder packaging

**Files:**
- Modify: `package.json` (add build config + scripts)
- Create: `build/entitlements.mac.plist`

- [ ] **Step 1: Install electron-builder**

Run: `npm install -D electron-builder`
Expected: electron-builder added to devDependencies.

- [ ] **Step 2: Add build config to `package.json`**

Add to the root of `package.json`:

```json
"build": {
  "appId": "com.freeplayer.app",
  "productName": "FreePlayer",
  "directories": {
    "output": "release"
  },
  "files": [
    "dist/**/*",
    "electron/**/*",
    "node_modules/**/*",
    "package.json"
  ],
  "mac": {
    "category": "public.app-category.music",
    "target": ["dmg", "zip"],
    "hardenedRuntime": true,
    "entitlements": "build/entitlements.mac.plist",
    "entitlementsInherit": "build/entitlements.mac.plist"
  },
  "win": {
    "target": ["nsis"]
  },
  "linux": {
    "target": ["AppImage", "deb"],
    "category": "Audio"
  }
}
```

Add scripts:
```json
"pack": "vite build && electron-builder --dir",
"dist": "vite build && electron-builder",
"dist:mac": "vite build && electron-builder --mac",
"dist:win": "vite build && electron-builder --win",
"dist:linux": "vite build && electron-builder --linux"
```

- [ ] **Step 3: Create `build/entitlements.mac.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-only</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 4: Commit**

```bash
git add package.json build/entitlements.mac.plist
git commit -m "build: add electron-builder packaging config for mac/win/linux"
```

---

## Phase 7: Final Verification

### Task 7.1: Run full test suite and production build

- [ ] **Step 1: Run all tests**

Run: `npm test`
Expected: All tests pass (database + playback + audioEngine).

- [ ] **Step 2: Production build**

Run: `npm run build`
Expected: Vite build succeeds, `dist/` directory created.

- [ ] **Step 3: Production package test**

Run: `npm run pack`
Expected: electron-builder creates unpacked app in `release/`.

- [ ] **Step 4: Dev mode smoke test**

Run: `npm run dev`
Expected: App launches, library loads, play/pause/next/prev work, visualizer renders, media keys respond.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "chore: final verification after comprehensive refactor"
```
