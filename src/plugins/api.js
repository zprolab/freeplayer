import { createPermissionProxy } from '@/plugins/permissions.js';

const UPDATE_WHITELIST = ['title', 'artist', 'album', 'genre', 'year', 'track_number'];
const RATE_WINDOW_MS = 10000;
const RATE_MAX = 20;
// Per-call payload caps. The rate limit alone does not bound SIZE: 20 calls per
// 10s of an unbounded lyrics/cover payload let a metadata:write plugin write
// arbitrarily large files into the user's library. Mirrors the 512KB cap the
// metadataRegistry fetch path already applies to the same native writers.
const MAX_LYRICS_CHARS = 256 * 1024;
const MAX_COVER_B64_CHARS = 512 * 1024;
const MAX_FIELD_CHARS = 4096;
const MAX_YEAR = 9999;

function makeRateLimit() {
  let hits = [];
  return () => {
    const now = Date.now();
    hits = hits.filter((t) => now - t < RATE_WINDOW_MS);
    if (hits.length >= RATE_MAX) return false;
    hits.push(now);
    return true;
  };
}

// Host integration (Task 10 Step 5b): player/events/audio come from the app
// runtime via window.__fpRuntimeState when the caller passes null — App.jsx
// writes the real bridge there so lazily-activated plugins always see a live
// player, event bus and audio source without rebuilding the api.
function runtimeBridge() {
  return (typeof window !== 'undefined' && window.__fpRuntimeState) || {};
}

// api.settings.* must never reach the global settings table: a plugin with
// settings:read could otherwise read other plugins' secrets
// (plugin.<id>.apiToken) and the plugin_perms_* blobs, and settings:write
// could rewrite other plugins' permissions. Every read/write is forced into
// the plugin's own namespace `plugin.<pluginId>.<key>` (keys already under
// that exact namespace are not double-prefixed).
function scopedSettingKey(pluginId, key) {
  const prefix = `plugin.${pluginId}.`;
  return key.startsWith(prefix) ? key : prefix + key;
}

export function createPluginApi(pluginId, granted, deps) {
  const rate = makeRateLimit();
  const gateWrite = (method) => (...args) => {
    if (!rate()) return Promise.reject(new Error('rate limit'));
    return Promise.resolve().then(() => method(...args));
  };
  const rt = runtimeBridge();
  const noop = () => {};
  const player = deps.player || rt.player || {
    getState: () => ({ isPlaying: false, currentTime: 0, duration: 0 }),
    getTrack: () => null,
    play: noop, pause: noop, seek: noop, next: noop, previous: noop, setVolume: noop,
  };
  const events = deps.events || rt.events || { on: noop, off: noop, removeOwner: noop };
  const audio = (deps.bridge && deps.bridge.audio) || rt.audio || { getSource: () => null };
  return {
    http: {
      getJson: (url) => deps.bridge.http.getJson(url),
      getBase64: (url) => deps.bridge.http.getBase64(url),
    },
    player: {
      getState: () => player.getState(),
      getTrack: () => player.getTrack(),
      play: () => player.play(),
      pause: () => player.pause(),
      seek: (t) => player.seek(t),
      next: () => player.next(),
      previous: () => player.previous(),
      setVolume: (v) => player.setVolume(v),
    },
    audio: {
      getSource: () => audio.getSource(),
    },
    metadata: {
      getTrackInfo: (id) => deps.bridge.metadata.getTrackInfo(id),
      getLyrics: (id) => deps.bridge.metadata.getLyrics(id),
      getCover: (id) => deps.bridge.metadata.getCover(id),
      saveLyrics: gateWrite((id, content) => {
        const text = typeof content === 'string' ? content : '';
        if (text.length > MAX_LYRICS_CHARS) return Promise.reject(new Error('lyrics too large'));
        return deps.bridge.metadata.saveLyrics(id, text);
      }),
      saveCover: gateWrite((id, base64) => {
        const data = typeof base64 === 'string' ? base64 : '';
        if (data.length > MAX_COVER_B64_CHARS) return Promise.reject(new Error('cover too large'));
        return deps.bridge.metadata.saveCover(id, data);
      }),
      updateTrack: gateWrite((id, fields) => {
        const clean = {};
        for (const k of UPDATE_WHITELIST) {
          const v = fields?.[k];
          if (v === undefined) continue;
          if (k === 'year') {
            const y = Number(v);
            if (!Number.isFinite(y) || y < 0 || y > MAX_YEAR) continue;
            clean[k] = Math.round(y);
            continue;
          }
          if (k === 'track_number') {
            const n = Number(v);
            if (!Number.isFinite(n) || n < 0) continue;
            clean[k] = Math.round(n);
            continue;
          }
          // Text fields: bound the length and drop null (a NULL artist/album
          // reaches UI code that assumes strings — e.g. TrackPicker's search).
          if (v == null) continue;
          clean[k] = String(v).slice(0, MAX_FIELD_CHARS);
        }
        return deps.bridge.metadata.updateTrack(id, clean);
      }),
      removeLyrics: gateWrite((id) => deps.bridge.metadata.removeLyrics(id)),
    },
    settings: {
      get: (key) => deps.settings.get(scopedSettingKey(pluginId, key)),
      set: (key, value) => deps.settings.set(scopedSettingKey(pluginId, key), value),
    },
    pluginSettings: {
      get: (key) => deps.pluginSettings.get(`${pluginId}.${key}`),
      set: (key, value) => deps.pluginSettings.set(`${pluginId}.${key}`, value),
    },
    events: {
      // Listener registrations are owner-tagged so the host can drop every
      // listener of a plugin on deactivate (hooks.js createEventBus is
      // owner-aware). removeOwner is intentionally not reachable through the
      // permission proxy for plugins — the loader calls it on the ungated
      // executor api at deactivate time.
      on: (channel, cb) => events.on(channel, cb, pluginId),
      off: (channel, cb) => events.off(channel, cb),
      removeOwner: (ownerId) => events.removeOwner(ownerId),
    },
    log: (level, msg) => deps.log(pluginId, level, msg),
    meta: { info: { id: pluginId, name: '', version: '' } },
  };
}

export function wrapApi(pluginId, granted, api, onDenied) {
  return createPermissionProxy(pluginId, granted, api, onDenied);
}
