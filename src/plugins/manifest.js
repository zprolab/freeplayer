import { sanitizeSvgIcon } from './svgIcon';

export const API_VERSION = 1;

export const PERMISSIONS = [
  'http', 'player:read', 'player:write', 'audio:read',
  'metadata:read', 'metadata:write', 'metadata:admin',
  'settings:read', 'settings:write', 'settings:admin',
];

export const ACTIVATION_EVENTS = [
  'lyrics:fetch', 'cover:fetch', 'metadata:fetch', 'track:changed', 'playback:changed',
];

const WRITE_IMPLIES_READ = {
  'player:write': 'player:read',
  'metadata:write': 'metadata:read',
  'settings:write': 'settings:read',
};

export function normalizePermissions(perms) {
  const out = new Set();
  for (const p of perms || []) {
    if (!PERMISSIONS.includes(p)) continue;
    out.add(p);
    const implied = WRITE_IMPLIES_READ[p];
    if (implied) out.add(implied);
  }
  return [...out];
}

const ID_RE = /^[a-z0-9][a-z0-9-]{1,63}$/;
const SETTING_TYPES = ['string', 'number', 'boolean', 'select'];
const MAX_MANIFEST_BYTES = 64 * 1024;
const MAX_TEXT = 4096;
const MAX_SETTINGS = 64;
const MAX_OPTIONS = 128;

export function validateManifest(raw) {
  const errors = [];
  if (!raw || typeof raw !== 'object') return { ok: false, errors: ['manifest is not an object'] };
  try {
    if (JSON.stringify(raw).length > MAX_MANIFEST_BYTES) return { ok: false, errors: ['manifest: too large'] };
  } catch { return { ok: false, errors: ['manifest invalid: not serializable'] }; }
  if (typeof raw.id !== 'string' || !ID_RE.test(raw.id)) errors.push('id: must match [a-z0-9][a-z0-9-]{1,63}');
  if (typeof raw.name !== 'string' || !raw.name.trim() || raw.name.length > MAX_TEXT) errors.push('name: required (max 4096 chars)');
  if (typeof raw.version !== 'string' || !raw.version || raw.version.length > 256) errors.push('version: required (max 256 chars)');
  for (const key of ['description', 'author', 'homepage']) {
    if (raw[key] !== undefined && (typeof raw[key] !== 'string' || raw[key].length > MAX_TEXT)) errors.push(`${key}: max 4096 chars`);
  }
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
  if (provides.metadata && !events.includes('metadata:fetch')) errors.push('provides.metadata requires activationEvents metadata:fetch');
  if (provides.metadata && !perms.includes('metadata:write')) errors.push('provides.metadata requires permission metadata:write');
  // Provider hooks are persisted by the host on the plugin's behalf, so a
  // provider must explicitly request the write permission it relies on —
  // otherwise the permission model would let any lyrics/cover backend write
  // to the library without ever being granted metadata:write.
  if ((provides.lyrics || provides.cover) && !perms.includes('metadata:write')) {
    errors.push('provides.lyrics/cover requires permission metadata:write');
  }
  if (raw.notice !== undefined) {
    if (typeof raw.notice !== 'string' || !raw.notice.trim() || raw.notice.length > 512) {
      errors.push('notice: must be a non-empty string (max 512 chars)');
    }
  }
  if (raw.icon !== undefined) {
    // Icon must be a sanitizable inline SVG (allowlisted elements/attrs,
    // no scripts/handlers); invalid icons fail the manifest.
    if (typeof raw.icon !== 'string' || !sanitizeSvgIcon(raw.icon)) {
      errors.push('icon: must be a valid inline SVG string');
    }
  }
  if (raw.settings !== undefined) {
    if (!Array.isArray(raw.settings) || raw.settings.length > MAX_SETTINGS) errors.push(`settings: must be an array (max ${MAX_SETTINGS})`);
    else {
      for (const s of raw.settings) {
        if (!s || typeof s !== 'object') { errors.push('settings: invalid entry'); continue; }
        if (typeof s.key !== 'string' || !/^[a-zA-Z0-9_.-]{1,64}$/.test(s.key)) errors.push('settings: key must match [a-zA-Z0-9_.-]{1,64}');
        if (!SETTING_TYPES.includes(s.type)) errors.push(`settings: "${s?.key}" has unknown type "${s?.type}"`);
        if (s.type === 'select') {
          if (!Array.isArray(s.options) || s.options.length === 0 || s.options.length > MAX_OPTIONS) {
            errors.push(`settings: "${s?.key}" select needs a non-empty options array`);
          } else if (!s.options.every((o) => typeof o === 'string')) {
            errors.push(`settings: "${s?.key}" select options must be strings`);
          } else if (s.options.some((o) => o.length > 512)) {
            errors.push(`settings: "${s?.key}" select options max length is 512`);
          } else if (s.default !== undefined && !s.options.includes(s.default)) {
            errors.push(`settings: "${s?.key}" default must be one of its options`);
          }
        }
        if (s.type === 'number') {
          if (!Number.isFinite(s.min) || !Number.isFinite(s.max)) {
            errors.push(`settings: "${s?.key}" number needs finite min/max`);
          } else if (s.min > s.max) {
            errors.push(`settings: "${s?.key}" min must not exceed max`);
          } else if (s.default !== undefined
            && (typeof s.default !== 'number' || !Number.isFinite(s.default) || s.default < s.min || s.default > s.max)) {
            errors.push(`settings: "${s?.key}" default must be a number within [min, max]`);
          }
        }
        if ((s.type === 'boolean' || s.type === 'string')
          && (s.min !== undefined || s.max !== undefined)) {
          errors.push(`settings: "${s?.key}" ${s.type} cannot declare min/max`);
        }
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
      notice: raw.notice !== undefined ? raw.notice : undefined,
      settings: raw.settings || [],
    },
  };
}
