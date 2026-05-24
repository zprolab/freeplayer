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
  const { state, dispatch, audioRef } = usePlayer();
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
        const prev = state.visualizerMode;
        if (e.shiftKey) {
          const idx = MODES.indexOf(prev);
          dispatch({ type: 'SET', payload: { visualizerMode: MODES[(idx + 1) % MODES.length] } });
        } else {
          dispatch({ type: 'SET', payload: { visualizerMode: prev === 'off' ? 'waveform' : 'off' } });
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

  const displayedTracks = state.activePlaylistId === null ? state.tracks : state.playlistTracks;

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
              <span className="track-count-badge">{displayedTracks.length} tracks</span>
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
                  tracks={displayedTracks}
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
                  audioElement={audioRef.current}
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
