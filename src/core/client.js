// The single seam between the app and the native bridge.
//
// `window.freeplayer` used to be called directly from 22 files — App.jsx alone
// made 37 calls. That has three costs the app paid for repeatedly:
//
//   * Tests must hand-stub the global before anything can run, so logic that
//     touches native state cannot be exercised without a fake bridge.
//   * The backend is unswappable: the bridge is the only data path.
//   * A method that silently returns the wrong SHAPE is invisible. Three of the
//     P0 defects fixed in 1.3.0 were exactly that (a createPlaylist that
//     returned a Bool read as a row id, a readFile that returned text where the
//     loader expected {source, bytes}, an updateTrack payload nested under a
//     `fields` key the host does not read). None of them raised.
//
// So this module does two things: it is the only place that touches the bridge,
// and it validates the shapes that have already bitten. Call sites use
// `client.library.tracks()` rather than `window.freeplayer.getTracks()`.
//
// It is deliberately dependency-free and React-free — the same discipline that
// made features/playback/engine.js a clean seam.

/** The raw bridge object, or null when running outside the shell (tests, web). */
function bridge() {
  return (typeof window !== 'undefined' && window.freeplayer) || null;
}

/**
 * Deferred so that importing this module never throws — tests and the web build
 * import it without a shell present. The rejection names the method, which is
 * what the old direct calls never did (they failed as "cannot read property of
 * undefined" somewhere upstack).
 */
function unavailable(method) {
  return Promise.reject(new Error(
    `native bridge unavailable: cannot call ${method}. ` +
    'This build is not running inside the FreePlayer shell (or the shell has not injected the bridge yet).',
  ));
}

/** Call one bridge method, rejecting with a named error when there is no bridge. */
function call(method, ...args) {
  const api = bridge();
  if (!api || typeof api[method] !== 'function') return unavailable(method);
  return api[method](...args);
}

/**
 * Register a native -> renderer callback channel.
 *
 * These three are not async calls: the bridge writes the handler onto a window
 * slot and the shell pushes into it. Registering twice silently replaces the
 * first handler, so this logs rather than pretending it chained — that silent
 * replacement is how a lost media-key handler would look like "keys sometimes
 * work".
 */
function on(channel, method, callback) {
  const api = bridge();
  if (!api || typeof api[method] !== 'function') return () => {};
  api[method](callback);
  return () => {
    const current = bridge();
    // The bridge has no "off"; clearing the slot is the only way to detach.
    if (current && current[method]) current[method](undefined);
  };
}

// ── settings ──────────────────────────────────────────────────────────────────
// The heaviest surface by far: getSetting/setSetting were called 29 + 22 times
// across the app, each component reading native state on its own. Everything
// that stores a preference goes through here.
export const settings = {
  get: (key) => call('getSetting', key),
  set: (key, value) => call('setSetting', { key, value }),
  /** Convenience for the common "read a string pref with a default" case. */
  async getOr(key, fallback) {
    const v = await call('getSetting', key).catch(() => undefined);
    return v === undefined || v === null || v === '' ? fallback : v;
  },
};

// ── library ──────────────────────────────────────────────────────────────────
export const library = {
  tracks: (params) => call('getTracks', params),
  track: (id) => call('getTrack', id),
  count: () => call('getTrackCount'),
  totalDuration: () => call('getTotalDuration'),
  isSetup: () => call('isSetup'),
  selectDirectory: () => call('selectLibraryDir'),
  scanDirectory: (dirPath) => call('scanDirectory', dirPath),
  importFiles: (data) => call('importFiles', data),
  importDialog: () => call('importDialog'),
  reset: () => call('resetDatabase'),
  stats: () => call('getStats'),
  history: (limit) => call('getPlayHistory', limit),
};

// ── tracks (metadata writes) ─────────────────────────────────────────────────
// The payload is FLAT: `updateTrack({ id, title, artist, ... })`. Nesting the
// columns under a `fields` key makes the host's column whitelist match nothing
// and it returns false without raising (1.3.0 shipped that bug for a while).
export const tracks = {
  update: (payload) => call('updateTrack', payload),
  remove: (id) => call('deleteTrack', id),
  resetFromFile: (id) => call('resetTrackFromFile', id),
  startPlay: (trackId) => call('playStart', trackId),
  endPlay: (data) => call('playEnd', data),
};

