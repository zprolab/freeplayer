// Application settings keys and defaults — the one place that knows what
// persisted preferences exist.
//
// Before this, key names were string literals scattered across six files
// ('ui_mode' in two places, 'volume' in two, and so on). Nothing listed the
// full set, so a typo produced a silently-empty read and a write that stored a
// value nobody would ever read back — indistinguishable from "the setting does
// not exist yet". The Settings page and the native allowlist could also drift
// apart from the renderer without anything noticing.
//
// This module does NOT replace the client (src/core/client.js) — reads and
// writes still go through it. It supplies the names and defaults so those calls
// stop inventing strings at the call site.
//
// Plugin settings are deliberately NOT here: they live under a per-plugin
// namespace (`plugin.<id>.<key>`) with its own API, permission model and audit
// trail in src/plugins/. Mixing the two would imply a plugin could collide with
// an app key.

/**
 * Canonical keys. Plugin-prefixed keys are built by src/plugins/, not here.
 *
 * The value is the key as the native host expects it — this is wire format, not
 * a free-form label, so renaming one is a migration, not a refactor.
 */
export const KEYS = Object.freeze({
  libraryDir: 'library_dir',
  importMode: 'import_mode',
  volume: 'volume',
  defaultVolume: 'default_volume',
  defaultVisualizer: 'default_visualizer',
  visualizerQuality: 'visualizer_quality',
  monoFont: 'mono_font',
  uiMode: 'ui_mode',
  sidebarCollapsed: 'sidebar_collapsed',
  trayEnabled: 'tray_enabled',
  trayNotify: 'tray_notify',
  startHidden: 'start_hidden',
  lyricsBackend: 'meta.lyricsBackend',
  coverBackend: 'meta.coverBackend',
  metadataBackend: 'meta.metadataBackend',
});

/**
 * Defaults for keys whose absence has a defined meaning.
 *
 * Only the keys that are actually read with a fallback belong here. A key
 * without an entry is genuinely optional and its readers must handle undefined —
 * listing a default nobody reads would be documentation that lies.
 */
export const DEFAULTS = Object.freeze({
  [KEYS.importMode]: 'copy',
  [KEYS.visualizerQuality]: 'balanced',
  [KEYS.uiMode]: 'unified',
  [KEYS.lyricsBackend]: 'lrclib-lyrics',
  [KEYS.coverBackend]: 'itunes-cover',
  [KEYS.metadataBackend]: 'musicbrainz-meta',
});

/** The key with its default applied, or undefined when it has no default. */
export const defaultFor = (key) => DEFAULTS[key];

/** Every key the app persists, for tests and diagnostics. */
export const allKeys = () => Object.freeze(Object.values(KEYS));

/**
 * Coerce a stored value to a boolean.
 *
 * The host returns whatever sqlite holds, so the same logical toggle can arrive
 * as a real boolean, a number, or '1'/'true'/'yes'/'on'. Callers that each did
 * their own coercion disagreed on edge cases.
 */
export function asBool(value) {
  if (value === true || value === 1) return true;
  if (value === false || value === 0 || value == null) return false;
  if (typeof value === 'string') {
    const s = value.toLowerCase();
    return s === 'true' || s === '1' || s === '1.0' || s === 'yes' || s === 'on';
  }
  return false;
}

/** Stored toggles are written as '1'/'0' by the tray settings; keep that shape. */
export const boolToStored = (on) => (on ? '1' : '0');
