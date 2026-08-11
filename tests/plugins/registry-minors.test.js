import { describe, it, expect, vi } from 'vitest';
import { createRegistry } from '../../src/plugins/registry';
import { createMetadataRegistry } from '../../src/plugins/metadataRegistry';
import { sanitizeSvgIcon } from '../../src/plugins/svgIcon';

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
    // enable() rejects error-status plugins — no force-enable path.
    await expect(registry.enable('bad', [])).rejects.toThrow(/cannot enable/);
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

  it('error-status plugins store a sanitized icon, never the raw SVG', async () => {
    const { registry, deps } = makeRegistry();
    const evil = MANIFEST('evil', {
      permissions: ['not-a-permission'], // force status 'error' so the raw
      // manifest (with the unsanitized icon) is what gets displayed
      icon: '<svg onload="alert(1)" onerror="steal()"><script>x()</script><path d="M1 2"/></svg>',
    });
    deps.listPlugins.mockResolvedValue([{ id: 'evil', manifestRaw: evil, builtin: false }]);
    await registry.discover();
    const icon = registry.getPlugin('evil').manifest.icon;
    expect(typeof icon).toBe('string');
    expect(icon).not.toContain('onload');
    expect(icon).not.toContain('onerror');
    expect(icon).not.toContain('script');
    // it equals the sanitizer output (safe to inject as HTML)
    expect(icon).toBe(sanitizeSvgIcon(evil.icon));
  });

  it('error-status plugins with an unsanitizable icon get no icon at all', async () => {
    const { registry, deps } = makeRegistry();
    const evil = MANIFEST('evil2', {
      permissions: ['not-a-permission'],
      icon: '<svg onload="alert(1)"></svg>', // no shapes -> sanitizer drops it
    });
    deps.listPlugins.mockResolvedValue([{ id: 'evil2', manifestRaw: evil, builtin: false }]);
    await registry.discover();
    expect(registry.getPlugin('evil2').manifest.icon).toBeUndefined();
  });

  it('uninstall clears persisted permissions', async () => {
    const { registry, deps, state } = makeRegistry();
    deps.listPlugins.mockResolvedValue([{ id: 'pp', manifestRaw: MANIFEST('pp'), builtin: false }]);
    await registry.discover();
    await registry.enable('pp', ['http']);
    expect(state.plugin_perms_pp).toBeTruthy();
    await registry.uninstall('pp');
    expect(deps.uninstallPlugin).toHaveBeenCalledWith('pp');
    expect(state.plugin_perms_pp).toBeFalsy();
    expect(registry.getPlugin('pp')).toBeUndefined();
  });

  it('getAuditLog returns a copy, not the internal list', async () => {
    const { registry } = makeRegistry();
    registry.logOp('pp', 'op', 'd');
    const log = registry.getAuditLog('pp');
    log.length = 0;
    expect(registry.getAuditLog('pp')).toHaveLength(1);
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
