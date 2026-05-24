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
