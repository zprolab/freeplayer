import { createPermissionProxy } from './permissions';

const UPDATE_WHITELIST = ['title', 'artist', 'album', 'genre', 'year', 'track_number'];
const RATE_WINDOW_MS = 10000;
const RATE_MAX = 20;

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
  const events = deps.events || rt.events || { on: noop, off: noop };
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
      saveLyrics: gateWrite((id, content) => deps.bridge.metadata.saveLyrics(id, content)),
      saveCover: gateWrite((id, base64) => deps.bridge.metadata.saveCover(id, base64)),
      updateTrack: gateWrite((id, fields) => {
        const clean = {};
        for (const k of UPDATE_WHITELIST) if (fields[k] !== undefined) clean[k] = fields[k];
        return deps.bridge.metadata.updateTrack(id, clean);
      }),
      removeLyrics: gateWrite((id) => deps.bridge.metadata.removeLyrics(id)),
    },
    settings: {
      get: (key) => deps.settings.get(key),
      set: (key, value) => deps.settings.set({ key, value }),
    },
    pluginSettings: {
      get: (key) => deps.pluginSettings.get(`${pluginId}.${key}`),
      set: (key, value) => deps.pluginSettings.set(`${pluginId}.${key}`, value),
    },
    events: {
      on: (channel, cb) => events.on(channel, cb),
      off: (channel, cb) => events.off(channel, cb),
    },
    log: (level, msg) => deps.log(pluginId, level, msg),
    meta: { info: { id: pluginId, name: '', version: '' } },
  };
}

export function wrapApi(pluginId, granted, api, onDenied) {
  return createPermissionProxy(pluginId, granted, api, onDenied);
}
