import React from 'react';

export default function Sidebar({
  currentView, onNavigate, trackCount, onImport,
  playlists, activePlaylistId, onSelectPlaylist,
  onCreatePlaylist, onRenamePlaylist, onDeletePlaylist,
}) {
  const [playlistContextMenu, setPlaylistContextMenu] = React.useState(null);

  const navItems = [
    {
      id: 'library',
      label: 'Library',
      icon: (
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
          <path d="M9 18V5l12-2v13"/>
          <circle cx="6" cy="18" r="3"/>
          <circle cx="18" cy="16" r="3"/>
        </svg>
      ),
    },
    {
      id: 'now-playing',
      label: 'Now Playing',
      icon: (
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="12" cy="12" r="10"/>
          <polygon points="10 8 16 12 10 16 10 8" fill="currentColor" stroke="none"/>
        </svg>
      ),
    },
    {
      id: 'stats',
      label: 'Statistics',
      icon: (
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
          <line x1="18" y1="20" x2="18" y2="10"/>
          <line x1="12" y1="20" x2="12" y2="4"/>
          <line x1="6" y1="20" x2="6" y2="14"/>
        </svg>
      ),
    },
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
  ];

  return (
    <>
    <aside className="sidebar">
      <div className="sidebar-header">
        <div className="sidebar-logo">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none">
            <circle cx="12" cy="12" r="11" stroke="currentColor" strokeWidth="1.5"/>
            <circle cx="12" cy="12" r="4" fill="currentColor"/>
            <path d="M12 1v8M12 15v8M1 12h8M15 12h8" stroke="currentColor" strokeWidth="1" opacity="0.4"/>
          </svg>
          <span className="sidebar-title">FreePlayer</span>
        </div>
      </div>

      <nav className="sidebar-nav">
        {navItems.map((item) => (
          <button
            key={item.id}
            className={`nav-item ${currentView === item.id ? 'nav-item--active' : ''}`}
            onClick={() => onNavigate(item.id)}
          >
            <span className="nav-icon">{item.icon}</span>
            <span className="nav-label">{item.label}</span>
            {item.id === 'library' && trackCount > 0 && (
              <span className="nav-badge">{trackCount}</span>
            )}
          </button>
        ))}
      </nav>

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

      <div className="sidebar-footer">
        <button className="nav-item" onClick={onImport}>
          <span className="nav-icon">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
              <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
              <polyline points="17 8 12 3 7 8"/>
              <line x1="12" y1="3" x2="12" y2="15"/>
            </svg>
          </span>
          <span className="nav-label">Import Music</span>
        </button>
      </div>
    </aside>

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
    </>
  );
}
