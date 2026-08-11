import { collectModuleGraph, rewriteModule, resolveRelPath } from './collect';
import { wrapApi } from './api';
import { hookTimeout } from './hooks';
import sandboxSource from './sandbox.js?raw';

export function blobUrlForModule(module) {
  return URL.createObjectURL(new Blob([module.source], { type: 'text/javascript' }));
}

// Host-side permission gate + executor dispatch for a plugin.
// `executorApi` is the real (ungated) api built from the app bridge; every
// worker apiCall is dispatched through `wrappedApi` so the permission proxy
// stays the single gate (a malicious plugin cannot reach the bridge around
// it). `setGranted` re-wraps with a new grant set — used when the user edits
// grants while a worker plugin is active (registry.enable).
function makeExecutor(pluginId, entry, deps) {
  const { createApi, onDenied } = deps;
  const { manifest, granted } = entry;
  let currentGranted = granted || manifest.permissions || [];
  const executorApi = createApi(pluginId);
  if (executorApi && executorApi.meta && executorApi.meta.info) {
    executorApi.meta.info = { id: pluginId, name: manifest.name, version: manifest.version };
  }
  let wrapped = wrapApi(pluginId, currentGranted, executorApi, (key) => onDenied(pluginId, key));
  return {
    wrapped,
    setGranted(next) {
      currentGranted = next || [];
      wrapped = wrapApi(pluginId, currentGranted, executorApi, (key) => onDenied(pluginId, key));
    },
    executorApi,
  };
}

function assertProvides(manifest, hooks) {
  if (manifest.provides?.lyrics && typeof hooks.fetchLyrics !== 'function') {
    throw new Error('missing hook: fetchLyrics');
  }
  if (manifest.provides?.cover && typeof hooks.fetchCover !== 'function') {
    throw new Error('missing hook: fetchCover');
  }
  if (manifest.provides?.metadata && typeof hooks.fetchMetadata !== 'function') {
    throw new Error('missing hook: fetchMetadata');
  }
}

