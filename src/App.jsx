import { useEffect, useMemo, useRef, useState } from 'react';
import Sidebar from './components/Sidebar';
import logoUrl from '../assets/logo.svg';
import Library from './components/Library';
import NowPlaying from './components/NowPlaying';
import Stats from './components/Stats';
import PlayerBar from './components/PlayerBar';
import MobileTabBar from './components/MobileTabBar';
import ImportModal from './components/ImportModal';
import Settings from './components/Settings';
import PluginPage from './components/PluginPage';
import PlaylistModal from './components/PlaylistModal';
import { usePlayer, VIEWS } from './context/PlayerContext';
import { usePlayback } from './hooks/usePlayback';
import { useLibrary } from './hooks/useLibrary';
import { usePlaylists } from './hooks/usePlaylists';
import { useAutoMeta } from './hooks/useAutoMeta';
import { audioEngine } from './audio/audioEngine';
import { createRegistry } from './plugins/registry';
import { createMetadataRegistry } from './plugins/metadataRegistry';
import { BUILTIN_PLUGINS } from './plugins/builtin';
import { createLoader } from './plugins/loader';
import { createPluginApi } from './plugins/api';
import { createEventBus } from './plugins/hooks';

// Plugin runtime singleton: registry + metadata registry assembled lazily on
// first use. Player/audio/events are resolved per plugin activation via
// window.__fpRuntimeState (written below), so lazily-activated plugins always
// see the live player bridge.
let pluginRuntime = null;

// Client-side sort for playlist views: getPlaylistTracks accepts no sort
// params and returns tracks in playlist position order, so replicate the DB
// sort semantics here (case-insensitive text, numeric duration/year).
function compareTracks(a, b, sortBy, sortDir) {
  const sign = sortDir === 'ASC' ? 1 : -1;
  let cmp = 0;
  if (sortBy === 'duration' || sortBy === 'year') {
    cmp = (Number(a[sortBy]) || 0) - (Number(b[sortBy]) || 0);
  } else {
    const av = String(a[sortBy] ?? '').toLowerCase();
    const bv = String(b[sortBy] ?? '').toLowerCase();
    cmp = av < bv ? -1 : av > bv ? 1 : 0;
  }
  return cmp * sign;
}

async function getPluginRuntime() {
  if (pluginRuntime) return pluginRuntime;
  const loader = createLoader({
    readFile: (pluginId, relPath) => window.freeplayer.readPluginFile(pluginId, relPath),
    importUrl: (url) => import(/* @vite-ignore */ url),
    createApi: (pluginId) => createPluginApi(pluginId, [], {
      bridge: {
        http: {
          getJson: (url) => window.freeplayer.httpGetJson(url),
          getBase64: (url) => window.freeplayer.httpGetBase64(url),
        },
        metadata: {
          getTrackInfo: (id) => window.freeplayer.getTrack(id),
          getLyrics: (id) => window.freeplayer.getLrc(id).then((r) => r && r.content),
          getCover: (id) => window.freeplayer.getTrack(id).then((t) => (t ? window.freeplayer.getCover(t.cover_path) : null)),
          saveLyrics: (id, content) => window.freeplayer.saveLrcContent(id, content),
          saveCover: (id, base64) => window.freeplayer.saveCover(id, base64),
          updateTrack: (id, fields) => window.freeplayer.updateTrack({ id, ...fields }),
          removeLyrics: (id) => window.freeplayer.removeLrc(id),
        },
        audio: null, // provided by App via window.__fpRuntimeState (Step 5b)
      },
      player: null, // provided by App via window.__fpRuntimeState (Step 5b)
      settings: {
        get: (key) => window.freeplayer.getSetting(key),
        set: ({ key, value }) => window.freeplayer.setSetting({ key, value }),
      },
      pluginSettings: {
        get: (key) => window.freeplayer.getSetting(`plugin.${key}`),
        set: (key, value) => window.freeplayer.setSetting({ key: `plugin.${key}`, value: JSON.stringify(value) }),
      },
      log: (id, level, msg) => console.warn(`[plugin:${id}]`, level, msg),
      events: null, // provided by App via window.__fpRuntimeState (Step 5b)
    }),
    onDenied: (pluginId, key) => console.warn(`[plugin:${pluginId}] permission denied: ${key}`),
  });
  const registry = createRegistry({
    listPlugins: () => window.freeplayer.listPlugins(),
    readFile: (pluginId, relPath) => window.freeplayer.readPluginFile(pluginId, relPath),
    loader,
    log: (id, level, msg) => console.warn(`[plugin:${id}]`, level, msg),
    getSetting: (k) => window.freeplayer.getSetting(k),
    setSetting: (data) => window.freeplayer.setSetting(data),
    uninstallPlugin: (id) => window.freeplayer.uninstallPlugin(id),
  });
  for (const b of BUILTIN_PLUGINS) registry.registerBuiltin(b);
  await registry.discover();
  await registry.restoreState();
  const meta = createMetadataRegistry({
    registry,
    getSetting: (k) => window.freeplayer.getSetting(k),
    saveLyrics: (trackId, content) => window.freeplayer.saveLrcContent(trackId, content),
    saveCover: (trackId, base64) => window.freeplayer.saveCover(trackId, base64),
    updateTrack: (id, fields) => window.freeplayer.updateTrack({ id, ...fields }),
  });
  pluginRuntime = { registry, meta };
  return pluginRuntime;
}

