import { useEffect, useMemo, useRef, useState } from 'react';
import Sidebar from '@/ui/shell/Sidebar.jsx';
import Library from '@/features/library/ui/Library.jsx';
import NowPlaying from '@/features/playback/ui/NowPlaying.jsx';
import Stats from '@/features/library/ui/Stats.jsx';
import PlayerBar from '@/features/playback/ui/PlayerBar.jsx';
import MobileTabBar from '@/ui/shell/MobileTabBar.jsx';
import ImportModal from '@/features/metadata/ui/ImportModal.jsx';
import Settings from '@/features/preferences/ui/Settings.jsx';
import PluginPage from '@/features/plugins/ui/PluginPage.jsx';
import PlaylistModal from '@/features/playlists/ui/PlaylistModal.jsx';
import EqWindow from '@/features/playback/ui/EqWindow.jsx';
import { AppLoading, AppWelcome } from '@/app/AppStates.jsx';
import { usePlayer, VIEWS } from '@/app/PlayerProvider.jsx';
import { usePlayback } from '@/features/playback/usePlayback.js';
import { buildShuffleOrder } from '@/features/playback/queue.js';
import { useLibrary } from '@/features/library/useLibrary.js';
import { sortTracks } from '@/features/library/store.js';
import { usePlaylists } from '@/features/playlists/usePlaylists.js';
import { useAutoMeta } from '@/features/metadata/useAutoMeta.js';
import { useVisualizerQuality } from '@/features/preferences/useVisualizerQuality.js';
import { audioEngine } from '@/features/playback/audio.js';
import { createRegistry } from '@/plugins/registry.js';
import { createMetadataRegistry } from '@/plugins/metadataRegistry.js';
import { BUILTIN_PLUGINS } from '@/plugins/builtin/index.js';
import diagnosticsManifest from '@/plugins/builtin/diagnostics/manifest.json';
import * as diagnosticsMain from '@/plugins/builtin/diagnostics/main.js';
import { createLoader } from '@/plugins/loader.js';
import { createPluginApi } from '@/plugins/api.js';
import { createEventBus } from '@/plugins/hooks.js';
import { Button, IconButton } from '@/ui/components/index.js';
import * as client from '@/core/client.js';
import { KEYS } from '@/core/settings.js';

// Plugin runtime singleton: registry + metadata registry assembled lazily on
// first use. Player/audio/events are resolved per plugin activation via
// window.__fpRuntimeState (written below), so lazily-activated plugins always
// see the live player bridge.
let pluginRuntime = null;

async function getPluginRuntime() {
  if (pluginRuntime) return pluginRuntime;
  const loader = createLoader({
    readFile: (pluginId, relPath) => client.plugins.readFile(pluginId, relPath),
    importUrl: (url) => import(/* @vite-ignore */ url),
    createApi: (pluginId) => createPluginApi(pluginId, [], {
      bridge: {
        http: {
          getJson: (url) => client.http.getJson(url),
          getBase64: (url) => client.http.getBase64(url),
        },
        metadata: {
          getTrackInfo: (id) => client.library.track(id),
          getLyrics: (id) => client.lyrics.get(id).then((r) => r && r.content),
          getCover: (id) => client.library.track(id).then((t) => (t ? client.lyrics.getCover(t.cover_path) : null)),
          saveLyrics: (id, content) => client.lyrics.save(id, content),
          saveCover: (id, base64) => client.lyrics.saveCover(id, base64),
          updateTrack: (id, fields) => client.tracks.update({ id, ...fields }),
          removeLyrics: (id) => client.lyrics.remove(id),
        },
        audio: null, // provided by App via window.__fpRuntimeState (Step 5b)
      },
      player: null, // provided by App via window.__fpRuntimeState (Step 5b)
      settings: {
        get: (key) => client.settings.get(key),
        set: (key, value) => client.settings.set(key, value),
      },
      pluginSettings: {
        get: (key) => client.settings.get(`plugin.${key}`),
        set: (key, value) => client.settings.set(`plugin.${key}`, JSON.stringify(value)),
      },
      log: (id, level, msg) => { console.warn(`[plugin:${id}]`, level, msg); client.diagnostics.log(id, level, msg); },
      events: null, // provided by App via window.__fpRuntimeState (Step 5b)
    }),
    onDenied: (pluginId, key) => console.warn(`[plugin:${pluginId}] permission denied: ${key}`),
  });
  const registry = createRegistry({
    listPlugins: () => client.plugins.list(),
    readFile: (pluginId, relPath) => client.plugins.readFile(pluginId, relPath),
    loader,
    log: (id, level, msg) => { console.warn(`[plugin:${id}]`, level, msg); client.diagnostics.log(id, level, msg); },
    getSetting: (k) => client.settings.get(k),
    setSetting: (data) => client.settings.set(data),
    uninstallPlugin: (id) => client.plugins.uninstall(id),
  });
  for (const b of BUILTIN_PLUGINS) registry.registerBuiltin(b);
  registry.registerBuiltin({ id: 'diagnostics-log', manifestRaw: diagnosticsManifest, builtin: true, module: diagnosticsMain });
  await registry.discover();
  await registry.restoreState();
  const meta = createMetadataRegistry({
    registry,
    getSetting: (k) => client.settings.get(k),
    saveLyrics: (trackId, content) => client.lyrics.save(trackId, content),
    saveCover: (trackId, base64) => client.lyrics.saveCover(trackId, base64),
    updateTrack: (id, fields) => client.tracks.update({ id, ...fields }),
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
  const [eqPanelOpen, setEqPanelOpen] = useState(false);
  const meta = pluginRuntime?.meta;

  useAutoMeta(state.currentTrack, meta, dispatch);

  // Analysis quality is surfaced both in Settings and inline on the visualizer;
  // one hook instance means both read and write the same live value.
  const {
    tier: visualizerQualityTier,
    changeQuality: changeVisualizerQuality,
    tiers: visualizerQualityTiers,
  } = useVisualizerQuality();

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
      'open-eq': () => client.equalizer.open(),
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
      // Don't hijack keys aimed at a control: Space on a focused SELECT opens
      // the dropdown (and used to also toggle playback), on a BUTTON it
      // activates the button. Editable content is excluded too.
      const tag = e.target.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || tag === 'BUTTON'
          || e.target.isContentEditable) return;
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
    const handler = ({ action }) => {
      const h = playbackHandlersRef.current;
      switch (action) {
        case 'playpause': h.togglePlayPause(); break;
        case 'next': h.handleNext(); break;
        case 'previous': h.handlePrev(); break;
      }
    };
    client.playback.onControl(handler);
  }, []); // register once; ref always has latest handlers

  // Equalizer: init from DB once, apply live curve changes
  const eqHandlerRef = useRef();
  eqHandlerRef.current = (s) => {
    if (!s) return;
    audioEngine.applyEq(s.gains, s.enabled);
    dispatch({ type: 'SET', payload: { eqEnabled: s.enabled } });
  };

  useEffect(() => {
    client.equalizer.getState().then((s) => {
      if (s) {
        audioEngine.applyEq(s.gains, s.enabled);
        dispatch({ type: 'SET', payload: { eqEnabled: s.enabled } });
      }
      }).catch((err) => console.warn('Failed to load EQ state:', err));
    // dispatch comes from useReducer, so its identity is stable and listing it
    // cannot retrigger the effect.
  }, [dispatch]);

  useEffect(() => {
    client.equalizer.onChange((s) => eqHandlerRef.current(s));
  }, []);

  // Appearance: Classic / Unified layout (defaults to Unified). Settings writes
