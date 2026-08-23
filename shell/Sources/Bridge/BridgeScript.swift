// FreePlayer shell — injected renderer bridge script (same source string as
// the ObjC++ port; keep in sync with window.freeplayer API shape).

enum BridgeScript {
    static let source = #"""
    (() => {
      const pending = new Map();
      let seq = 0;

      const api = {
        // Import (M3: scan pipeline)
        importDialog: () => api._invoke('importDialog'),
        scanDirectory: (dirPath) => api._invoke('scanDirectory', dirPath),
        importFiles: (data) => api._invoke('importFiles', data),
        // Tracks
        getTracks: (params) => api._invoke('getTracks', params),
        getTrack: (id) => api._invoke('getTrack', id),
        updateTrack: (data) => api._invoke('updateTrack', data),
        deleteTrack: (id) => api._invoke('deleteTrack', id),
        getTrackCount: () => api._invoke('getTrackCount'),
        getTotalDuration: () => api._invoke('getTotalDuration'),
        // Network (native stack: no CORS, stable on unreliable links)
        httpGetJson: (url) => api._invoke('httpGetJson', url),
        httpGetBase64: (url) => api._invoke('httpGetBase64', url),
        // Playback history
        playStart: (trackId) => api._invoke('playStart', trackId),
        playEnd: (data) => api._invoke('playEnd', data),
        // History & Stats
        getPlayHistory: (limit) => api._invoke('getPlayHistory', limit),
        getStats: () => api._invoke('getStats'),
        // Cover art
        getCover: (coverPath) => api._invoke('getCover', coverPath),
        // Settings
        getSetting: (key) => api._invoke('getSetting', key),
        setSetting: (data) => api._invoke('setSetting', data),
        getPlatform: () => api._invoke('getPlatform'),
        isSetup: () => api._invoke('isSetup'),
        selectLibraryDir: () => api._invoke('selectLibraryDir'),
        resetDatabase: () => api._invoke('resetDatabase'),
        // Playlists
        createPlaylist: (data) => api._invoke('createPlaylist', data),
        getPlaylists: () => api._invoke('getPlaylists'),
        addToPlaylist: (data) => api._invoke('addToPlaylist', data),
        addTracksToPlaylist: (data) => api._invoke('addTracksToPlaylist', data),
        setPlaylistTracks: (data) => api._invoke('setPlaylistTracks', data),
        getPlaylistTracks: (playlistId) => api._invoke('getPlaylistTracks', playlistId),
        removeFromPlaylist: (data) => api._invoke('removeFromPlaylist', data),
        deletePlaylist: (playlistId) => api._invoke('deletePlaylist', playlistId),
        renamePlaylist: (data) => api._invoke('renamePlaylist', data),
        // LRC Lyrics
        getLrc: (trackId) => api._invoke('getLrc', trackId),
        setLrc: (data) => api._invoke('setLrc', data),
        uploadLrc: (trackId) => api._invoke('uploadLrc', trackId),
        removeLrc: (trackId) => api._invoke('removeLrc', trackId),
        saveLrcContent: (trackId, content) => api._invoke('saveLrcContent', trackId, content),
        saveCover: (trackId, base64) => api._invoke('saveCover', trackId, base64),
        // Media keys / tray (M5)
        onMediaKey: (callback) => { window.__freeplayerMediaKeyHandler = callback; },
        sendPlaybackState: (isPlaying) => api._invoke('sendPlaybackState', { isPlaying }),
        onPlaybackControl: (callback) => { window.__freeplayerPlaybackHandler = callback; },
        // Login item (M5)
        getLoginItemSettings: () => api._invoke('getLoginItemSettings'),
        setLoginItemSettings: (data) => api._invoke('setLoginItemSettings', data),
        // Equalizer (10-band)
        openEq: () => api._invoke('openEqWindow'),
        getEqState: () => api._invoke('getEqState'),
        setEq: (data) => api._invoke('setEq', data),
        onEqChange: (callback) => { window.__freeplayerEqHandler = callback; },
        // Appearance (window chrome shade)
        setAppearance: (dark) => api._invoke('setAppearance', { dark }),
        // First-run onboarding
        finishOnboarding: () => api._invoke('finishOnboarding'),
        // Plugins
        listPlugins: () => api._invoke('listPlugins'),
        readPluginFile: (id, rel) => api._invoke('readPluginFile', id, rel),
        openPluginsDir: () => api._invoke('openPluginsDir'),
        uninstallPlugin: (id) => api._invoke('uninstallPlugin', id),
      };

      api._invoke = (method, ...args) => new Promise((resolve, reject) => {
        const id = ++seq;
        pending.set(id, { resolve, reject });
        window.webkit.messageHandlers.freeplayer.postMessage({ id, method, args });
      });

      window.freeplayer = api;
      window.freeplayer._resolve = (id, result) => {
        const p = pending.get(id);
        if (!p) return;
        pending.delete(id);
        p.resolve(result);
      };
      window.freeplayer._reject = (id, err) => {
        const p = pending.get(id);
        if (!p) return;
        pending.delete(id);
        p.reject(new Error(String(err)));
      };
      // Tray menu -> playback control channel
      window.freeplayer._pushControl = (action) => {
        if (window.__freeplayerPlaybackHandler) {
          try { window.__freeplayerPlaybackHandler({ action }); } catch (e) {}
        }
      };
      // System media keys -> media key channel
      window.freeplayer._pushMediaKey = (action) => {
        if (window.__freeplayerMediaKeyHandler) {
          try { window.__freeplayerMediaKeyHandler(action); } catch (e) {}
        }
      };
      // Equalizer state -> EQ handler channel
      window.freeplayer._pushEq = (state) => {
        if (window.__freeplayerEqHandler) {
          try { window.__freeplayerEqHandler(state); } catch (e) {}
        }
      };

      // ── Window drag shim ──
      // WKWebView strips -webkit-app-region (Chromium-only), so map the app's
      // known regions directly. Keep in sync with App.css -webkit-app-region rules.
      const DRAG_SEL = '.top-bar, .sidebar, .sidebar-header, .sidebar-logo';
      const NO_DRAG_SEL = '.top-bar-right, .sidebar-nav, .sidebar-footer, .nav-item,'
        + ' button, input, textarea, select, a, [contenteditable]';

      document.addEventListener('mousedown', (e) => {
        if (e.button !== 0) return;
        const t = e.target;
        if (!t.closest) return;
        if (t.closest(NO_DRAG_SEL)) return;
        if (!t.closest(DRAG_SEL)) return;
        try {
          window.webkit.messageHandlers.freeplayer.postMessage({
            id: 0, method: '__dragStart', args: [e.screenX, e.screenY],
          });
          e.preventDefault();
        } catch (err) {}
      });

      // ── Console capture ──
      ['log', 'warn', 'error', 'info'].forEach((lv) => {
        const orig = console[lv];
        console[lv] = (...a) => {
          orig.apply(console, a);
          try {
            window.webkit.messageHandlers.freeplayer.postMessage({
              id: 0, method: '__console', args: [lv, a.map((x) => {
                if (x instanceof Error) return (x.stack || x.message).slice(0, 1200);
                try { return JSON.stringify(x); } catch { return String(x); }
              }).join(' ')],
            });
          } catch (e) {}
        };
      });
      window.addEventListener('error', (e) => {
        try {
          window.webkit.messageHandlers.freeplayer.postMessage({
            id: 0, method: '__console',
            args: ['error', 'window.onerror: ' + (e.message || '') + ' @ ' + (e.filename || '') + ':' + (e.lineno || '')],
          });
        } catch (err) {}
      });
      window.addEventListener('unhandledrejection', (e) => {
        try {
          const r = e.reason;
          window.webkit.messageHandlers.freeplayer.postMessage({
            id: 0, method: '__console',
            args: ['error', 'unhandledrejection: ' + (r && (r.stack || r.message) || String(r)).slice(0, 1200)],
          });
        } catch (err) {}
      });

      window.webkit.messageHandlers.freeplayer.postMessage({ id: 0, method: '__ready', args: [] });
    })();
    """#
}