export default function App() {
  const { state, dispatch, audioRef } = usePlayer();
  const {
    togglePlayPause, handleNext, handlePrev,
    handleSeek, handleVolumeChange, playTrackFromList,
  } = usePlayback();
  const {
    handleImportComplete, handleImportModeChange,
    handleDefaultVolumeChange, handleDefaultVisualizerChange,
    handleResetDatabase, handleSidebarCollapsedChange, loadTracks,
  } = useLibrary();
  const {
    handleSelectPlaylist, handleCreatePlaylist, handleRenamePlaylist, handleDeletePlaylist,
    handleUpdatePlaylistTracks, loadPlaylists,
    handleAddToPlaylist, handleRemoveFromPlaylist, handleOpenCreateForTrack,
  } = usePlaylists();

  const [pluginRuntime, setPluginRuntime] = useState(null);
  const meta = pluginRuntime?.meta;

  useAutoMeta(state.currentTrack, meta, dispatch);

  // Plugin bridge: real player/audio/events are written into
  // window.__fpRuntimeState and read lazily by createPluginApi per activation.
  // pluginBridgeRef.current is re-assigned every render, so the closures below
  // must dereference it at call time — never snapshotted at mount (F1).
  const stateRef = useRef(state);
  stateRef.current = state;
  const eventBusRef = useRef(createEventBus());
  const registryRef = useRef(null);
  registryRef.current = pluginRuntime?.registry;
  const pluginBridgeRef = useRef({});
  pluginBridgeRef.current = { state, togglePlayPause, handleNext, handlePrev, handleSeek, handleVolumeChange, audioRef };

  useEffect(() => {
    window.__fpRuntimeState = {
      player: {
        getState: () => pluginBridgeRef.current.state,
        getTrack: () => pluginBridgeRef.current.state.currentTrack,
        play: () => { if (!pluginBridgeRef.current.state.isPlaying) pluginBridgeRef.current.togglePlayPause(); },
        pause: () => { if (pluginBridgeRef.current.state.isPlaying) pluginBridgeRef.current.togglePlayPause(); },
        seek: (t) => pluginBridgeRef.current.handleSeek(t),
        next: () => pluginBridgeRef.current.handleNext(),
        previous: () => pluginBridgeRef.current.handlePrev(),
        setVolume: (v) => pluginBridgeRef.current.handleVolumeChange(v),
      },
      audio: { getSource: () => (pluginBridgeRef.current.audioRef.current ? pluginBridgeRef.current.audioRef.current.src : null) },
      events: eventBusRef.current,
    };
  }, []);

  // Plugin runtime: registry + metadata registry (auto-fetch pipeline).
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const rt = await getPluginRuntime();
        if (cancelled) return;
        setPluginRuntime(rt);
        rt.registry.subscribe('trackChanged', (track) => {
          // App stays the source of truth for playback: only adopt a
          // plugin-emitted track change when it names a different track.
          if (track?.id && track.id !== stateRef.current.currentTrack?.id) {
            dispatch({ type: 'SET_CURRENT_TRACK', payload: track });
          }
        });
      } catch (err) {
        console.warn('Plugin runtime init failed:', err.message || err);
      }
    })();
    return () => { cancelled = true; };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // Forward playback/track state to plugin listeners (api.events) and to the
  // registry (lazy-activation hooks onTrackChanged / onPlaybackChanged).
  // registryRef keeps the registry out of the deps so runtime init doesn't
  // cause spurious re-emits; the ref always holds the latest instance.
  useEffect(() => {
    if (!state.currentTrack) return;
    window.__fpRuntimeState?.events?.emit('trackChanged', state.currentTrack);
    registryRef.current?.emit('trackChanged', state.currentTrack);
  }, [state.currentTrack]);

  useEffect(() => {
    const payload = {
      isPlaying: state.isPlaying, currentTime: state.currentTime, duration: state.duration,
    };
    window.__fpRuntimeState?.events?.emit('playbackChanged', payload);
    registryRef.current?.emit('playbackChanged', payload);
  }, [state.isPlaying, state.currentTime, state.duration]);

  // macOS menu bar: actions pushed from the native menu (Playback/View/File)
  useEffect(() => {
    const actionRef = {
      playpause: togglePlayPause,
      next: handleNext,
      prev: handlePrev,
      import: () => dispatch({ type: 'SET', payload: { importModalOpen: true } }),
      'view-library': () => dispatch({ type: 'SET', payload: { view: VIEWS.LIBRARY } }),
      'view-now-playing': () => dispatch({ type: 'SET', payload: { view: VIEWS.NOW_PLAYING } }),
      'view-stats': () => dispatch({ type: 'SET', payload: { view: VIEWS.STATS } }),
      'view-plugins': () => dispatch({ type: 'SET', payload: { view: VIEWS.PLUGINS } }),
      'view-settings': () => dispatch({ type: 'SET', payload: { view: VIEWS.SETTINGS } }),
      'open-eq': () => window.freeplayer?.openEq?.(),
    };
    window.__freeplayerMenuAction = (action) => {
      actionRef[action]?.();
    };
    return () => { delete window.__freeplayerMenuAction; };
  }, [togglePlayPause, handleNext, handlePrev, dispatch]);

  // Load playlists on mount
  useEffect(() => {
    loadPlaylists();
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // Keyboard shortcuts
  useEffect(() => {
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

  // Tray menu playback control — use ref to avoid listener leak on re-renders
  const playbackHandlersRef = useRef({ togglePlayPause, handleNext, handlePrev });
  playbackHandlersRef.current = { togglePlayPause, handleNext, handlePrev };

  useEffect(() => {
    if (!window.freeplayer?.onPlaybackControl) return;
    const handler = ({ action }) => {
      const h = playbackHandlersRef.current;
      switch (action) {
        case 'playpause': h.togglePlayPause(); break;
        case 'next': h.handleNext(); break;
        case 'previous': h.handlePrev(); break;
      }
    };
    window.freeplayer.onPlaybackControl(handler);
  }, []); // register once; ref always has latest handlers

  // Equalizer: init from DB once, apply live curve changes
  const eqHandlerRef = useRef();
  eqHandlerRef.current = (s) => {
    if (!s) return;
    audioEngine.applyEq(s.gains, s.enabled);
    dispatch({ type: 'SET', payload: { eqEnabled: s.enabled } });
  };

  useEffect(() => {
    if (!window.freeplayer?.getEqState) return;
    window.freeplayer.getEqState().then((s) => {
      if (s) {
        audioEngine.applyEq(s.gains, s.enabled);
        dispatch({ type: 'SET', payload: { eqEnabled: s.enabled } });
      }
    }).catch((err) => console.warn('Failed to load EQ state:', err));
  }, []);

  useEffect(() => {
    if (!window.freeplayer?.onEqChange) return;
    window.freeplayer.onEqChange((s) => eqHandlerRef.current(s));
  }, []);

  // Appearance: Classic / Unified layout (defaults to Unified). Settings writes
// broadcast `fp-appearance-changed` so the switch applies without a restart.
useEffect(() => {
    const applyAppearance = () => {
      if (!window.freeplayer?.getSetting) return;
      window.freeplayer.getSetting('ui_mode')
        .then((mode) => {
          // missing setting → Unified (the current look)
          document.documentElement.classList.toggle('ui-mode-unified', mode !== 'classic');
        })
        .catch(() => {});
    };
    applyAppearance();
    window.addEventListener('fp-appearance-changed', applyAppearance);
    return () => window.removeEventListener('fp-appearance-changed', applyAppearance);
  }, []);

  const displayedTracks = useMemo(() => {
    if (state.activePlaylistId === null) return state.tracks;
    return state.playlistTracks
      .slice()
      .sort((a, b) => compareTracks(a, b, state.sortBy, state.sortDir));
    // state.tracks is a deps prerequisite: loadTracks replaces it on startup
    // while the other deps stay identical, and without it the memo would
    // freeze at the initial [] and show an empty library forever.
  }, [state.tracks, state.activePlaylistId, state.playlistTracks, state.sortBy, state.sortDir]);

  if (state.isLoading) {
    return (
      <div className="app-loading">
        <div className="loading-logo"><img src={logoUrl} width={56} height={56} alt="" /></div>
        <div className="loading-spinner" />
        <span className="loading-text">Loading FreePlayer...</span>
      </div>
    );
  }

  return (
    <div className={`app${state.sidebarCollapsed ? ' app--sidebar-collapsed' : ''}`}>
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
        onEditPlaylist={(playlist) => dispatch({ type: 'SET', payload: { playlistModal: { mode: 'edit', playlist } } })}
        onDeletePlaylist={handleDeletePlaylist}
        collapsed={state.sidebarCollapsed}
        onToggleCollapse={() => handleSidebarCollapsedChange(!state.sidebarCollapsed)}
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
              {state.view === VIEWS.PLUGINS && 'Plugins'}
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
                    <path d="M8 1v14M1 8h14" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"/>
                  </svg>
                  <span className="btn-label">Import</span>
                </button>
              </>
            )}
          </div>
        </header>

        <div className="content-area">
          {state.view === VIEWS.PLUGINS ? (
            pluginRuntime ? (
              <PluginPage registry={pluginRuntime.registry} meta={meta} tracks={state.tracks} />
            ) : (
              <div className="empty-state">
                <div className="empty-state-icon">
                  <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.2">
                    <rect x="3" y="3" width="18" height="18" rx="2"/>
                    <path d="M12 8v8M8 12h8"/>
                  </svg>
                </div>
                <h2>Plugins unavailable</h2>
                <p>Plugin runtime failed to initialize. Restart FreePlayer and try again.</p>
              </div>
            )
          ) : state.view === VIEWS.SETTINGS ? (
            <Settings
              importMode={state.importMode}
              onImportModeChange={handleImportModeChange}
              libraryDir={state.libraryDir}
              onLibraryDirChange={(dir) => {
                dispatch({ type: 'SET', payload: { libraryDir: dir } });
                // Minor-1: the library changed — drop stale tracks so the
                // list reflects the new directory instead of erroring on play
                dispatch({ type: 'SET', payload: { tracks: [], currentTrack: null, queue: [], queueIndex: -1 } });
                loadTracks();
              }}
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
                    ? loadTracks
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
                  onSelectPlaylist={handleSelectPlaylist}
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
                  onCoverSaved={(coverPath) => dispatch({ type: 'SET_TRACK_FIELDS', payload: { id: state.currentTrack?.id, fields: { cover_path: coverPath } } })}
                  meta={meta}
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
        eqEnabled={state.eqEnabled}
        onOpenEq={() => window.freeplayer?.openEq?.()}
      />

      <MobileTabBar
        currentView={state.view}
        onNavigate={(v) => dispatch({ type: 'SET', payload: { view: v } })}
      />

      {state.importModalOpen && (
        <ImportModal
          onClose={() => dispatch({ type: 'SET', payload: { importModalOpen: false } })}
          onComplete={handleImportComplete}
          importMode={state.importMode}
        />
      )}

      {state.playlistModal && (
        <PlaylistModal
          mode={state.playlistModal.mode}
          playlist={state.playlistModal.playlist}
          allTracks={state.tracks}
          onClose={() => dispatch({ type: 'SET', payload: { playlistModal: null, pendingAddTrack: null } })}
          onSubmit={
            state.playlistModal.mode === 'create' ? handleCreatePlaylist :
            state.playlistModal.mode === 'rename' ? handleRenamePlaylist :
            handleUpdatePlaylistTracks
          }
        />
      )}
    </div>
  );
}
