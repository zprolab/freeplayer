import React, { useState } from 'react';
import EditModal from './EditModal';
import PlaylistMenu from './PlaylistMenu';

function formatDuration(seconds) {
  if (!seconds || !isFinite(seconds)) return '--:--';
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, '0')}`;
}

const SORT_COLUMNS = [
  { key: 'title', label: 'Title', width: 'auto' },
  { key: 'artist', label: 'Artist', width: '180px' },
  { key: 'album', label: 'Album', width: '200px' },
  { key: 'duration', label: 'Duration', width: '90px' },
  { key: 'imported_at', label: 'Added', width: '130px' },
];

export default function Library({
  tracks, onPlay, currentTrack, isPlaying, sortBy, sortDir, onSort, onTracksChanged,
  activePlaylistId, playlists, onAddToPlaylist, onRemoveFromPlaylist, onCreatePlaylistForTrack,
}) {
  const [contextMenu, setContextMenu] = useState(null);
  const [editTrack, setEditTrack] = useState(null);
  const [playlistSubmenu, setPlaylistSubmenu] = useState(null);

  const handleRowClick = (track) => {
    onPlay(track, tracks);
  };

  const handleContextMenu = (e, track) => {
    e.preventDefault();
    setContextMenu({ x: e.clientX, y: e.clientY, track });
  };

  const handleEdit = () => {
    if (contextMenu) {
      setEditTrack(contextMenu.track);
      setContextMenu(null);
    }
  };

  const handleDelete = async () => {
    if (contextMenu) {
      await window.freeplayer.deleteTrack(contextMenu.track.id);
      setContextMenu(null);
      onTracksChanged?.();
    }
  };

  const handleEditSaved = () => {
    setEditTrack(null);
    onTracksChanged?.();
  };

  const handleRemoveFromPlaylist = async () => {
    if (contextMenu) {
      onRemoveFromPlaylist(contextMenu.track.id);
      setContextMenu(null);
    }
  };

  const handleUploadLrc = async () => {
    if (contextMenu) {
      await window.freeplayer.uploadLrc(contextMenu.track.id);
      setContextMenu(null);
    }
  };

  const handleRemoveLrc = async () => {
    if (contextMenu) {
      await window.freeplayer.removeLrc(contextMenu.track.id);
      setContextMenu(null);
    }
  };

  if (tracks.length === 0) {
    return (
      <div className="empty-state">
        <div className="empty-state-icon">
          <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.2">
            <path d="M9 18V5l12-2v13"/>
            <circle cx="6" cy="18" r="3"/>
            <circle cx="18" cy="16" r="3"/>
          </svg>
        </div>
        <h3>No tracks yet</h3>
        <p>Import your music to start building your library.</p>
      </div>
    );
  }

  return (
    <div className="library">
      <div className="table-container">
        <table className="data-table">
          <thead>
            <tr>
              <th style={{ width: '44px' }}>#</th>
              {SORT_COLUMNS.map(col => (
                <th
                  key={col.key}
                  style={{ width: col.width, cursor: 'pointer' }}
                  onClick={() => onSort(col.key)}
                  className="sortable-th"
                >
                  <span className="th-content">
                    {col.label}
                    <span className={`sort-indicator ${sortBy === col.key ? 'active' : ''}`}>
                      {sortBy === col.key ? (sortDir === 'ASC' ? '↑' : '↓') : '↓'}
                    </span>
                  </span>
                </th>
              ))}
              <th style={{ width: '40px' }}></th>
            </tr>
          </thead>
          <tbody>
            {tracks.map((track, idx) => {
              const isActive = currentTrack && currentTrack.id === track.id;
              return (
                <tr
                  key={track.id}
                  className={`track-row ${isActive ? 'track-row--active' : ''}`}
                  onClick={() => handleRowClick(track)}
                  onContextMenu={(e) => handleContextMenu(e, track)}
                >
                  <td className="cell-index">
                    {isActive && isPlaying ? (
                      <span className="playing-indicator">
                        <span className="eq-bar" />
                        <span className="eq-bar" />
                        <span className="eq-bar" />
                      </span>
                    ) : (
                      <span className="index-num">{idx + 1}</span>
                    )}
                  </td>
                  <td className="cell-title">
                    <div className="title-wrap">
                      <span className={`track-title ${isActive ? 'track-title--active' : ''}`}>
                        {track.title}
                      </span>
                      <span className="track-format">{track.file_format}</span>
                    </div>
                  </td>
                  <td className="cell-artist">{track.artist}</td>
                  <td className="cell-album">{track.album}</td>
                  <td className="cell-duration mono">{formatDuration(track.duration)}</td>
                  <td className="cell-date mono">
                    {track.imported_at ? new Date(track.imported_at + 'Z').toLocaleDateString() : '--'}
                  </td>
                  <td className="cell-action">
                    <button
                      className="btn-icon"
                      onClick={(e) => {
                        e.stopPropagation();
                        onPlay(track, tracks);
                      }}
                      title="Play"
                    >
                      <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor">
                        <polygon points="5,3 13,8 5,13"/>
                      </svg>
                    </button>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {/* Context menu */}
      {contextMenu && (
        <>
          <div className="overlay" onClick={() => setContextMenu(null)} />
          <div
            className="context-menu"
            style={{ left: contextMenu.x, top: contextMenu.y }}
          >
            <button className="context-menu-item" onClick={handleEdit}>
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/>
                <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/>
              </svg>
              Edit Metadata
            </button>
            <button
              className="context-menu-item"
              onClick={(e) => {
                e.stopPropagation();
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
            <button className="context-menu-item" onClick={handleUploadLrc}>
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/>
                <path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/>
                <line x1="8" y1="7" x2="16" y2="7"/>
                <line x1="8" y1="11" x2="14" y2="11"/>
                <line x1="12" y1="15" x2="12" y2="20"/>
                <line x1="9" y1="18" x2="15" y2="18"/>
              </svg>
              Upload Lyrics...
            </button>
            <button className="context-menu-item" onClick={handleRemoveLrc}>
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/>
                <path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/>
                <line x1="8" y1="7" x2="16" y2="7"/>
                <line x1="8" y1="11" x2="14" y2="11"/>
                <line x1="9" y1="15" x2="15" y2="15"/>
              </svg>
              Remove Lyrics
            </button>
            <button className="context-menu-item" onClick={handleDelete}>
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                <polyline points="3 6 5 6 21 6"/>
                <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>
              </svg>
              Delete Track
            </button>
            {activePlaylistId !== null && activePlaylistId !== undefined && (
              <button className="context-menu-item" onClick={handleRemoveFromPlaylist}>
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                  <line x1="18" y1="6" x2="6" y2="18"/>
                  <line x1="6" y1="6" x2="18" y2="18"/>
                </svg>
                Remove from Playlist
              </button>
            )}
          </div>
        </>
      )}

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

      {/* Edit modal */}
      {editTrack && (
        <EditModal
          track={editTrack}
          onClose={() => setEditTrack(null)}
          onSaved={handleEditSaved}
        />
      )}
    </div>
  );
}