export function createLoader(deps) {
  const {
    readFile, importUrl, createApi, onDenied,
    hookTimeoutMs = 15000, deactivateGraceMs = 50,
  } = deps;

  // Direct path: trusted bundled modules (builtins) and importUrl-based
  // modules run in the page realm — they are app code, not user plugins.
  async function runDirect(pluginId, manifest, granted, mainModule, blobUrls) {
    if (!mainModule || typeof mainModule.activate !== 'function') {
      throw new Error('activate failed: plugin does not export activate(api)');
    }
    const ex = makeExecutor(pluginId, { manifest, granted }, deps);
    const hooks = await hookTimeout(() => mainModule.activate(ex.wrapped), hookTimeoutMs);
    if (!hooks || typeof hooks !== 'object') {
      throw new Error('activate failed: activate(api) must return a hooks object');
    }
    assertProvides(manifest, hooks);
    return {
      hooks,
      deactivate: () => {
        for (const u of blobUrls) URL.revokeObjectURL(u);
        blobUrls.clear();
        // Drop any event-bus listeners the module registered via api.events
        // (owner-tracked by the bus, see hooks.js createEventBus).
        try { ex.executorApi.events?.removeOwner?.(pluginId); } catch { /* isolated */ }
        mainModule.deactivate?.();
      },
      api: ex.wrapped,
    };
  }

  // Worker path: user plugin modules are blob URLs imported INSIDE a
  // dedicated Web Worker. The worker has no access to the page realm; all
  // privileged calls round-trip through the permission-wrapped executor.
  // The worker is real containment — the 15s hookTimeout host-side may
  // reject while the plugin keeps running, which is safe because it cannot
  // touch the host (that is why it lives in the worker in the first place).
  async function activateWorker(pluginId, entry) {
    const { manifest, granted } = entry;
    const blobUrls = new Set();
    const graph = await collectModuleGraph(manifest.main, (rel) => readFile(pluginId, rel));
    if (graph.error) throw new Error(graph.error);
    // collectModuleGraph outputs post-order (deps first); by the time a
    // module is rewritten, its dependencies' final URLs are already in the map.
    const urls = new Map();
    for (const mod of graph.modules) {
      mod.source = rewriteModule(mod.source, (spec) => {
        const rel = resolveRelPath(mod.path, spec);
        const url = rel ? urls.get(rel) : null;
        return url ? { url } : null;
      });
      const url = blobUrlForModule(mod);
      blobUrls.add(url);
      urls.set(mod.path, url);
    }
    const mainUrl = urls.get(manifest.main);
    if (!mainUrl) throw new Error(`missing main module: ${manifest.main}`);

    // Worker bootstrap blob: config line first (module top-level reads it),
    // then the sandbox runtime. The worker is a module worker so the entry
    // blob URL is importable from it (same-origin, page-created).
    const config = {
      entry: mainUrl,
      meta: { id: pluginId, name: manifest.name, version: manifest.version },
    };
    const workerSource = `globalThis.__fpSandboxConfig = ${JSON.stringify(config)};\n` + sandboxSource;
    const workerUrl = URL.createObjectURL(new Blob([workerSource], { type: 'text/javascript' }));
    blobUrls.add(workerUrl);

    const ex = makeExecutor(pluginId, { manifest, granted }, deps);
    let worker = new Worker(workerUrl, { type: 'module' });
    let terminated = false;
    let seq = 0;
    let reportedHooks = new Set();
    const pendingHooks = new Map(); // seq -> { resolve, reject }
    const hostSubs = new Map(); // channel -> { forward, count }
    let onActivated = null;
    let onActivateError = null;

    const cleanup = () => {
      if (!terminated) {
        terminated = true;
        if (worker) { try { worker.terminate(); } catch { /* */ } }
        worker = null;
        for (const u of blobUrls) URL.revokeObjectURL(u);
        blobUrls.clear();
        for (const sub of hostSubs.values()) {
          try { ex.executorApi.events?.off?.(sub.channel, sub.forward); } catch { /* */ }
        }
        hostSubs.clear();
      }
      for (const p of pendingHooks.values()) p.reject(new Error('plugin worker terminated'));
      pendingHooks.clear();
    };

    const send = (msg) => {
      if (terminated || !worker) throw new Error('plugin worker terminated');
      worker.postMessage(msg);
    };

    const handleApiCall = async (msg) => {
      const dot = msg.method ? msg.method.indexOf('.') : -1;
      const ns = dot === -1 ? null : msg.method.slice(0, dot);
      const method = dot === -1 ? null : msg.method.slice(dot + 1);
      let reply;
      try {
        const fn = ns && method ? ex.wrapped[ns]?.[method] : null;
        if (typeof fn !== 'function') throw new Error(`unknown api method: ${msg.method}`);
        const result = await fn(...(Array.isArray(msg.args) ? msg.args : []));
        reply = { type: 'apiResult', seq: msg.seq, result: result === undefined ? null : result };
      } catch (err) {
        reply = { type: 'apiResult', seq: msg.seq, error: String((err && err.message) || err) };
      }
      try { send(reply); } catch { /* worker already gone */ }
    };

    const handleEventsOn = (channel) => {
      const sub = hostSubs.get(channel);
      if (sub) { sub.count += 1; return; }
      const forward = (payload) => {
        try { send({ type: 'event', channel, payload }); } catch { /* worker gone */ }
      };
      try {
        // Permission gate: events:on/off require player:read. A denied
        // subscription is dropped silently here — onDenied already logged it
        // and the plugin simply never receives events.
        ex.wrapped.events.on(channel, forward);
        hostSubs.set(channel, { channel, forward, count: 1 });
      } catch { /* permission denied */ }
    };

    const handleEventsOff = (channel) => {
      const sub = hostSubs.get(channel);
      if (!sub) return;
      sub.count -= 1;
      if (sub.count <= 0) {
        hostSubs.delete(channel);
        try { ex.executorApi.events?.off?.(channel, sub.forward); } catch { /* */ }
      }
    };

    const handleHookResult = (msg) => {
      const p = pendingHooks.get(msg.seq);
      if (!p) return;
      pendingHooks.delete(msg.seq);
      if (msg.error) p.reject(new Error(msg.error));
      else p.resolve(msg.result);
    };

    worker.onmessage = (e) => {
      const msg = e && e.data;
      if (!msg || typeof msg !== 'object') return;
      switch (msg.type) {
        case 'apiCall': handleApiCall(msg); break;
        case 'eventsOn': handleEventsOn(msg.channel); break;
        case 'eventsOff': handleEventsOff(msg.channel); break;
        case 'activated':
          if (onActivated) onActivated(msg.hooks || []);
          break;
        case 'activateError':
          if (onActivateError) onActivateError(String(msg.error || 'activate failed'));
          break;
        case 'hookResult': handleHookResult(msg); break;
        case 'log': deps.log?.(pluginId, msg.level, msg.msg); break;
        case 'deactivated': break; // host terminates after deactivateGraceMs
        default: break;
      }
    };
    worker.onerror = (e) => {
      const message = String((e && (e.message || e.error)) || 'worker error');
      if (!reportedHooks.size && onActivateError) onActivateError(message);
      else {
        for (const p of pendingHooks.values()) p.reject(new Error(message));
        pendingHooks.clear();
        cleanup();
      }
    };

    // Handshake: activate -> activated/activateError, bounded by hookTimeout.
    const handshake = new Promise((resolve, reject) => {
      onActivated = (names) => {
        reportedHooks = new Set(names);
        if (manifest.provides?.lyrics && !reportedHooks.has('fetchLyrics')) {
          reject(new Error('missing hook: fetchLyrics'));
          return;
        }
        if (manifest.provides?.cover && !reportedHooks.has('fetchCover')) {
          reject(new Error('missing hook: fetchCover'));
          return;
        }
        if (manifest.provides?.metadata && !reportedHooks.has('fetchMetadata')) {
          reject(new Error('missing hook: fetchMetadata'));
          return;
        }
        const remote = {};
        for (const name of reportedHooks) {
          remote[name] = (payload) => invokeHook(name, payload);
        }
        resolve(remote);
      };
      onActivateError = (message) => reject(new Error(message));
    });

    const invokeHook = (name, payload) => {
      if (!reportedHooks.has(name)) {
        return Promise.reject(new Error(`hook missing: ${name}`));
      }
      return new Promise((resolve, reject) => {
        const id = ++seq;
        pendingHooks.set(id, { resolve, reject });
        send({ type: 'invokeHook', hook: name, seq: id, payload });
      });
    };

    let hooks;
    try {
      send({ type: 'activate', pluginId });
      hooks = await hookTimeout(() => handshake, hookTimeoutMs);
    } catch (err) {
      cleanup();
      throw err;
    }

    return {
      hooks,
      deactivate: () => {
        if (terminated) return;
        try { worker.postMessage({ type: 'deactivate' }); } catch { /* */ }
        // Grace period lets the worker run mainModule.deactivate?.() before
        // hard termination. The worker is sandboxed, so even a hung
        // deactivate cannot harm the host — terminating is safe.
        setTimeout(() => {
          for (const sub of hostSubs.values()) {
            try { ex.executorApi.events?.off?.(sub.channel, sub.forward); } catch { /* */ }
          }
          hostSubs.clear();
          try { ex.executorApi.events?.removeOwner?.(pluginId); } catch { /* */ }
          cleanup();
        }, deactivateGraceMs);
      },
      api: ex.wrapped,
      setGranted: (next) => { ex.setGranted(next); },
    };
  }

  async function activate(pluginId, entry) {
    const { manifest, builtin, module: builtinModule, granted } = entry;
    if (builtinModule) {
      return runDirect(pluginId, manifest, granted, builtinModule, new Set());
    }
    if (builtin) {
      // Builtin flagged but no bundled module: load via manifest.main.
      const blobUrls = new Set();
      const mainModule = await importUrl(manifest.main);
      return runDirect(pluginId, manifest, granted, mainModule, blobUrls);
    }
    return activateWorker(pluginId, entry);
  }

  return { activate };
}
