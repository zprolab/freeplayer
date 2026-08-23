import { IconMusicNote, IconPlayCircle, IconPuzzle, IconGear } from './icons';
import { VIEWS } from '../context/PlayerContext';

const TABS = [
  { id: VIEWS.LIBRARY, label: 'Library', icon: <IconMusicNote /> },
  { id: VIEWS.NOW_PLAYING, label: 'Now Playing', icon: <IconPlayCircle /> },
  { id: VIEWS.STATS, label: 'Statistics', icon: (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <line x1="18" y1="20" x2="18" y2="10"/>
      <line x1="12" y1="20" x2="12" y2="4"/>
      <line x1="6" y1="20" x2="6" y2="14"/>
    </svg>
  ) },
  { id: VIEWS.PLUGINS, label: 'Plugins', icon: <IconPuzzle /> },
  { id: VIEWS.SETTINGS, label: 'Settings', icon: <IconGear /> },
];

export default function MobileTabBar({ currentView, onNavigate }) {
  return (
    <nav className="mobile-tabbar">
      {TABS.map((t) => (
        <button
          key={t.id}
          className={`mobile-tabbar-item ${currentView === t.id ? 'mobile-tabbar-item--active' : ''}`}
          onClick={() => onNavigate(t.id)}
        >
          <span className="mobile-tabbar-icon">{t.icon}</span>
          <span className="mobile-tabbar-label">{t.label}</span>
        </button>
      ))}
    </nav>
  );
}
