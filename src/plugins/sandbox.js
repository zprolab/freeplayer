// Worker-side plugin runtime.
//
// This file is embedded (as raw source) into a worker blob by loader.js:
//   blob = new Blob([configLine + sandboxSource], { type: 'text/javascript' })
//   new Worker(blobUrl, { type: 'module' })
//
// It runs INSIDE a Web Worker, fully isolated from the page realm. The
// plugin module graph it imports (blob URLs) has NO access to
// window.freeplayer, the DOM, page globals or eval of page scope — all
// privileged api calls are round-tripped to the host via postMessage and
// gated there by the permission proxy. Everything in this file is
// self-contained: no imports, no page APIs.
//
// Message protocol (host <-> worker):
//   host -> worker:
//     { type: 'activate', pluginId }            trigger import + activate
//     { type: 'invokeHook', hook, seq, payload } invoke one reported hook
//     { type: 'deactivate' }                    run mainModule.deactivate?.()
//     { type: 'apiResult', seq, result, error } response to an apiCall
//     { type: 'event', channel, payload }       forwarded app event
//   worker -> host:
//     { type: 'activated', hooks: [names] }     activation succeeded
//     { type: 'activateError', error }          activation failed
//     { type: 'hookResult', seq, result, error } hook invocation result
//     { type: 'apiCall', seq, method, args }    execute api.<method> host-side
//     { type: 'eventsOn', channel }             plugin registered a listener
//     { type: 'eventsOff', channel }            plugin removed last listener
//     { type: 'log', level, msg }               plugin log line
//
// The config line (prepended by the host) must define __fpSandboxConfig:
//   { entry: <blob url of the plugin main module>, meta: { id, name, version } }

/* global __fpSandboxConfig */
const config = globalThis.__fpSandboxConfig;
if (!config || typeof config.entry !== 'string') {
  throw new Error('sandbox: missing __fpSandboxConfig.entry');
}

const HOOK_NAMES = [
  'fetchLyrics', 'fetchCover', 'fetchMetadata',
  'onTrackChanged', 'onPlaybackChanged',
];

// Namespaces/methods the plugin may call; each maps to a host round-trip.
const API_METHODS = {
  http: ['getJson', 'getBase64'],
  player: ['getState', 'getTrack', 'play', 'pause', 'seek', 'next', 'previous', 'setVolume'],
  audio: ['getSource'],
  metadata: ['getTrackInfo', 'getLyrics', 'getCover', 'saveLyrics', 'saveCover', 'updateTrack', 'removeLyrics'],
  settings: ['get', 'set'],
  pluginSettings: ['get', 'set'],
};

let seq = 0;
const pendingApi = new Map(); // seq -> { resolve, reject }
const eventCbs = new Map(); // channel -> Set<cb>
let mainModule = null;
let hooks = null;

function post(msg) {
  globalThis.postMessage(msg);
}

function makeApiShim() {
  const api = {};
  for (const [ns, methods] of Object.entries(API_METHODS)) {
    api[ns] = {};
    for (const method of methods) {
      api[ns][method] = (...args) => new Promise((resolve, reject) => {
        const id = ++seq;
        pendingApi.set(id, { resolve, reject });
        post({ type: 'apiCall', seq: id, method: `${ns}.${method}`, args });
      });
    }
  }
  // events are handled locally (callbacks cannot cross the postMessage
  // boundary); the host forwards { type: 'event' } messages after gating the
  // subscription permission (events:on/off require player:read).
  api.events = {
    on(channel, cb) {
      if (typeof cb !== 'function') return;
      if (!eventCbs.has(channel)) eventCbs.set(channel, new Set());
      const set = eventCbs.get(channel);
      set.add(cb);
      if (set.size === 1) post({ type: 'eventsOn', channel });
    },
    off(channel, cb) {
      const set = eventCbs.get(channel);
      if (!set) return;
      set.delete(cb);
      if (set.size === 0) {
        eventCbs.delete(channel);
        post({ type: 'eventsOff', channel });
      }
    },
  };
  api.log = (level, msg) => post({ type: 'log', level, msg });
  api.meta = { info: { id: config.meta.id, name: config.meta.name, version: config.meta.version } };
  return api;
}

function handleActivate(pluginId) {
  (async () => {
    const mod = await import(config.entry);
    mainModule = mod;
    if (typeof mainModule.activate !== 'function') {
      throw new Error('activate failed: plugin does not export activate(api)');
    }
    const result = await mainModule.activate(makeApiShim());
    if (!result || typeof result !== 'object') {
      throw new Error('activate failed: activate(api) must return a hooks object');
    }
    hooks = {};
    const names = [];
    for (const name of HOOK_NAMES) {
      if (typeof result[name] === 'function') {
        hooks[name] = result[name];
        names.push(name);
      }
    }
    post({ type: 'activated', hooks: names, pluginId });
  })().catch((err) => {
    post({ type: 'activateError', error: String((err && err.message) || err) });
  });
}

globalThis.onmessage = (e) => {
  const msg = e && e.data;
  if (!msg || typeof msg !== 'object') return;
  switch (msg.type) {
    case 'activate':
      handleActivate(msg.pluginId);
      break;
    case 'invokeHook': {
      const { hook, seq: hookSeq, payload } = msg;
      const fn = hooks && hooks[hook];
      if (typeof fn !== 'function') {
        post({ type: 'hookResult', seq: hookSeq, error: `hook missing: ${hook}` });
        return;
      }
      Promise.resolve()
        .then(() => fn(payload))
        .then((result) => post({ type: 'hookResult', seq: hookSeq, result: result === undefined ? null : result }))
        .catch((err) => post({ type: 'hookResult', seq: hookSeq, error: String((err && err.message) || err) }));
      break;
    }
    case 'deactivate':
      try { if (mainModule && typeof mainModule.deactivate === 'function') mainModule.deactivate(); } catch { /* isolated */ }
      post({ type: 'deactivated' });
      break;
    case 'apiResult': {
      const p = pendingApi.get(msg.seq);
      if (!p) return;
      pendingApi.delete(msg.seq);
      if (msg.error) p.reject(new Error(msg.error));
      else p.resolve(msg.result);
      break;
    }
    case 'event': {
      const set = eventCbs.get(msg.channel);
      if (!set) return;
      for (const cb of [...set]) {
        try { cb(msg.payload); } catch { /* plugin listener error is isolated */ }
      }
      break;
    }
    default:
      break;
  }
};
