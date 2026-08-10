import { validateManifest, API_VERSION } from './manifest';
import { loadPermissions, persistPermissions } from './permissions';
import { createEventBus, EVENT_CHANNELS, hookTimeout } from './hooks';

const AUDIT_LIMIT = 200;
const EVENT_TO_HOOK = {
  trackChanged: { activation: 'track:changed', hook: 'onTrackChanged' },
  playbackChanged: { activation: 'playback:changed', hook: 'onPlaybackChanged' },
};

function classify(raw) {
  try {
    if (raw.manifestRaw && raw.manifestRaw.apiVersion !== API_VERSION) {
      return { status: 'incompatible', lastError: `apiVersion ${raw.manifestRaw.apiVersion} != ${API_VERSION}` };
    }
    const r = validateManifest(raw.manifestRaw);
    return r.ok
      ? { status: 'disabled', lastError: '' }
      : { status: 'error', lastError: r.errors.join('; ') };
  } catch (err) {
    return { status: 'error', lastError: `manifest invalid: ${err.message || err}` };
  }
}

export function createRegistry(deps) {
  const { listPlugins, readFile, loader, log, getSetting, setSetting, uninstallPlugin } = deps;
  const plugins = new Map();
  const audit = new Map();
  const events = createEventBus();

  function record(id, patch) {
    const p = plugins.get(id);
    if (p) Object.assign(p, patch);
  }

  async function discover() {
    const seen = new Set();
    const userList = await listPlugins();
    for (const raw of userList) {
      seen.add(raw.id);
      const cls = classify(raw);
      const existing = plugins.get(raw.id);
      plugins.set(raw.id, {
        id: raw.id,
        manifest: cls.status === 'disabled' ? validateManifest(raw.manifestRaw).manifest : raw.manifestRaw,
        builtin: false,
        status: cls.status,
        perms: existing?.perms || { enabled: false, granted: [] },
        lastError: cls.lastError,
        hooks: null, deactivate: null,
      });
    }
    for (const [id, rec] of plugins) {
      if (!seen.has(id) && !rec.builtin) plugins.delete(id); // user plugin removed from disk
    }
  }

  function registerBuiltin({ id, manifestRaw, module }) {
    const cls = classify({ manifestRaw });
    plugins.set(id, {
      id,
      manifest: cls.status === 'disabled' ? validateManifest(manifestRaw).manifest : manifestRaw,
      builtin: true,
      status: cls.status,
      perms: { enabled: false, granted: [] },
      lastError: cls.lastError,
      hooks: null, deactivate: null,
      module,
    });
  }

  async function restoreState() {
    for (const [id, rec] of plugins) {
      // Only pristine 'disabled' plugins may resurrect from persisted perms;
      // 'error'/'incompatible' plugins must never silently flip back to
      // enabled just because an old permission blob exists.
      if (rec.status !== 'disabled') continue;
      const perms = await loadPermissions(id, getSetting);
      rec.perms = perms;
      if (perms.enabled) rec.status = 'enabled';
    }
  }

  async function enable(id, granted) {
    const p = plugins.get(id);
    if (!p || p.status === 'incompatible') throw new Error(`cannot enable ${id}`);
    p.perms = { enabled: true, granted };
    await persistPermissions(id, p.perms, setSetting);
    p.status = 'enabled';
  }

  async function disable(id) {
    const p = plugins.get(id);
    if (!p) return;
    if (p.status === 'active' && p.deactivate) {
      try { p.deactivate(); } catch { /* isolated */ }
    }
    p.status = 'disabled';
    p.hooks = null; p.deactivate = null;
    p.perms.enabled = false;
    await persistPermissions(id, p.perms, setSetting);
  }

  async function ensureActive(id) {
    const p = plugins.get(id);
    if (!p) throw new Error(`unknown plugin ${id}`);
    if (p.status === 'active') return p;
    if (p.status !== 'enabled') throw new Error(`plugin ${id} is not enabled`);
    try {
      const res = await loader.activate(id, {
        manifest: p.manifest, builtin: p.builtin, module: p.module, readFile,
        granted: p.perms.granted,
      });
      p.hooks = res.hooks;
      p.deactivate = res.deactivate;
      p.status = 'active';
      p.lastError = '';
    } catch (err) {
      p.status = 'error';
      p.lastError = String(err.message || err);
      throw err;
    }
    return p;
  }

  async function invokeHook(id, name, payload) {
    const p = plugins.get(id);
    if (!p || (p.status !== 'enabled' && p.status !== 'active')) return null;
    try {
      const rec = await ensureActive(id);
      const fn = rec.hooks[name];
      if (typeof fn !== 'function') return null;
      const res = await hookTimeout(() => fn(payload), 15000);
      logOp(id, `hook:${name}`, 'ok', true);
      return res;
    } catch (err) {
      record(id, { lastError: String(err.message || err) });
      log(id, 'error', `hook ${name}: ${err.message || err}`);
      logOp(id, `hook:${name}`, String(err.message || err), false);
      return null;
    }
  }

  async function emit(channel, payload) {
    if (!EVENT_CHANNELS.includes(channel)) throw new Error(`unknown channel ${channel}`);
    events.emit(channel, payload);
    const map = EVENT_TO_HOOK[channel];
    for (const [id, p] of plugins) {
      if (p.status !== 'enabled' && p.status !== 'active') continue;
      // Raw manifests of error plugins may lack activationEvents entirely.
      if (!(p.manifest.activationEvents || []).includes(map.activation)) continue;
      await invokeHook(id, map.hook, payload);
    }
  }

  function logOp(pluginId, op, detail, ok = true) {
    const entry = { at: new Date().toISOString(), op, detail, ok };
    const list = audit.get(pluginId) || [];
    list.push(entry);
    while (list.length > AUDIT_LIMIT) list.shift();
    audit.set(pluginId, list);
  }

  function getAuditLog(pluginId) { return [...(audit.get(pluginId) || [])]; }

  async function uninstall(id) {
    const p = plugins.get(id);
    if (!p) return;
    if (p.status === 'active' && p.deactivate) { try { p.deactivate(); } catch { /* */ } }
    if (!p.builtin) {
      await uninstallPlugin(id);
      // Clear persisted perms so the plugin cannot resurrect on restart.
      // The in-memory audit log is session-scoped and dies with it by design.
      await setSetting({ key: `plugin_perms_${id}`, value: '' });
    }
    plugins.delete(id);
  }

  async function refresh() {
    await discover();
    await restoreState();
  }

  return {
    discover, registerBuiltin, restoreState, refresh,
    enable, disable, ensureActive, invokeHook, emit,
    subscribe: (c, cb) => events.on(c, cb),
    getPlugins: () => [...plugins.values()],
    getPlugin: (id) => plugins.get(id),
    logOp, getAuditLog, uninstall,
  };
}
