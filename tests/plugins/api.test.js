import { describe, it, expect, vi } from 'vitest';
import { createPluginApi, wrapApi } from '../../src/plugins/api';
import { createEventBus, hookTimeout } from '../../src/plugins/hooks';

function makeDeps(over = {}) {
  const bridge = {
    http: { getJson: vi.fn(async () => ({ ok: true, status: 200, body: {} })), getBase64: vi.fn(async () => ({ ok: true, base64: '' })) },
    metadata: {
      getTrackInfo: vi.fn(async () => ({})), getLyrics: vi.fn(async () => null), getCover: vi.fn(async () => null),
      saveLyrics: vi.fn(async () => ({ success: true })), saveCover: vi.fn(async () => ({ success: true })),
      updateTrack: vi.fn(async () => true), removeLyrics: vi.fn(async () => true),
    },
  };
  const player = {
    getState: vi.fn(() => ({ isPlaying: false })), getTrack: vi.fn(() => ({ id: 1 })),
    play: vi.fn(), pause: vi.fn(), seek: vi.fn(), next: vi.fn(), previous: vi.fn(), setVolume: vi.fn(),
  };
  const settings = { get: vi.fn(async () => null), set: vi.fn(async () => {}) };
  const pluginSettings = { get: vi.fn(async () => null), set: vi.fn(async () => {}) };
  const log = vi.fn();
  const events = createEventBus();
  return { bridge, player, settings, pluginSettings, log, events, ...over };
}

describe('createPluginApi', () => {
  it('exposes http through bridge', async () => {
    const deps = makeDeps();
    const api = createPluginApi('p1', ['http'], deps);
    await api.http.getJson('https://x');
    expect(deps.bridge.http.getJson).toHaveBeenCalledWith('https://x');
  });
  it('does not expose deleteTrack or resetDatabase', () => {
    const api = createPluginApi('p1', ['metadata:admin', 'settings:admin'], makeDeps());
    expect(api.metadata.deleteTrack).toBeUndefined();
    expect(api.settings.resetDatabase).toBeUndefined();
  });
  it('metadata write methods enforce the 10s/20 rate limit', async () => {
    const deps = makeDeps();
    const api = createPluginApi('p1', ['metadata:write'], deps);
    for (let i = 0; i < 20; i++) await api.metadata.saveLyrics(1, 'x');
    await expect(api.metadata.saveLyrics(1, 'x')).rejects.toThrow(/rate limit/);
  });
  it('updateTrack rejects fields outside the whitelist', async () => {
    const deps = makeDeps();
    const api = createPluginApi('p1', ['metadata:write'], deps);
    await api.metadata.updateTrack(1, { title: 'ok', file_path: '/evil' });
    expect(deps.bridge.metadata.updateTrack).toHaveBeenCalledWith(1, { title: 'ok' });
  });
  it('pluginSettings works without permissions', async () => {
    const deps = makeDeps();
    const api = createPluginApi('p1', [], deps);
    await api.pluginSettings.set('k', 'v');
    expect(deps.pluginSettings.set).toHaveBeenCalled();
  });
  it('pluginSettings keys are scoped under the plugin id', async () => {
    const deps = makeDeps();
    const api = createPluginApi('p1', [], deps);
    await api.pluginSettings.get('k');
    expect(deps.pluginSettings.get).toHaveBeenCalledWith('p1.k');
    await api.pluginSettings.set('k', 'v');
    expect(deps.pluginSettings.set).toHaveBeenCalledWith('p1.k', 'v');
  });
  it('meta.info exposes plugin identity', () => {
    const api = createPluginApi('p1', [], makeDeps());
    expect(api.meta.info).toEqual({ id: 'p1', name: '', version: '' });
  });
  it('api.settings is scoped to the plugin namespace, never the global table', async () => {
    const deps = makeDeps();
    const api = createPluginApi('p1', ['settings:read', 'settings:write'], deps);
    // a plugin with settings:read cannot read another plugin's keyspace
    await api.settings.get('musicbrainz-meta.apiToken');
    expect(deps.settings.get).toHaveBeenCalledWith('plugin.p1.musicbrainz-meta.apiToken');
    // nor the permission blobs
    await api.settings.get('plugin_perms_musicbrainz-meta');
    expect(deps.settings.get).toHaveBeenLastCalledWith('plugin.p1.plugin_perms_musicbrainz-meta');
    // writes land in the plugin's own namespace
    await api.settings.set('apiToken', 's3cret');
    expect(deps.settings.set).toHaveBeenCalledWith({ key: 'plugin.p1.apiToken', value: 's3cret' });
    // already-namespaced own keys are not double-prefixed
    await api.settings.get('plugin.p1.apiToken');
    expect(deps.settings.get).toHaveBeenLastCalledWith('plugin.p1.apiToken');
  });
  it('events.on registers the plugin as owner so removeOwner drops its listeners', () => {
    const deps = makeDeps();
    const api = createPluginApi('p1', ['player:read'], deps);
    const cb = vi.fn();
    api.events.on('trackChanged', cb);
    deps.events.emit('trackChanged', { id: 5 });
    expect(cb).toHaveBeenCalledWith({ id: 5 });
    api.events.removeOwner('p1');
    deps.events.emit('trackChanged', { id: 6 });
    expect(cb).toHaveBeenCalledTimes(1);
  });
});

