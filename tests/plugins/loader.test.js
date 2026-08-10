import { describe, it, expect, vi } from 'vitest';
import { createLoader } from '../../src/plugins/loader';

function makeLoader(over = {}) {
  const files = {};
  const readFile = vi.fn(async (pluginId, rel) => files[rel] ? { source: files[rel], bytes: rel.length } : null);
  const imported = {};
  const importUrl = vi.fn(async (url) => imported[url]);
  const deps = {
    readFile, importUrl,
    createApi: vi.fn((pluginId) => ({ info: pluginId })),
    onDenied: vi.fn(),
    hookTimeoutMs: 1000,
    ...over,
  };
  return { loader: createLoader(deps), files, imported, deps };
}

describe('createLoader', () => {
  it('activates a builtin plugin via direct import', async () => {
    const { loader, imported } = makeLoader();
    const hooks = { fetchLyrics: async () => ({ content: 'lrc' }) };
    imported['main.js'] = { activate: vi.fn(() => hooks), deactivate: vi.fn() };
    const entry = { manifest: { main: 'main.js', provides: { lyrics: true }, permissions: ['http'] }, builtin: true };
    const res = await loader.activate('p1', entry);
    expect(res.hooks.fetchLyrics).toBe(hooks.fetchLyrics);
    expect(res.api.info).toBe('p1');
  });
  it('wraps the api with user-granted permissions, not the manifest declaration', async () => {
    const { loader, imported, deps } = makeLoader();
    let capturedApi;
    imported['main.js'] = { activate: (api) => { capturedApi = api; return {}; } };
    deps.createApi.mockReturnValue({
      http: { getJson: () => 'json-ok' },
      metadata: { saveLyrics: () => 'saved' },
    });
    const entry = {
      // manifest requests metadata:write, user granted only http
      manifest: { main: 'main.js', provides: {}, permissions: ['http', 'metadata:write'] },
      builtin: true,
      granted: ['http'],
    };
    await loader.activate('p1', entry);
    expect(capturedApi.http.getJson()).toBe('json-ok');
    expect(() => capturedApi.metadata.saveLyrics(1, 'x')).toThrow(/Permission denied/);
  });
  it('falls back to the manifest permissions when no granted list is supplied', async () => {
    const { loader, imported, deps } = makeLoader();
    let capturedApi;
    imported['main.js'] = { activate: (api) => { capturedApi = api; return {}; } };
    deps.createApi.mockReturnValue({ http: { getJson: () => 'json-ok' } });
    const entry = { manifest: { main: 'main.js', provides: {}, permissions: ['http'] }, builtin: true };
    await loader.activate('p1', entry);
    expect(capturedApi.http.getJson()).toBe('json-ok');
  });
  it('collects and loads user plugin module graphs', async () => {
    const { loader, files, deps } = makeLoader();
    files['main.js'] = "import './helper.js'; export function activate(api){ return {} }";
    files['helper.js'] = 'export const x = 1;';
    // importUrl 返回成功模块，不依赖具体 blob URL
    deps.importUrl.mockImplementation(async () => ({ activate: () => ({}) }));
    const entry = { manifest: { main: 'main.js', provides: {}, permissions: [] }, builtin: false };
    const res = await loader.activate('p1', entry);
    expect(deps.importUrl).toHaveBeenCalled();
    expect(deps.importUrl.mock.calls[0][0]).toMatch(/^blob:/);
    expect(deps.readFile).toHaveBeenCalledWith('p1', 'helper.js');
    expect(res.hooks).toEqual({});
  });
  it('revokes all plugin blob URLs on deactivate', async () => {
    const { loader, files, deps } = makeLoader();
    files['main.js'] = "import './helper.js'; export function activate(api){ return {} }";
    files['helper.js'] = 'export const x = 1;';
    deps.importUrl.mockImplementation(async () => ({ activate: () => ({}) }));
    const revoke = vi.spyOn(URL, 'revokeObjectURL').mockImplementation(() => {});
    try {
      const entry = { manifest: { main: 'main.js', provides: {}, permissions: [] }, builtin: false };
      const res = await loader.activate('p1', entry);
      const mainUrl = deps.importUrl.mock.calls[0][0];
      res.deactivate();
      expect(revoke).toHaveBeenCalledWith(mainUrl);
    } finally {
      revoke.mockRestore();
    }
  });
  it('fails with a clear error when main is missing', async () => {
    const { loader } = makeLoader();
    const entry = { manifest: { main: 'main.js', provides: {}, permissions: [] }, builtin: false };
    await expect(loader.activate('p1', entry)).rejects.toThrow(/main\.js/);
  });
  it('fails when activate throws', async () => {
    const { loader, imported } = makeLoader();
    imported['main.js'] = { activate: () => { throw new Error('boom'); } };
    const entry = { manifest: { main: 'main.js', provides: {}, permissions: [] }, builtin: true };
    await expect(loader.activate('p1', entry)).rejects.toThrow(/boom/);
  });
  it('fails when activate is missing', async () => {
    const { loader, imported } = makeLoader();
    imported['main.js'] = {};
    const entry = { manifest: { main: 'main.js', provides: {}, permissions: [] }, builtin: true };
    await expect(loader.activate('p1', entry)).rejects.toThrow(/activate/);
  });
  it('fails when a declared provider hook is missing', async () => {
    const { loader, imported } = makeLoader();
    imported['main.js'] = { activate: () => ({}) };
    const entry = { manifest: { main: 'main.js', provides: { lyrics: true }, permissions: [] }, builtin: true };
    await expect(loader.activate('p1', entry)).rejects.toThrow(/fetchLyrics/);
  });
  it('fails when a declared cover provider hook is missing', async () => {
    const { loader, imported } = makeLoader();
    imported['main.js'] = { activate: () => ({}) };
    const entry = { manifest: { main: 'main.js', provides: { cover: true }, permissions: [] }, builtin: true };
    await expect(loader.activate('p1', entry)).rejects.toThrow(/fetchCover/);
  });
  it('deactivate is a no-op when the module has no deactivate', async () => {
    const { loader, imported } = makeLoader();
    imported['main.js'] = { activate: () => ({}) };
    const entry = { manifest: { main: 'main.js', provides: {}, permissions: [] }, builtin: true };
    const res = await loader.activate('p1', entry);
    expect(() => res.deactivate()).not.toThrow();
  });
  it('enforces hook timeout', async () => {
    const { loader, imported } = makeLoader({ hookTimeoutMs: 20 });
    imported['main.js'] = { activate: () => new Promise((r) => setTimeout(r, 200)) };
    const entry = { manifest: { main: 'main.js', provides: {}, permissions: [] }, builtin: true };
    await expect(loader.activate('p1', entry)).rejects.toThrow(/timeout/);
  });
});
