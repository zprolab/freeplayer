// The two states the shell shows INSTEAD of a view: the startup splash and the
// first-run prompt. Both are pure — no hooks, no data access, no dispatch — so
// they are safe to render anywhere and cannot take part in the mount ordering
// that the playback wiring depends on.
//
// Split out of App.jsx, which held them inline between the playback orchestration
// and the view switching.

import { Button } from '@/ui/components/index.js';
import logoUrl from '@assets/logo.svg';

/** Startup splash, shown while the initial library load is in flight. */
export function AppLoading() {
  return (
    <div className="app-loading">
      <div className="loading-logo"><img src={logoUrl} width={56} height={56} alt="" /></div>
      <div className="loading-spinner" />
      <span className="loading-text">Loading FreePlayer...</span>
    </div>
  );
}

/**
 * First-run prompt. Shown when the library directory has not been chosen yet, so
 * its only action opens the import/setup dialog.
 */
export function AppWelcome({ onSetup }) {
  return (
    <div className="empty-state">
      <div className="empty-state-icon">
        <svg width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.2">
          <path d="M9 18V5l12-2v13" /><circle cx="6" cy="18" r="3" /><circle cx="18" cy="16" r="3" />
        </svg>
      </div>
      <h2>Welcome to FreePlayer</h2>
      <p>Set up your music library to get started. Choose a directory where your music will be stored, then import your audio files.</p>
      <Button variant="primary" size="lg" onClick={onSetup}>
        Set Up Library
      </Button>
    </div>
  );
}
