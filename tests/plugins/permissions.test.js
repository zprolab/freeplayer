import { describe, it, expect, vi } from 'vitest';
import { checkPermission, createPermissionProxy, loadPermissions, persistPermissions } from '../../src/plugins/permissions';

describe('checkPermission', () => {
  it('grants an exact match', () => {
    expect(checkPermission(['http'], 'http')).toBe(true);
  });
  it('denies unlisted permissions', () => {
    expect(checkPermission(['http'], 'player:read')).toBe(false);
  });
  it('grants domain read when write was granted', () => {
    expect(checkPermission(['metadata:write'], 'metadata:read')).toBe(true);
  });
  it('grants domain read when admin was granted', () => {
    expect(checkPermission(['metadata:admin'], 'metadata:write')).toBe(true);
    expect(checkPermission(['metadata:admin'], 'metadata:read')).toBe(true);
  });
  it('denies nothing-granted', () => {
    expect(checkPermission([], 'http')).toBe(false);
  });
  it('maps methods to levels: metadata:write grants saveLyrics', () => {
    expect(checkPermission(['metadata:write'], 'metadata:saveLyrics')).toBe(true);
  });
  it('requires admin for deleteTrack', () => {
    expect(checkPermission(['metadata:write'], 'metadata:deleteTrack')).toBe(false);
    expect(checkPermission(['metadata:admin'], 'metadata:deleteTrack')).toBe(true);
  });
  it('requires write for player control', () => {
    expect(checkPermission(['player:read'], 'player:play')).toBe(false);
    expect(checkPermission(['player:write'], 'player:play')).toBe(true);
  });
  it('bare domain grant passes any method of the domain', () => {
    expect(checkPermission(['http'], 'http:getJson')).toBe(true);
    expect(checkPermission(['http'], 'http:getBase64')).toBe(true);
  });
  it('events methods are judged against the player domain', () => {
    expect(checkPermission(['player:read'], 'events:on')).toBe(true);
    expect(checkPermission(['player:read'], 'events:off')).toBe(true);
    expect(checkPermission([], 'events:on')).toBe(false);
  });
});

describe('createPermissionProxy', () => {
  it('routes allowed keys through and throws on denied', () => {
    const onDenied = vi.fn();
    const inner = { http: { getJson: () => 'ok' }, metadata: { deleteTrack: () => 'bad' } };
    const proxied = createPermissionProxy('p1', ['http'], inner, onDenied);
    expect(proxied.http.getJson()).toBe('ok');
    expect(() => proxied.metadata.deleteTrack()).toThrow('Permission denied');
    expect(onDenied).toHaveBeenCalledWith('metadata.deleteTrack');
  });
  it('reports pluginId in the error', () => {
    const inner = { a: { b: () => {} } };
    const proxied = createPermissionProxy('p1', [], inner, () => {});
    try { proxied.a.b(); expect.unreachable(); } catch (e) { expect(String(e)).toContain('p1'); }
  });
  it('maps method-level grants through the proxy', () => {
    const onDenied = vi.fn();
    const inner = { metadata: { saveLyrics: () => 'saved', deleteTrack: () => 'deleted' } };
    const proxied = createPermissionProxy('p1', ['metadata:write'], inner, onDenied);
    expect(proxied.metadata.saveLyrics()).toBe('saved');
    expect(() => proxied.metadata.deleteTrack()).toThrow('Permission denied');
    expect(onDenied).toHaveBeenCalledWith('metadata.deleteTrack');
  });
  it('passes through non-function leaves and non-plugin namespaces', () => {
    const inner = { meta: { info: 'x' }, pluginSettings: { get: () => 'mine' } };
    const proxied = createPermissionProxy('p1', [], inner, () => {});
    expect(proxied.meta.info).toBe('x');
    expect(proxied.pluginSettings.get()).toBe('mine');
  });
});

describe('persistence', () => {
  it('round-trips enabled + granted through settings', async () => {
    const store = {};
    const getSetting = vi.fn(async (k) => store[k] ?? null);
    const setSetting = vi.fn(async ({ key, value }) => { store[key] = value; });
    await persistPermissions('p1', { enabled: true, granted: ['http'] }, setSetting);
    const loaded = await loadPermissions('p1', getSetting);
    expect(loaded).toEqual({ enabled: true, granted: ['http'] });
  });
  it('defaults to disabled with no grants', async () => {
    const getSetting = vi.fn(async () => null);
    expect(await loadPermissions('p1', getSetting)).toEqual({ enabled: false, granted: [] });
  });
});
