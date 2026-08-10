import { describe, it, expect, vi } from 'vitest';
import { createRegistry } from '../../src/plugins/registry';
import { createMetadataRegistry } from '../../src/plugins/metadataRegistry';

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

describe('registry deferred minors', () => {
  it('emit survives an error plugin whose raw manifest lacks activationEvents', async () => {
    const { registry, deps } = makeRegistry();
    const bad = MANIFEST('bad', { permissions: ['not-a-permission'] }); // invalid -> error
    delete bad.activationEvents;
    deps.listPlugins.mockResolvedValue([{ id: 'bad', manifestRaw: bad, builtin: false }]);
    await registry.discover();
    expect(registry.getPlugin('bad').status).toBe('error');
    // enable() only rejects 'incompatible' — an error plugin can still be
    // force-enabled, so emit must not assume its manifest is normalized.
    await registry.enable('bad', []);
    await registry.emit('trackChanged', { id: 9 });
    expect(deps.loader.activate).not.toHaveBeenCalled();
  });

  it('restoreState does not resurrect an error plugin', async () => {
    const { registry, deps, state } = makeRegistry();
    const bad = MANIFEST('bad', { permissions: ['not-a-permission'] });
    deps.listPlugins.mockResolvedValue([{ id: 'bad', manifestRaw: bad, builtin: false }]);
    state.plugin_perms_bad = JSON.stringify({ enabled: true, granted: [] });
    await registry.discover();
    await registry.restoreState();
    expect(registry.getPlugin('bad').status).toBe('error');
    expect(registry.getPlugin('bad').perms.enabled).toBe(false);
  });

  it('uninstall clears persisted permissions', async () => {
    const { registry, deps, state } = makeRegistry();
    deps.listPlugins.mockResolvedValue([{ id: 'p', manifestRaw: MANIFEST('p'), builtin: false }]);
    await registry.discover();
    await registry.enable('p', ['http']);
    expect(state.plugin_perms_p).toBeTruthy();
    await registry.uninstall('p');
    expect(deps.uninstallPlugin).toHaveBeenCalledWith('p');
    expect(state.plugin_perms_p).toBeFalsy();
    expect(registry.getPlugin('p')).toBeUndefined();
  });

  it('getAuditLog returns a copy, not the internal list', async () => {
    const { registry } = makeRegistry();
    registry.logOp('p', 'op', 'd');
    const log = registry.getAuditLog('p');
    log.length = 0;
    expect(registry.getAuditLog('p')).toHaveLength(1);
  });
});

describe('metadataRegistry deferred minor', () => {
  it('getProviders tolerates plugins without a provides section', () => {
    const registry = {
      getPlugins: () => [
        { id: 'bare', status: 'enabled', manifest: {} },
        { id: 'full', status: 'enabled', manifest: { provides: { lyrics: true } } },
      ],
      invokeHook: vi.fn(),
    };
    const reg = createMetadataRegistry({
      registry, getSetting: vi.fn(), saveLyrics: vi.fn(), saveCover: vi.fn(),
    });
    expect(reg.getProviders('lyrics')).toEqual(['full']);
    expect(reg.getProviders('cover')).toEqual([]);
  });
});
