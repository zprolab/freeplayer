import { describe, it, expect } from 'vitest';
import { validateManifest, normalizePermissions, API_VERSION } from '../../src/plugins/manifest';

describe('normalizePermissions', () => {
  it('expands write to include same-domain read', () => {
    expect(normalizePermissions(['player:write', 'http'])).toEqual(
      ['player:write', 'player:read', 'http']
    );
  });
  it('leaves read-only and no-write domains untouched', () => {
    expect(normalizePermissions(['http', 'audio:read']).sort()).toEqual(['http', 'audio:read'].sort());
  });
});

describe('validateManifest', () => {
  const base = {
    id: 'lrclib-lyrics', name: 'LRCLIB Lyrics', version: '1.0.0',
    main: 'main.js', apiVersion: API_VERSION,
    permissions: ['http'], activationEvents: [],
  };
  it('accepts a valid manifest and expands write permissions', () => {
    const r = validateManifest({ ...base, permissions: ['metadata:write'] });
    expect(r.ok).toBe(true);
    expect(r.manifest.permissions).toContain('metadata:read');
  });
  it('rejects missing id', () => {
    const { id, ...noId } = base;
    const r = validateManifest(noId);
    expect(r.ok).toBe(false);
    expect(r.errors.join()).toContain('id');
  });
  it('rejects malformed id', () => {
    const r = validateManifest({ ...base, id: 'Bad Id!' });
    expect(r.ok).toBe(false);
  });
  it('rejects apiVersion mismatch', () => {
    const r = validateManifest({ ...base, apiVersion: 2 });
    expect(r.ok).toBe(false);
    expect(r.errors.join()).toContain('apiVersion');
  });
  it('rejects unknown permission', () => {
    const r = validateManifest({ ...base, permissions: ['root:all'] });
    expect(r.ok).toBe(false);
  });
  it('rejects unknown activationEvent', () => {
    const r = validateManifest({ ...base, activationEvents: ['onEveryTick'] });
    expect(r.ok).toBe(false);
  });
  it('rejects main escaping the plugin dir', () => {
    const r = validateManifest({ ...base, main: '../../evil.js' });
    expect(r.ok).toBe(false);
  });
  it('rejects main not ending in .js', () => {
    const r = validateManifest({ ...base, main: 'main.ts' });
    expect(r.ok).toBe(false);
  });
  it('rejects invalid settings schema entries', () => {
    const r = validateManifest({ ...base, settings: [{ key: 'x', type: 'nope' }] });
    expect(r.ok).toBe(false);
  });
  it('does not throw on malformed settings entries (null / primitives)', () => {
    const r = validateManifest({ ...base, settings: [null, 42, 'x', { key: 'ok', type: 'string' }] });
    expect(r.ok).toBe(false);
    expect(r.errors.join()).toContain('invalid entry');
    expect(r.errors.some((e) => e.includes('unknown type'))).toBe(false);
  });
  it('accepts settings with valid types', () => {
    const r = validateManifest({ ...base, settings: [
      { key: 'a', type: 'number', label: 'A', default: 1, min: 0, max: 5 },
      { key: 'b', type: 'select', label: 'B', default: 'x', options: ['x', 'y'] },
      { key: 'c', type: 'boolean', label: 'C', default: true },
      { key: 'd', type: 'string', label: 'D', default: '' },
    ] });
    expect(r.ok).toBe(true);
  });
  it('rejects provides.lyrics without lyrics:fetch activation', () => {
    const r = validateManifest({ ...base, provides: { lyrics: true } });
    expect(r.ok).toBe(false);
    expect(r.errors.join()).toContain('lyrics:fetch');
  });
  it('accepts provides.lyrics with matching activation and write permission', () => {
    const r = validateManifest({
      ...base,
      provides: { lyrics: true },
      activationEvents: ['lyrics:fetch'],
      permissions: ['http', 'metadata:write'],
    });
    expect(r.ok).toBe(true);
  });
  it('rejects providers without the metadata:write permission', () => {
    const r = validateManifest({
      ...base,
      provides: { cover: true },
      activationEvents: ['cover:fetch'],
      permissions: ['http'],
    });
    expect(r.ok).toBe(false);
    expect(r.errors.join()).toContain('metadata:write');
  });
  it('accepts a valid sanitizable svg icon', () => {
    const r = validateManifest({
      ...base,
      icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/></svg>',
    });
    expect(r.ok).toBe(true);
    expect(r.manifest.icon).toContain('<path d="M9 18V5l12-2v13"/>');
    expect(r.manifest.icon).not.toContain('width=');
  });
  it('rejects icons with scripts or handlers', () => {
    const r = validateManifest({ ...base, icon: '<svg onload="alert(1)"><script>x()</script></svg>' });
    expect(r.ok).toBe(false);
    expect(r.errors.join()).toContain('icon');
  });
  it('rejects non-string icons', () => {
    const r = validateManifest({ ...base, icon: 42 });
    expect(r.ok).toBe(false);
  });
});