// broadcast `fp-appearance-changed` so the switch applies without a restart.
useEffect(() => {
    const applyAppearance = () => {
      client.settings.get(KEYS.uiMode)
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
    // The playlist view cannot ask the host to sort — getPlaylistTracks takes no
    // sort parameters — so it uses the shared comparator that mirrors the host's
    // semantics (see features/library/store.js).
    return sortTracks(state.playlistTracks, state.sortBy, state.sortDir);
    // state.tracks is a deps prerequisite: loadTracks replaces it on startup
    // while the other deps stay identical, and without it the memo would
    // freeze at the initial [] and show an empty library forever.
  }, [state.tracks, state.activePlaylistId, state.playlistTracks, state.sortBy, state.sortDir]);

  if (state.isLoading) {
    return <AppLoading />;
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
                <Button variant="primary" onClick={() => dispatch({ type: 'SET', payload: { importModalOpen: true } })}>
                  <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                    <path d="M8 1v14M1 8h14" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"/>
                  </svg>
                  <span className="btn-label">Import</span>
                </Button>
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
              qualityTier={visualizerQualityTier}
              qualityTiers={visualizerQualityTiers}
              onQualityChange={changeVisualizerQuality}
              onResetDatabase={handleResetDatabase}
            />
          ) : !state.isSetup ? (
            <AppWelcome onSetup={() => dispatch({ type: 'SET', payload: { importModalOpen: true } })} />
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
                  onCoverSaved={(coverPath) => dispatch({ type: 'SET_TRACK_FIELDS', payload: { id: state.currentTrack?.id, fields: { cover_path: coverPath, cover_source: 'plugin' } } })}
                  onTrackReset={(fresh) => {
                    // "Reset from file" rewrote tags/cover in the DB from the
                    // audio file: mirror the fresh row (sources included) into
                    // the current track and the lists so the badges and cover
                    // follow immediately.
                    if (!fresh || !fresh.id) return;
                    const { id, ...fields } = fresh;
                    dispatch({ type: 'SET_TRACK_FIELDS', payload: { id, fields } });
                  }}
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
        onPlayModeChange={(m) => {
          // Entering shuffle must seed the play order: the reducer only clears
          // the stored order when *leaving* shuffle, so without this the empty
          // order made computeNextIndex fall back to the queue and "shuffle"
          // played the list in its stored order.
          if (m === 'shuffle' && state.queue.length > 0) {
            dispatch({
              type: 'SET_SHUFFLED_QUEUE',
              payload: buildShuffleOrder(state.queue, state.currentTrack?.id),
            });
          }
          dispatch({ type: 'SET_PLAY_MODE', payload: m });
        }}
        eqEnabled={state.eqEnabled}
        onOpenEq={() => {
          // iOS is a single-window app: the EQ renders in a sheet instead of
          // a native window (openEq is a no-op there).
          client.shell.platform()
            .then((p) => (p === 'ios' ? setEqPanelOpen(true) : client.equalizer.open()))
            .catch(() => client.equalizer.open());
        }}
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

      {eqPanelOpen && (
        <div className="eq-overlay" onClick={() => setEqPanelOpen(false)}>
          <div className="eq-sheet" onClick={(e) => e.stopPropagation()}>
            <IconButton size="lg" className="eq-sheet-close" label="Close equalizer" onClick={() => setEqPanelOpen(false)}>
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round">
                <path d="M6 6l12 12M18 6L6 18" />
              </svg>
            </IconButton>
            <EqWindow />
          </div>
        </div>
      )}
    </div>
  );
}
