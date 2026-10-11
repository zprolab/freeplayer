// The view-switching region of the shell: the top bar and the content area.
//
// Split out of App.jsx, which had grown to hold the playback orchestration, the
// plugin runtime wiring and the whole view switch in one component. This part is
// presentational — it owns no state and starts no work; every handler and every
// slice it reads is passed in from the shell, which is what keeps the mount
// ordering the playback wiring depends on unchanged.
//
// Props are grouped by domain rather than flattened, so a name collision cannot
// silently wire the wrong thing (the previous shape had ~20 handlers in one
// scope) and the signature documents what each area needs.

import { VIEWS } from '@/app/PlayerProvider.jsx';
import { Button } from '@/ui/components/index.js';
import { AppWelcome } from '@/app/AppStates.jsx';
import Library from '@/features/library/ui/Library.jsx';
import NowPlaying from '@/features/playback/ui/NowPlaying.jsx';
import Stats from '@/features/library/ui/Stats.jsx';
import Settings from '@/features/preferences/ui/Settings.jsx';
import PluginPage from '@/features/plugins/ui/PluginPage.jsx';

/** Header title per view. Playlist views show the playlist's name instead. */
function titleFor(state) {
  switch (state.view) {
    case VIEWS.LIBRARY:
      if (state.activePlaylistId === null) return 'Library';
      return state.playlists.find((p) => p.id === state.activePlaylistId)?.name || 'Playlist';
    case VIEWS.NOW_PLAYING: return 'Now Playing';
    case VIEWS.STATS: return 'Statistics';
    case VIEWS.PLUGINS: return 'Plugins';
    case VIEWS.SETTINGS: return 'Settings';
    default: return '';
  }
}

export default function MainContent({
  state,
  dispatch,
  displayedTracks,
  player,
  library,
  settings,
  playlists,
  plugins,
}) {
  const openImport = () => dispatch({ type: 'SET', payload: { importModalOpen: true } });

  return (
    <main className="main-content">
      <header className="top-bar">
        <div className="top-bar-left">
          <h1 className="page-title">{titleFor(state)}</h1>
          {state.view === VIEWS.LIBRARY && (
            <span className="track-count-badge">{displayedTracks.length} tracks</span>
          )}
        </div>
        <div className="top-bar-right">
          {state.view === VIEWS.LIBRARY && (
            <>
              <div className="search-box">
                <svg className="search-icon" width="16" height="16" viewBox="0 0 16 16" fill="none">
                  <path d="M11.742 10.344a6.5 6.5 0 1 0-1.397 1.398h-.001l3.85 3.85a1 1 0 0 0 1.415-1.414l-3.85-3.85-.017.016zm-5.242.156a5 5 0 1 1 0-10 5 5 0 0 1 0 10z" fill="currentColor" />
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
                    <svg width="12" height="12" viewBox="0 0 12 12"><path d="M1 1l10 10M11 1L1 11" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" /></svg>
                  </button>
                )}
              </div>
              <Button variant="primary" onClick={openImport}>
                <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                  <path d="M8 1v14M1 8h14" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
                </svg>
                <span className="btn-label">Import</span>
              </Button>
            </>
          )}
        </div>
      </header>

      <div className="content-area">
        {state.view === VIEWS.PLUGINS ? (
          plugins.runtime ? (
            <PluginPage registry={plugins.runtime.registry} meta={plugins.meta} tracks={state.tracks} />
          ) : (
            <div className="empty-state">
              <div className="empty-state-icon">
                <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.2">
                  <rect x="3" y="3" width="18" height="18" rx="2" />
                  <path d="M12 8v8M8 12h8" />
                </svg>
              </div>
              <h2>Plugins unavailable</h2>
              <p>Plugin runtime failed to initialize. Restart FreePlayer and try again.</p>
            </div>
          )
        ) : state.view === VIEWS.SETTINGS ? (
          <Settings
            importMode={state.importMode}
            onImportModeChange={settings.onImportModeChange}
            libraryDir={state.libraryDir}
            onLibraryDirChange={settings.onLibraryDirChange}
            defaultVolume={state.defaultVolume}
            onDefaultVolumeChange={settings.onDefaultVolumeChange}
            defaultVisualizer={state.defaultVisualizer}
            onDefaultVisualizerChange={settings.onDefaultVisualizerChange}
            qualityTier={settings.qualityTier}
            qualityTiers={settings.qualityTiers}
            onQualityChange={settings.onQualityChange}
            onResetDatabase={settings.onResetDatabase}
          />
        ) : !state.isSetup ? (
          <AppWelcome onSetup={openImport} />
        ) : (
          <>
            {state.view === VIEWS.LIBRARY && (
              <Library
                tracks={displayedTracks}
                onPlay={player.playTrackFromList}
                currentTrack={state.currentTrack}
                isPlaying={state.isPlaying}
                sortBy={state.sortBy}
                sortDir={state.sortDir}
                onTracksChanged={library.onTracksChanged}
                onSort={library.onSort}
                activePlaylistId={state.activePlaylistId}
                playlists={state.playlists}
                onAddToPlaylist={playlists.onAddToPlaylist}
                onRemoveFromPlaylist={playlists.onRemoveFromPlaylist}
                onCreatePlaylistForTrack={playlists.onCreatePlaylistForTrack}
                onSelectPlaylist={playlists.onSelectPlaylist}
              />
            )}
            {state.view === VIEWS.NOW_PLAYING && (
              <NowPlaying
                currentTrack={state.currentTrack}
                isPlaying={state.isPlaying}
                currentTime={state.currentTime}
                duration={state.duration}
                onSeek={player.onSeek}
                onTogglePlay={player.onTogglePlay}
                onNext={player.onNext}
                onPrev={player.onPrev}
                queue={state.queue}
                queueIndex={state.queueIndex}
                onPlayFromQueue={player.playTrackFromList}
                audioElement={player.audioElement}
                visualizerMode={state.visualizerMode}
                onVisualizerModeChange={(m) => dispatch({ type: 'SET', payload: { visualizerMode: m } })}
                onCoverSaved={(coverPath) => dispatch({
                  type: 'SET_TRACK_FIELDS',
                  payload: { id: state.currentTrack?.id, fields: { cover_path: coverPath, cover_source: 'plugin' } },
                })}
                onTrackReset={(fresh) => {
                  // "Reset from file" rewrote tags/cover in the DB from the audio
                  // file: mirror the fresh row (sources included) into the current
                  // track and the lists so the badges and cover follow immediately.
                  if (!fresh || !fresh.id) return;
                  const { id, ...fields } = fresh;
                  dispatch({ type: 'SET_TRACK_FIELDS', payload: { id, fields } });
                }}
                meta={plugins.meta}
              />
            )}
            {state.view === VIEWS.STATS && <Stats />}
          </>
        )}
      </div>
    </main>
  );
}
