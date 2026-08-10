import { describe, it, expect, vi, beforeEach } from 'vitest';
import { createRegistry } from '../../src/plugins/registry';
import { wrapApi } from '../../src/plugins/api';

const MANIFEST = (id, extra = {}) => ({
  id, name: id, version: '1.0.0', main: 'main.js',
  apiVersion: 1, permissions: ['http'],
  activationEvents: [], provides: {}, ...extra,
});

function makeRegistry(over = {}) {
  const state = {};
  const loader = {
    activate: vi.fn(async () => ({ hooks: {}, deactivate: vi.fn() })),
  };
  const deps = {
    listPlugins: vi.fn(async () => []),
    readFile: vi.fn(async () => null),
    loader,
    log: vi.fn(),
    getSetting: vi.fn(async (k) => state[k] ?? null),
    setSetting: vi.fn(async ({ key, value }) => { state[key] = value; }),
    uninstallPlugin: vi.fn(async () => {}),
    ...over,
  };
  return { registry: createRegistry(deps), deps, state };
}

describe('createRegistry', () => {
  it('discovers and validates plugins, flagging incompatibles', async () => {
    const { registry, deps } = makeRegistry();
    deps.listPlugins.mockResolvedValue([
      { id: 'good', manifestRaw: MANIFEST('good'), builtin: false },
      { id: 'old', manifestRaw: MANIFEST('old', { apiVersion: 2 }), builtin: false },
    ]);
    await registry.discover();
    const byId = Object.fromEntries(registry.getPlugins().map((p) => [p.id, p]));
    expect(byId.good.status).toBe('disabled');
    expect(byId.old.status).toBe('incompatible');
  });
  it('user plugin overrides builtin with the same id', async () => {
    const { registry, deps } = makeRegistry();
    deps.listPlugins.mockResolvedValue([{ id: 'x', manifestRaw: MANIFEST('x'), builtin: false }]);
    registry.registerBuiltin({ id: 'x', manifestRaw: MANIFEST('x', { version: '9.9.9' }), builtin: true });
    await registry.discover();
    const p = registry.getPlugin('x');
    expect(p.builtin).toBe(false);
    expect(p.manifest.version).toBe('1.0.0');
  });
  it('builtin module is forwarded to the loader for direct import', async () => {
    const { registry, deps } = makeRegistry();
    const module = { activate: vi.fn(() => ({})) };
    deps.listPlugins.mockResolvedValue([]);
    registry.registerBuiltin({ id: 'b', manifestRaw: MANIFEST('b'), builtin: true, module });
    await registry.discover();
    await registry.enable('b', ['http']);
    deps.loader.activate.mockResolvedValue({ hooks: {}, deactivate: vi.fn() });
    await registry.ensureActive('b');
    expect(deps.loader.activate).toHaveBeenCalledWith('b', expect.objectContaining({ builtin: true, module }));
  });
  it('enable persists permissions and does not activate', async () => {
    const { registry, deps } = makeRegistry();
    deps.listPlugins.mockResolvedValue([{ id: 'p', manifestRaw: MANIFEST('p'), builtin: true }]);
    await registry.discover();
    await registry.enable('p', ['http']);
    expect(deps.loader.activate).not.toHaveBeenCalled();
    expect(registry.getPlugin('p').status).toBe('enabled');
    expect(registry.getPlugin('p').perms.granted).toContain('http');
  });
  it('passes the user-granted permission list to the loader at activation', async () => {
    const { registry, deps } = makeRegistry();
    // manifest requests metadata:write, but the user only granted http
    deps.listPlugins.mockResolvedValue([{ id: 'p', manifestRaw: MANIFEST('p', { permissions: ['http', 'metadata:write'] }), builtin: true }]);
    await registry.discover();
    await registry.enable('p', ['http']);
    await registry.ensureActive('p');
    expect(deps.loader.activate).toHaveBeenCalledWith('p', expect.objectContaining({ granted: ['http'] }));
  });
  it('invokeHook gates the plugin api on granted permissions, not the manifest', async () => {
    const { registry, deps } = makeRegistry();
    deps.listPlugins.mockResolvedValue([{ id: 'p', manifestRaw: MANIFEST('p', { permissions: ['http', 'metadata:write'], provides: { lyrics: true } }), builtin: true }]);
    let capturedApi;
    // loader mock mirrors the real loader contract: wrap the api with entry.granted
    deps.loader.activate.mockImplementation(async (id, entry) => {
      capturedApi = wrapApi(id, entry.granted, {
        http: { getJson: () => 'json-ok' },
        metadata: { saveLyrics: () => 'saved' },
      }, () => {});
      return { hooks: { fetchLyrics: async () => 'lrc' }, deactivate: vi.fn() };
    });
    await registry.discover();
    await registry.enable('p', ['http']); // user grants only http despite the manifest request
    const res = await registry.invokeHook('p', 'fetchLyrics', {});
    expect(res).toBe('lrc');
    expect(capturedApi.http.getJson()).toBe('json-ok');
    expect(() => capturedApi.metadata.saveLyrics(1, 'x')).toThrow(/Permission denied/);
  });
  it('invokeHook success writes an ok audit entry', async () => {
    const { registry, deps } = makeRegistry();
    deps.listPlugins.mockResolvedValue([{ id: 'p', manifestRaw: MANIFEST('p', { provides: { lyrics: true } }), builtin: true }]);
    deps.loader.activate.mockResolvedValue({ hooks: { fetchLyrics: vi.fn(async () => 'lrc') }, deactivate: vi.fn() });
    await registry.discover();
    await registry.enable('p', ['http']);
    await registry.invokeHook('p', 'fetchLyrics', {});
    const log = registry.getAuditLog('p');
    expect(log).toHaveLength(1);
    expect(log[0]).toMatchObject({ op: 'hook:fetchLyrics', detail: 'ok', ok: true });
  });
  it('invokeHook lazily activates then calls the hook', async () => {
    const { registry, deps } = makeRegistry();
    deps.listPlugins.mockResolvedValue([{ id: 'p', manifestRaw: MANIFEST('p', { provides: { lyrics: true } }), builtin: true }]);
    deps.loader.activate.mockResolvedValue({ hooks: { fetchLyrics: vi.fn(async () => ({ content: 'lrc' })) }, deactivate: vi.fn() });
    await registry.discover();
    await registry.enable('p', ['http']);
    const res = await registry.invokeHook('p', 'fetchLyrics', { title: 'Sun' });
    expect(res).toEqual({ content: 'lrc' });
    expect(registry.getPlugin('p').status).toBe('active');
  });
  it('disable calls deactivate and returns to disabled', async () => {
    const { registry, deps } = makeRegistry();
    const deactivate = vi.fn();
    deps.listPlugins.mockResolvedValue([{ id: 'p', manifestRaw: MANIFEST('p', { provides: { lyrics: true } }), builtin: true }]);
    deps.loader.activate.mockResolvedValue({ hooks: { fetchLyrics: vi.fn() }, deactivate });
    await registry.discover();
    await registry.enable('p', ['http']);
    await registry.invokeHook('p', 'fetchLyrics', {});
    await registry.disable('p');
    expect(deactivate).toHaveBeenCalled();
    expect(registry.getPlugin('p').status).toBe('disabled');
  });
  it('invokeHook failures set lastError, audit the failure and return null', async () => {
    const { registry, deps } = makeRegistry();
    deps.listPlugins.mockResolvedValue([{ id: 'p', manifestRaw: MANIFEST('p', { provides: { lyrics: true } }), builtin: true }]);
    deps.loader.activate.mockResolvedValue({ hooks: { fetchLyrics: vi.fn(async () => { throw new Error('boom'); }) }, deactivate: vi.fn() });
    await registry.discover();
    await registry.enable('p', ['http']);
    const res = await registry.invokeHook('p', 'fetchLyrics', {});
    expect(res).toBeNull();
    expect(registry.getPlugin('p').lastError).toContain('boom');
    const log = registry.getAuditLog('p');
    expect(log).toHaveLength(1);
    expect(log[0]).toMatchObject({ op: 'hook:fetchLyrics', ok: false });
    expect(log[0].detail).toContain('boom');
  });
  it('emit only activates plugins that subscribe to the channel', async () => {
    const { registry, deps } = makeRegistry();
    deps.listPlugins.mockResolvedValue([
      { id: 'sub', manifestRaw: MANIFEST('sub', { activationEvents: ['track:changed'] }), builtin: true },
      { id: 'nosub', manifestRaw: MANIFEST('nosub'), builtin: true },
    ]);
    const subCb = vi.fn();
    const subDeactivate = vi.fn();
    deps.loader.activate.mockImplementation(async (id) => ({
      hooks: { onTrackChanged: subCb }, deactivate: subDeactivate,
    }));
    await registry.discover();
    await registry.enable('sub', []);
    await registry.enable('nosub', []);
    await registry.emit('trackChanged', { id: 9 });
    expect(deps.loader.activate).toHaveBeenCalledTimes(1);
    expect(deps.loader.activate.mock.calls[0][0]).toBe('sub');
    expect(subCb).toHaveBeenCalledWith({ id: 9 });
  });
  it('audit log is per-plugin and bounded', async () => {
    const { registry, deps } = makeRegistry();
    deps.listPlugins.mockResolvedValue([{ id: 'p', manifestRaw: MANIFEST('p'), builtin: true }]);
    await registry.discover();
    for (let i = 0; i < 210; i++) registry.logOp('p', 'op', i, true);
    const log = registry.getAuditLog('p');
    expect(log.length).toBeLessThanOrEqual(200);
    expect(log[0].detail).toBe(210 - 200); // newest first
  });
  it('discover marks malformed manifests as error without affecting other plugins', async () => {
    const { registry, deps } = makeRegistry();
    deps.listPlugins.mockResolvedValue([
      { id: 'bad', manifestRaw: { id: 'bad', name: 'Bad', apiVersion: 1, main: 'main.js', settings: [null] } },
      { id: 'throwing', manifestRaw: { id: 'throwing', apiVersion: 1, version: '1.0.0', main: 'main.js', get name() { throw new Error('boom'); } } },
      { id: 'good', manifestRaw: MANIFEST('good') },
    ]);
    await registry.discover();
    expect(registry.getPlugin('bad').status).toBe('error');
    expect(registry.getPlugin('bad').lastError).toContain('settings');
    expect(registry.getPlugin('throwing').status).toBe('error');
    expect(registry.getPlugin('throwing').lastError).toContain('manifest invalid');
    expect(registry.getPlugin('good').status).toBe('disabled');
  });
});
