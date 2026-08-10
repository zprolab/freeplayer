import { useState } from 'react';
import {
  IconMusicNote, IconPlayCircle, IconChartBar, IconPuzzle, IconGear,
  IconImport, IconList, IconPlus, IconEdit, IconTrash,
} from './icons';

export default function Sidebar({
  currentView, onNavigate, trackCount, onImport,
  playlists, activePlaylistId, onSelectPlaylist,
  onCreatePlaylist, onRenamePlaylist, onEditPlaylist, onDeletePlaylist,
}) {
  const [playlistContextMenu, setPlaylistContextMenu] = useState(null);

  const navItems = [
    {
      id: 'library',
      label: 'Library',
      icon: <IconMusicNote />,
    },
    {
      id: 'now-playing',
      label: 'Now Playing',
      icon: <IconPlayCircle />,
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
      id: 'plugins',
      label: 'Plugins',
      icon: <IconPuzzle />,
    },
    {
      id: 'settings',
      label: 'Settings',
      icon: <IconGear />,
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
            <IconPlus size={14} />
          </button>
        </div>

        <div className="sidebar-playlists-list">
          <button
            className={`nav-item ${activePlaylistId === null ? 'nav-item--active' : ''}`}
            onClick={() => onSelectPlaylist(null)}
          >
            <span className="nav-icon"><IconList /></span>
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
              <span className="nav-icon"><IconMusicNote /></span>
              <span className="nav-label">{pl.name}</span>
            </button>
          ))}
        </div>
      </div>

      <div className="sidebar-footer">
        <button className="nav-item" onClick={onImport}>
          <span className="nav-icon"><IconImport /></span>
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
              <IconEdit size={14} />
              Rename
            </button>
            <button className="context-menu-item" onClick={() => {
              onEditPlaylist(playlistContextMenu.playlist);
              setPlaylistContextMenu(null);
            }}>
              <IconList size={14} />
              Edit Tracks
            </button>
            <button className="context-menu-item" onClick={() => {
              onDeletePlaylist(playlistContextMenu.playlist.id);
              setPlaylistContextMenu(null);
            }}>
              <IconTrash size={14} />
              Delete
            </button>
          </div>
        </>
      )}
    </>
  );
}
