import { normalizePermissions } from './manifest';

const DOMAIN_LEVEL = {
  http: 1, player: 2, audio: 1, metadata: 3, settings: 3,
};

const LEVEL_RANK = { read: 1, write: 2, admin: 3 };

const METHOD_LEVEL = {
  http: { getJson: 'read', getBase64: 'read' },
  player: {
    getState: 'read', getTrack: 'read',
    play: 'write', pause: 'write', seek: 'write', next: 'write', previous: 'write', setVolume: 'write',
  },
  audio: { getSource: 'read' },
  metadata: {
    getTrackInfo: 'read', getLyrics: 'read', getCover: 'read',
    saveLyrics: 'write', saveCover: 'write', updateTrack: 'write', removeLyrics: 'write',
    deleteTrack: 'admin',
  },
  settings: { get: 'read', set: 'write' },
  events: { on: 'read', off: 'read' },
};

const ALIAS_DOMAIN = { events: 'player' };

function grantedRank(granted, domain) {
  let max = 0;
  for (const p of granted) {
    const [d, l] = p.split(':');
    if (d !== domain) continue;
    if (!LEVEL_RANK[l]) return Infinity;
    if (LEVEL_RANK[l] > max) max = LEVEL_RANK[l];
  }
  return max;
}

export function checkPermission(granted, permission) {
  const [domain, level] = permission.split(':');
  const effectiveDomain = ALIAS_DOMAIN[domain] || domain;
  if (!DOMAIN_LEVEL[effectiveDomain] && !METHOD_LEVEL[domain]) return false;
  if (LEVEL_RANK[level]) return grantedRank(granted, effectiveDomain) >= LEVEL_RANK[level];
  const methodLevel = METHOD_LEVEL[domain]?.[level];
  if (methodLevel) return grantedRank(granted, effectiveDomain) >= LEVEL_RANK[methodLevel];
  return granted.includes(domain);
}

const AUTO_NAMESPACES = new Set(['pluginSettings', 'meta', 'log']);

export function createPermissionProxy(pluginId, granted, api, onDenied) {
  return new Proxy(api, {
    get(target, prop, receiver) {
      if (AUTO_NAMESPACES.has(prop)) return Reflect.get(target, prop, receiver);
      const ns = Reflect.get(target, prop, receiver);
      if (!ns || typeof ns !== 'object') return ns;
      return new Proxy(ns, {
        get(nsTarget, method) {
          const fn = Reflect.get(nsTarget, method);
          if (typeof fn !== 'function') return fn;
          const permission = `${prop}:${String(method)}`;
          if (checkPermission(granted, permission)) return fn.bind(nsTarget);
          onDenied(`${prop}.${String(method)}`);
          throw new Error(`Permission denied for plugin ${pluginId}: ${prop}.${String(method)}`);
        },
      });
    },
  });
}

export async function loadPermissions(pluginId, getSetting) {
  const raw = await getSetting(`plugin_perms_${pluginId}`);
  if (!raw) return { enabled: false, granted: [] };
  try {
    const parsed = JSON.parse(String(raw));
    return {
      enabled: !!parsed.enabled,
      granted: normalizePermissions(Array.isArray(parsed.granted) ? parsed.granted : []),
    };
  } catch {
    return { enabled: false, granted: [] };
  }
}

export async function persistPermissions(pluginId, perms, setSetting) {
  await setSetting({ key: `plugin_perms_${pluginId}`, value: JSON.stringify({
    enabled: !!perms.enabled, granted: normalizePermissions(perms.granted),
  }) });
}