describe('wrapApi', () => {
  it('denies calls without permission', () => {
    const deps = makeDeps();
    const api = createPluginApi('p1', [], deps);
    const wrapped = wrapApi('p1', [], api, vi.fn());
    expect(() => wrapped.http.getJson('x')).toThrow(/Permission denied/);
  });
  it('allows permitted calls', () => {
    const deps = makeDeps();
    const api = createPluginApi('p1', ['http'], deps);
    const wrapped = wrapApi('p1', ['http'], api, vi.fn());
    expect(() => wrapped.http.getJson('x')).not.toThrow();
  });
  it('gates events.on/off on player:read', () => {
    const onDenied = vi.fn();
    const api = createPluginApi('p1', ['player:read'], makeDeps());
    const wrapped = wrapApi('p1', ['player:read'], api, onDenied);
    const cb = vi.fn();
    expect(() => wrapped.events.on('trackChanged', cb)).not.toThrow();
    const denied = wrapApi('p1', [], api, onDenied);
    expect(() => denied.events.on('trackChanged', cb)).toThrow(/Permission denied/);
    expect(() => denied.events.off('trackChanged', cb)).toThrow(/Permission denied/);
    expect(onDenied).toHaveBeenCalledWith('events.on');
  });
});

describe('createEventBus + hookTimeout', () => {
  it('routes on/off/emit per channel', () => {
    const bus = createEventBus();
    const cb = vi.fn();
    bus.on('trackChanged', cb);
    bus.emit('trackChanged', { id: 5 });
    expect(cb).toHaveBeenCalledWith({ id: 5 });
    bus.off('trackChanged', cb);
    bus.emit('trackChanged', { id: 6 });
    expect(cb).toHaveBeenCalledTimes(1);
  });
  it('rejects unknown channels', () => {
    const bus = createEventBus();
    expect(() => bus.on('nope', () => {})).toThrow();
    expect(() => bus.emit('nope', {})).toThrow();
  });
  it('isolates listener exceptions during emit', () => {
    const bus = createEventBus();
    const boom = () => { throw new Error('boom'); };
    const ok = vi.fn();
    bus.on('trackChanged', boom);
    bus.on('trackChanged', ok);
    expect(() => bus.emit('trackChanged', { id: 5 })).not.toThrow();
    expect(ok).toHaveBeenCalledWith({ id: 5 });
  });
  it('hookTimeout rejects when the hook is slow', async () => {
    await expect(hookTimeout(() => new Promise((r) => setTimeout(r, 50)), 10)).rejects.toThrow(/timeout/);
  });
  it('hookTimeout resolves fast hooks', async () => {
    expect(await hookTimeout(() => Promise.resolve('v'), 100)).toBe('v');
  });
});
