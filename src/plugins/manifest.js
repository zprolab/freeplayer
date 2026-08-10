import { sanitizeSvgIcon } from './svgIcon';

export const API_VERSION = 1;

export const PERMISSIONS = [
  'http', 'player:read', 'player:write', 'audio:read',
  'metadata:read', 'metadata:write', 'metadata:admin',
  'settings:read', 'settings:write', 'settings:admin',
];

export const ACTIVATION_EVENTS = [
  'lyrics:fetch', 'cover:fetch', 'track:changed', 'playback:changed',
];

const WRITE_IMPLIES_READ = {
  'player:write': 'player:read',
  'metadata:write': 'metadata:read',
  'settings:write': 'settings:read',
};

export function normalizePermissions(perms) {
  const out = new Set();
  for (const p of perms || []) {
    out.add(p);
    const implied = WRITE_IMPLIES_READ[p];
    if (implied) out.add(implied);
  }
  return [...out];
}

const ID_RE = /^[a-z0-9][a-z0-9-]{1,63}$/;
const SETTING_TYPES = ['string', 'number', 'boolean', 'select'];
const MAX_MANIFEST_BYTES = 64 * 1024;

export function validateManifest(raw) {
  const errors = [];
  if (!raw || typeof raw !== 'object') return { ok: false, errors: ['manifest is not an object'] };
  if (typeof raw.id !== 'string' || !ID_RE.test(raw.id)) errors.push('id: must match [a-z0-9][a-z0-9-]{1,63}');
  if (typeof raw.name !== 'string' || !raw.name.trim()) errors.push('name: required');
  if (typeof raw.version !== 'string' || !raw.version) errors.push('version: required');
  if (raw.apiVersion !== API_VERSION) errors.push(`apiVersion: must be ${API_VERSION}`);
  if (typeof raw.main !== 'string' || !/^[^./][^]*\.js$/.test(raw.main) || raw.main.includes('..')) {
    errors.push('main: must be a .js file inside the plugin directory');
  }
  const perms = Array.isArray(raw.permissions) ? raw.permissions : [];
  for (const p of perms) {
    if (!PERMISSIONS.includes(p)) errors.push(`permissions: unknown "${p}"`);
  }
  const events = Array.isArray(raw.activationEvents) ? raw.activationEvents : [];
  for (const e of events) {
    if (!ACTIVATION_EVENTS.includes(e)) errors.push(`activationEvents: unknown "${e}"`);
  }
  const provides = raw.provides || {};
  if (provides.lyrics && !events.includes('lyrics:fetch')) errors.push('provides.lyrics requires activationEvents lyrics:fetch');
  if (provides.cover && !events.includes('cover:fetch')) errors.push('provides.cover requires activationEvents cover:fetch');
  // Provider hooks are persisted by the host on the plugin's behalf, so a
  // provider must explicitly request the write permission it relies on —
  // otherwise the permission model would let any lyrics/cover backend write
  // to the library without ever being granted metadata:write.
  if ((provides.lyrics || provides.cover) && !perms.includes('metadata:write')) {
    errors.push('provides.lyrics/cover requires permission metadata:write');
  }
  if (raw.icon !== undefined) {
    // Icon must be a sanitizable inline SVG (allowlisted elements/attrs,
    // no scripts/handlers); invalid icons fail the manifest.
    if (typeof raw.icon !== 'string' || !sanitizeSvgIcon(raw.icon)) {
      errors.push('icon: must be a valid inline SVG string');
    }
  }
  if (raw.settings !== undefined) {
    if (!Array.isArray(raw.settings)) errors.push('settings: must be an array');
    else {
      for (const s of raw.settings) {
        if (!s || typeof s !== 'object') { errors.push('settings: invalid entry'); continue; }
        if (typeof s.key !== 'string' || !s.key) errors.push('settings: key required');
        if (!SETTING_TYPES.includes(s.type)) errors.push(`settings: "${s?.key}" has unknown type "${s?.type}"`);
        if (s.type === 'select' && !Array.isArray(s.options)) errors.push(`settings: "${s?.key}" select needs options`);
      }
    }
  }
  if (errors.length) return { ok: false, errors };
  return {
    ok: true,
    manifest: {
      id: raw.id, name: raw.name, version: raw.version,
      description: raw.description || '', author: raw.author || '',
      homepage: raw.homepage || '',
      icon: raw.icon !== undefined ? sanitizeSvgIcon(raw.icon) : undefined,
      apiVersion: raw.apiVersion, main: raw.main,
      permissions: normalizePermissions(perms),
      activationEvents: events, provides,
      settings: raw.settings || [],
    },
  };
}
