import { validateManifest, normalizePermissions, PERMISSIONS, API_VERSION } from './manifest';
import { sanitizeSvgIcon } from './svgIcon';
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

// For error/incompatible records the raw manifest is kept for display, but
// its icon must NEVER be injected as HTML — it was never validated by
// validateManifest. Sanitize it through the same sanitizer the validator
// uses (sanitizeSvgIcon) or drop it entirely. A hostile manifest with
// throwing getters degrades to an empty display manifest.
function displayManifest(raw, status) {
  if (status === 'disabled') return validateManifest(raw.manifestRaw).manifest;
  let m;
  try {
    m = raw.manifestRaw && typeof raw.manifestRaw === 'object' ? { ...raw.manifestRaw } : {};
  } catch {
    m = {};
  }
  if (typeof m.icon === 'string') m.icon = sanitizeSvgIcon(m.icon) || undefined;
  else m.icon = undefined;
  return m;
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
      // Replacing a record must not orphan an active plugin instance: its
      // worker/blob resources are released by deactivate, otherwise blob
      // URLs leak and event-bus listeners stay registered.
      if (existing && existing.status === 'active' && existing.deactivate) {
        try { existing.deactivate(); } catch { /* isolated */ }
        existing.hooks = null;
        existing.deactivate = null;
        existing.api = null;
      }
      plugins.set(raw.id, {
        id: raw.id,
        manifest: displayManifest(raw, cls.status),
        builtin: false,
        status: cls.status,
        perms: existing?.perms || { enabled: false, granted: [] },
        lastError: cls.lastError,
        hooks: null, deactivate: null, api: null,
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
      manifest: displayManifest({ manifestRaw }, cls.status),
      builtin: true,
      status: cls.status,
      perms: { enabled: false, granted: [] },
      lastError: cls.lastError,
      hooks: null, deactivate: null, api: null,
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

  // Only 'disabled' (fresh or after disable) plugins may be enabled; an
  // 'error' plugin (failed validation) must never be force-enabled, and
  // 'incompatible' never. 'enabled'/'active' are accepted so the permission
  // tab (updateGrants) can persist grant changes — for an active plugin the
  // new grants are pushed into the running worker via setGranted; the
  // direct (builtin) path re-applies them on next enable.
  async function enable(id, granted) {
    const p = plugins.get(id);
    if (!p) throw new Error(`cannot enable ${id}: unknown plugin`);
    if (p.status !== 'disabled' && p.status !== 'enabled' && p.status !== 'active') {
      throw new Error(`cannot enable ${id}: status ${p.status}`);
    }
    // Grants are intersected with the known permission set so a caller
    // cannot smuggle unvalidated strings into the persisted grant blob.
    const clean = normalizePermissions((granted || []).filter((g) => PERMISSIONS.includes(g)));
    p.perms = { enabled: true, granted: clean };
    await persistPermissions(id, p.perms, setSetting);
    if (p.status === 'active' && p.api?.setGranted) {
      p.api.setGranted(clean);
    }
    if (p.status !== 'active') p.status = 'enabled';  }

  async function disable(id) {
    const p = plugins.get(id);
    if (!p) return;
    if (p.status === 'active' && p.deactivate) {
      try { p.deactivate(); } catch { /* isolated */ }
    }
    events.removeOwner(id);
    p.status = 'disabled';
    p.hooks = null; p.deactivate = null; p.api = null;
    p.perms.enabled = false;
    await persistPermissions(id, p.perms, setSetting);
  }

  async function ensureActive(id) {
    const p = plugins.get(id);
    if (!p) throw new Error(`unknown plugin ${id}`);
    if (p.status === 'active') return p;
    if (p.status !== 'enabled') throw new Error(`plugin ${id} is not enabled`);
    // Concurrent callers (two emits/invokes in the same tick) must share one
    // activation, not double-activate the worker (orphaned blob URLs, hooks
    // running twice).
    if (p._activating) return p._activating;
    p._activating = (async () => {
      try {
        // Re-validate the manifest right before activation: an error-status
        // plugin may carry a raw manifest whose main/provides/permissions
        // were never validated. If validation fails, stay error/disabled.
        let manifest = p.manifest;
        const v = validateManifest(p.manifest);
        if (!v.ok) {
          p.status = 'error';
          p.lastError = `manifest invalid at activation: ${v.errors.join('; ')}`;
          log(id, 'error', p.lastError);
          throw new Error(p.lastError);
        }
        manifest = v.manifest;
        const res = await loader.activate(id, {
          manifest, builtin: p.builtin, module: p.module, readFile,
          granted: p.perms.granted,
        });
        p.hooks = res.hooks;
        p.deactivate = res.deactivate;
        // The loader result carries the permission-wrapped api plus (for
        // worker plugins) setGranted so grant edits can re-wrap the host
        // executor while the plugin stays active.
        p.api = res;
        // A worker crash AFTER activation must not leave a dead worker shown
        // as active: mark the record error-ed so the UI reflects it and
        // future invokes stop dispatching into a terminated worker.
        res.onCrash?.((message) => {
          if (p.status !== 'active') return;
          p.status = 'error';
          p.lastError = `worker crashed: ${message}`;
          p.hooks = null; p.deactivate = null; p.api = null;
          log(id, 'error', p.lastError);
        });
        p.status = 'active';
        p.lastError = '';
        return p;
      } catch (err) {
        p.status = 'error';
        p.lastError = String(err.message || err);
        throw err;
      } finally {
        p._activating = null; // cleared so a later retry is possible
      }
    })();
    return p._activating;
  }

  // invokeHook records the failure (lastError + audit) and then REJECTS —
  // callers like metadataRegistry rely on the rejection to distinguish
  // 'plugin-error' (timeout/missing hook) from 'not-found' (empty result).
  // Event emission wraps it in a catch so one broken plugin can't stall
  // delivery to the others.
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
      throw err;
    }
  }

  async function emit(channel, payload) {
    if (!EVENT_CHANNELS.includes(channel)) throw new Error(`unknown channel ${channel}`);
    events.emit(channel, payload);
    const map = EVENT_TO_HOOK[channel];
    const targets = [];
    for (const [id, p] of plugins) {
      if (p.status !== 'enabled' && p.status !== 'active') continue;
      // Raw manifests of error plugins may lack activationEvents entirely.
      if (!(p.manifest.activationEvents || []).includes(map.activation)) continue;
      targets.push(id);
    }
    // Delivery is concurrent (Promise.all) — a 15s hook timeout in one
    // plugin must not stall the others. Each failure is isolated; the
    // error path of invokeHook already recorded lastError + audit.
    await Promise.all(targets.map((id) => invokeHook(id, map.hook, payload).catch(() => null)));
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
    events.removeOwner(id);
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