// ── playlists ────────────────────────────────────────────────────────────────
export const playlists = {
  list: () => call('getPlaylists'),
  tracks: (playlistId) => call('getPlaylistTracks', playlistId),
  /** Resolves to the NEW playlist's row id. See the check below. */
  async create(data) {
    const id = await call('createPlaylist', data);
    // The host once returned an exec success flag here, which the bridge wrapped
    // as NSNumber and serialised to JSON `true`; callers read it as a row id, so
    // `true` became id 1 and every playlist's tracks landed in playlist 1. Fail
    // loudly instead of writing to the wrong playlist.
    if (typeof id !== 'number' || !Number.isInteger(id) || id <= 0) {
      throw new Error(`createPlaylist returned ${JSON.stringify(id)} where a row id was expected`);
    }
    return id;
  },
  rename: (data) => call('renamePlaylist', data),
  remove: (playlistId) => call('deletePlaylist', playlistId),
  addTrack: (data) => call('addToPlaylist', data),
  addTracks: (data) => call('addTracksToPlaylist', data),
  setTracks: (data) => call('setPlaylistTracks', data),
  removeTrack: (data) => call('removeFromPlaylist', data),
};

// ── lyrics & cover art ───────────────────────────────────────────────────────
export const lyrics = {
  get: (trackId) => call('getLrc', trackId),
  set: (data) => call('setLrc', data),
  save: (trackId, content) => call('saveLrcContent', trackId, content),
  upload: (trackId) => call('uploadLrc', trackId),
  remove: (trackId) => call('removeLrc', trackId),
  getCover: (coverPath) => call('getCover', coverPath),
  saveCover: (trackId, base64) => call('saveCover', trackId, base64),
};

// ── playback side-channels ───────────────────────────────────────────────────
export const playback = {
  // Pass the BOOLEAN, not { isPlaying }: the bridge layer
  // (BridgeScript.swift) already wraps it as `{ isPlaying }` before invoking.
  // Passing a wrapped object here nested it twice, so the native side read a
  // dictionary where it expected NSNumber, the cast failed and it fell back to
  // `?? false` — the tray icon could never show Pause.
  sendState: (isPlaying) => call('sendPlaybackState', isPlaying),
  onControl: (cb) => on('control', 'onPlaybackControl', cb),
  onMediaKey: (cb) => on('mediakey', 'onMediaKey', cb),
};

// ── equalizer ────────────────────────────────────────────────────────────────
export const equalizer = {
  open: () => call('openEq'),
  getState: () => call('getEqState'),
  set: (data) => call('setEq', data),
  onChange: (cb) => on('eq', 'onEqChange', cb),
};

// ── window chrome / platform ─────────────────────────────────────────────────
export const shell = {
  platform: () => call('getPlatform'),
  // The bridge expects { dark }, not a bare boolean.
  // Same double-wrap trap as sendState: the bridge wraps this as `{ dark }`.
  setAppearance: (dark) => call('setAppearance', dark),
  finishOnboarding: () => call('finishOnboarding'),
  loginItem: () => call('getLoginItemSettings'),
  setLoginItem: (data) => call('setLoginItemSettings', data),
};

// ── http (native stack: no CORS, stable on unreliable links) ─────────────────
export const http = {
  getJson: (url) => call('httpGetJson', url),
  getBase64: (url) => call('httpGetBase64', url),
};

// ── diagnostics ──────────────────────────────────────────────────────────────
export const diagnostics = {
  log: (pluginId, level, message) => call('logDiagnostic', { pluginId, level, message }),
  enable: (enabled) => call('setDiagnosticsEnabled', !!enabled),
  path: () => call('getDiagnosticsPath'),
  clear: () => call('clearDiagnostics'),
};

// ── plugins ──────────────────────────────────────────────────────────────────
export const plugins = {
  list: () => call('listPlugins'),
  /**
   * Read a file from a plugin's directory.
   *
   * The host returns the file's TEXT. The loader's module graph collector wants
   * `{ source, bytes }` for its size caps, and assuming the wrong one made
   * `file.source` undefined so EVERY user plugin threw inside its own scan
   * (1.3.0). Normalising here means only one place has to know the wire shape.
   */
  async readFile(id, rel) {
    const raw = await call('readPluginFile', id, rel);
    if (raw === null || raw === undefined) return null;
    if (typeof raw === 'string') {
      return { source: raw, bytes: new TextEncoder().encode(raw).length };
    }
    return raw;
  },
  openDirectory: () => call('openPluginsDir'),
  uninstall: (id) => call('uninstallPlugin', id),
};

/** True when the native bridge has been injected (false in tests / web build). */
export const available = () => bridge() !== null;
