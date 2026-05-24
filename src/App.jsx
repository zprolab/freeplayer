import React, { useState, useEffect, useCallback, useRef } from 'react';
import Sidebar from './components/Sidebar';
import Library from './components/Library';
import NowPlaying from './components/NowPlaying';
import Stats from './components/Stats';
import PlayerBar from './components/PlayerBar';
import ImportModal from './components/ImportModal';
import Settings from './components/Settings';
import PlaylistModal from './components/PlaylistModal';
import { setPlaybackGain } from './audioEngine';

const VIEWS = {
  LIBRARY: 'library',
  NOW_PLAYING: 'now-playing',
  STATS: 'stats',
  SETTINGS: 'settings',
};

export default function App() {
  const [view, setView] = useState(VIEWS.LIBRARY);
  const [tracks, setTracks] = useState([]);
  const [currentTrack, setCurrentTrack] = useState(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [queue, setQueue] = useState([]);
  const [queueIndex, setQueueIndex] = useState(-1);
  const [importModalOpen, setImportModalOpen] = useState(false);
  const [isSetup, setIsSetup] = useState(false);
  const [libraryDir, setLibraryDir] = useState('');
  const [searchQuery, setSearchQuery] = useState('');
  const [sortBy, setSortBy] = useState('imported_at');
  const [sortDir, setSortDir] = useState('DESC');
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [volume, setVolume] = useState(0.8);
  const [isLoading, setIsLoading] = useState(true);
  const [visualizerMode, setVisualizerMode] = useState('waveform'); // 'waveform' | 'spectrogram' | 'off'
  const [importMode, setImportMode] = useState('copy');
  const [defaultVolume, setDefaultVolume] = useState(0.8);
  const [defaultVisualizer, setDefaultVisualizer] = useState('waveform');
  const [playMode, setPlayMode] = useState('sequential'); // 'sequential' | 'repeat-one' | 'shuffle'
  const [shuffledQueue, setShuffledQueue] = useState([]);
  const [playlists, setPlaylists] = useState([]);
  const [activePlaylistId, setActivePlaylistId] = useState(null);
  const [playlistTracks, setPlaylistTracks] = useState([]);
  const [playlistModal, setPlaylistModal] = useState(null);
  const [pendingAddTrack, setPendingAddTrack] = useState(null);
  const [dragOver, setDragOver] = useState(false);
  const [initialPaths, setInitialPaths] = useState(null);

  const audioRef = useRef(new Audio());
  const playSessionIdRef = useRef(null);
  const playStartTimeRef = useRef(null);
  const togglePlayPauseRef = useRef(null);
  const handleNextRef = useRef(null);
  const handlePrevRef = useRef(null);

  // Fisher-Yates shuffle
  function shuffleArray(array) {
    const a = [...array];
    for (let i = a.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
  }

  // Check setup on mount
  useEffect(() => {
    async function checkSetup() {
      try {
        const result = await window.freeplayer.isSetup();
        setIsSetup(result.setup);
        setLibraryDir(result.libraryDir || '');
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
        if (result.setup) {
          await loadTracks();
          await loadPlaylists();
        }
      } catch (err) {
        console.error('Setup check failed:', err);
      } finally {
        setIsLoading(false);
      }
    }
    checkSetup();
  }, []);

  const loadTracks = useCallback(async () => {
    try {
      const data = await window.freeplayer.getTracks({ search: searchQuery, sortBy, sortDir });
      setTracks(data);
    } catch (err) {
      console.error('Failed to load tracks:', err);
    }
  }, [searchQuery, sortBy, sortDir]);

  useEffect(() => {
    if (isSetup) loadTracks();
  }, [loadTracks, isSetup]);

  const loadPlaylists = useCallback(async () => {
    try {
      const data = await window.freeplayer.getPlaylists();
      setPlaylists(data || []);
    } catch (err) {
      console.error('Failed to load playlists:', err);
    }
  }, []);

  // Audio event handlers
  useEffect(() => {
    const audio = audioRef.current;

    const onTimeUpdate = () => setCurrentTime(audio.currentTime);
    const onDurationChange = () => setDuration(audio.duration || 0);
    const onEnded = () => handleNextRef.current?.();
    const onPlay = () => setIsPlaying(true);
    const onPause = () => setIsPlaying(false);
    const onError = (e) => {
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

    audio.volume = volume;

    return () => {
      audio.removeEventListener('timeupdate', onTimeUpdate);
      audio.removeEventListener('durationchange', onDurationChange);
      audio.removeEventListener('ended', onEnded);
      audio.removeEventListener('play', onPlay);
      audio.removeEventListener('pause', onPause);
      audio.removeEventListener('error', onError);
    };
  }, [volume]);

  // End play session only on app close / unmount (track switches handled explicitly)
  useEffect(() => {
    return () => {
      const sid = playSessionIdRef.current;
      if (sid && playStartTimeRef.current) {
        const elapsed = (Date.now() - playStartTimeRef.current) / 1000;
        const trackDuration = audioRef.current.duration || 0;
        const percentage = trackDuration > 0 ? Math.min((elapsed / trackDuration) * 100, 100) : 0;
        window.freeplayer.playEnd({ sessionId: sid, durationSeconds: Math.round(elapsed), playPercentage: Math.round(percentage) });
      }
    };
  }, []);

  // Keyboard shortcuts for visualizer
  useEffect(() => {
    const MODES = ['waveform', 'spectrogram', 'off'];
    const onKey = (e) => {
      // Don't trigger when typing in inputs
      if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;

      if (e.key === ' ' || e.code === 'Space') {
        e.preventDefault();
        togglePlayPauseRef.current?.();
        return;
      }
      if (e.key === 'v' || e.key === 'V') {
        if (e.shiftKey) {
          setVisualizerMode(prev => {
            const idx = MODES.indexOf(prev);
            return MODES[(idx + 1) % MODES.length];
          });
        } else {
          setVisualizerMode(prev => prev === 'off' ? 'waveform' : 'off');
        }
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  const startPlaySession_ = async (trackId) => {
    const prevSid = playSessionIdRef.current;
    if (prevSid && playStartTimeRef.current) {
      const elapsed = (Date.now() - playStartTimeRef.current) / 1000;
      const trackDuration = audioRef.current.duration || 0;
      const percentage = trackDuration > 0 ? Math.min((elapsed / trackDuration) * 100, 100) : 0;
      await window.freeplayer.playEnd({ sessionId: prevSid, durationSeconds: Math.round(elapsed), playPercentage: Math.round(percentage) });
    }
    const sessionId = await window.freeplayer.playStart(trackId);
    playSessionIdRef.current = sessionId;
    playStartTimeRef.current = Date.now();
  };

  const playTrack = async (track) => {
    setCurrentTrack(track);
    const src = `media://${track.file_path}`;
    audioRef.current.src = src;
    // Apply ReplayGain loudness normalization
    const gainDb = track.replaygain_gain || 0;
    setPlaybackGain(gainDb);
    try {
      await audioRef.current.play();
      await startPlaySession_(track.id);
    } catch (err) {
      console.error('Playback failed:', err);
    }
  };

  const togglePlayPause = () => {
    const audio = audioRef.current;
    if (!audio.src && tracks.length > 0) {
      playTrack(tracks[0]);
      return;
    }
    if (audio.paused) {
      audio.play().catch(console.error);
    } else {
      audio.pause();
    }
  };
  togglePlayPauseRef.current = togglePlayPause;

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
        const reshuffled = shuffleArray(queue);
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
  handleNextRef.current = handleNext;
  handlePrevRef.current = handlePrev;

  const handleSeek = (time) => {
    audioRef.current.currentTime = time;
    setCurrentTime(time);
  };

  const handleVolumeChange = (vol) => {
    audioRef.current.volume = vol;
    setVolume(vol);
  };

  const playTrackFromList = async (track, trackList) => {
    setQueue(trackList);
    const idx = trackList.findIndex(t => t.id === track.id);
    setQueueIndex(idx);

    if (playMode === 'shuffle') {
      const shuffled = shuffleArray(trackList);
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

  const handleImportComplete = async (result) => {
    setImportModalOpen(false);
    if (result && !result.canceled) {
      await loadTracks();
      const setupResult = await window.freeplayer.isSetup();
      setIsSetup(setupResult.setup);
      setLibraryDir(setupResult.libraryDir || '');
    }
  };

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
    setPlaylists([]);
    setActivePlaylistId(null);
    setPlaylistTracks([]);
    audioRef.current.src = '';
  };

  // ── Playlist handlers ──

  const handleSelectPlaylist = async (playlistId) => {
    setActivePlaylistId(playlistId);
    if (playlistId === null) {
      await loadTracks();
    } else {
      const tracks = await window.freeplayer.getPlaylistTracks(playlistId);
      setPlaylistTracks(tracks || []);
    }
    setView(VIEWS.LIBRARY);
  };

  const handleCreatePlaylist = async ({ name, description }) => {
    const result = await window.freeplayer.createPlaylist({ name, description });
    await loadPlaylists();
    setPlaylistModal(null);
    if (pendingAddTrack) {
      const playlistId = result.lastInsertRowid || result.id;
      await window.freeplayer.addToPlaylist({ playlistId, trackId: pendingAddTrack.id });
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

  const handleDragEnter = (e) => {
    if (view !== VIEWS.LIBRARY || importModalOpen) return;
    e.preventDefault();
    e.stopPropagation();
    setDragOver(true);
  };

  const handleDragOver = (e) => {
    if (view !== VIEWS.LIBRARY || importModalOpen) return;
    e.preventDefault();
    e.stopPropagation();
  };

  const handleDragLeave = (e) => {
    if (e.currentTarget === e.target) {
      setDragOver(false);
    }
  };

  const handleDrop = (e) => {
    e.preventDefault();
    e.stopPropagation();
    setDragOver(false);

    if (view !== VIEWS.LIBRARY || importModalOpen) return;

    const paths = [];
    const { files } = e.dataTransfer;
    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      if (file.path) {
        paths.push(file.path);
      }
    }

    if (paths.length > 0) {
      setInitialPaths(paths);
      setImportModalOpen(true);
    }
  };

  if (isLoading) {
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
      <main className="main-content">
        <header className="top-bar">
          <div className="top-bar-left">
            <h1 className="page-title">
              {view === VIEWS.LIBRARY && (activePlaylistId !== null
                ? (playlists.find(p => p.id === activePlaylistId)?.name || 'Playlist')
                : 'Library'
              )}
              {view === VIEWS.NOW_PLAYING && 'Now Playing'}
              {view === VIEWS.STATS && 'Statistics'}
              {view === VIEWS.SETTINGS && 'Settings'}
            </h1>
            {view === VIEWS.LIBRARY && (
              <span className="track-count-badge">
                {activePlaylistId === null ? tracks.length : playlistTracks.length} tracks
              </span>
            )}
          </div>
          <div className="top-bar-right">
            {view === VIEWS.LIBRARY && (
              <>
                <div className="search-box">
                  <svg className="search-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
                    <path d="M11.742 10.344a6.5 6.5 0 1 0-1.397 1.398h-.001l3.85 3.85a1 1 0 0 0 1.415-1.414l-3.85-3.85-.017.016zm-5.242.156a5 5 0 1 1 0-10 5 5 0 0 1 0 10z" fill="currentColor"/>
                  </svg>
                  <input
                    type="text"
                    placeholder="Search your library..."
                    value={searchQuery}
                    onChange={(e) => setSearchQuery(e.target.value)}
                    className="search-input"
                  />
                  {searchQuery && (
                    <button className="search-clear" onClick={() => setSearchQuery('')}>
                      <svg width="12" height="12" viewBox="0 0 12 12"><path d="M1 1l10 10M11 1L1 11" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"/></svg>
                    </button>
                  )}
                </div>
                <button className="btn btn-primary" onClick={() => setImportModalOpen(true)}>
                  <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                    <path d="M8 1v14M1 8h14" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
                  </svg>
                  Import
                </button>
              </>
            )}
          </div>
        </header>

        <div
          className="content-area"
          onDragEnter={handleDragEnter}
          onDragOver={handleDragOver}
          onDragLeave={handleDragLeave}
          onDrop={handleDrop}
        >
          {dragOver && view === VIEWS.LIBRARY && !importModalOpen && (
            <div className="drag-overlay">
              <div className="drag-zone">
                <svg className="drag-zone-icon" width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round">
                  <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
                  <polyline points="17 8 12 3 7 8"/>
                  <line x1="12" y1="3" x2="12" y2="15"/>
                </svg>
                <span className="drag-zone-title">Drop to Import</span>
                <span className="drag-zone-hint">Audio files and folders supported</span>
              </div>
            </div>
          )}
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
              <div className="empty-state-icon">
                <svg width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.2">
                  <path d="M9 18V5l12-2v13"/>
                  <circle cx="6" cy="18" r="3"/>
                  <circle cx="18" cy="16" r="3"/>
                </svg>
              </div>
              <h2>Welcome to FreePlayer</h2>
              <p>Set up your music library to get started. Choose a directory where your music will be stored, then import your audio files.</p>
              <button className="btn btn-primary btn-lg" onClick={() => setImportModalOpen(true)}>
                Set Up Library
              </button>
            </div>
          ) : (
            <>
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
              {view === VIEWS.NOW_PLAYING && (
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
              )}
              {view === VIEWS.STATS && <Stats />}
            </>
          )}
        </div>
      </main>

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

      {importModalOpen && (
        <ImportModal
          onClose={() => {
            setImportModalOpen(false);
            setInitialPaths(null);
          }}
          onComplete={(result) => {
            setInitialPaths(null);
            handleImportComplete(result);
          }}
          importMode={importMode}
          initialPaths={initialPaths}
        />
      )}

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
    </div>
  );
}
