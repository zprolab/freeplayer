import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createLoader } from '../../src/plugins/loader';

// Worker mock installed by tests/setup.js (globalThis.Worker).
function lastWorker() {
  const w = Worker.instances[Worker.instances.length - 1];
  if (!w) throw new Error('no Worker instance was created');
  return w;
}

// The loader's user-plugin path awaits readFile before creating the worker,
// so tests must wait a tick for it to appear.
async function waitForWorker() {
  for (let i = 0; i < 50; i++) {
    if (Worker.instances.length) return lastWorker();
    await new Promise((r) => setTimeout(r, 0));
  }
  throw new Error('no Worker instance was created');
}

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
    deactivateGraceMs: 1,
    ...over,
  };
  return { loader: createLoader(deps), files, imported, deps };
}

// Captures every Blob handed to URL.createObjectURL so tests can read the
// worker bootstrap source and enumerate module blobs.
function captureBlobs() {
  const blobs = [];
  const spy = vi.spyOn(URL, 'createObjectURL').mockImplementation((blob) => {
    blobs.push(blob);
    return `blob:mock-${blobs.length}`;
  });
  return { blobs, spy, urls: () => blobs.map((_, i) => `blob:mock-${i + 1}`) };
}

const blobText = async (blob) => (await blob.text());

// Starts activation, waits for the worker to appear, then drives the
// handshake: resolve loader.activate() once the test emits 'activated'.
async function activateUserPlugin(loader, entry, opts = {}) {
  const promise = loader.activate('p1', entry);
  const worker = await waitForWorker();
  if (opts.onActivate) opts.onActivate(worker);
  if (opts.hooks !== undefined) worker.emit({ type: 'activated', hooks: opts.hooks });
  const res = await promise;
  return { worker, res };
}

describe('createLoader', () => {
  beforeEach(() => Worker.reset());
  afterEach(() => vi.restoreAllMocks());

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
  it('collects user module graphs and runs them in a module worker (no page import)', async () => {
    const { loader, files, deps } = makeLoader();
    const { blobs, urls } = captureBlobs();
    files['main.js'] = "import './helper.js'; export function activate(api){ return {} }";
    files['helper.js'] = 'export const x = 1;';
    const entry = { manifest: { main: 'main.js', provides: {}, permissions: [] }, builtin: false };
    const { worker, res } = await activateUserPlugin(loader, entry, { hooks: [] });

    expect(worker.options.type).toBe('module');
    expect(deps.importUrl).not.toHaveBeenCalled();
    expect(deps.readFile).toHaveBeenCalledWith('p1', 'helper.js');
    expect(res.hooks).toEqual({});
    // two module blobs (main + helper) + the worker bootstrap blob
    expect(worker.url).toBe(urls()[2]);
    // the worker blob embeds the sandbox runtime + a config line carrying the
    // entry module url and the plugin meta.
    const workerSource = await blobText(blobs[2]);
    expect(workerSource).toContain('__fpSandboxConfig');
    // module graph is post-order: helper blob first, main entry second
    expect(workerSource).toContain('"entry":"blob:mock-2"');
    expect(workerSource).toContain('"id":"p1"');
    // the loader must have asked the worker to activate p1
    expect(worker.sent[0]).toMatchObject({ type: 'activate', pluginId: 'p1' });
  });
  it('revokes all plugin blob URLs (modules + worker blob) and terminates on deactivate', async () => {
    const { loader, files } = makeLoader();
    captureBlobs();
    files['main.js'] = "import './helper.js'; export function activate(api){ return {} }";
    files['helper.js'] = 'export const x = 1;';
    const entry = { manifest: { main: 'main.js', provides: {}, permissions: [] }, builtin: false };
    const { worker, res } = await activateUserPlugin(loader, entry, { hooks: [] });

    const revoke = vi.spyOn(URL, 'revokeObjectURL').mockImplementation(() => {});
    try {
      res.deactivate();
      expect(worker.sent.find((m) => m.type === 'deactivate')).toBeTruthy();
      await new Promise((r) => setTimeout(r, 5)); // grace
      expect(worker.terminated).toBe(true);
      expect(revoke).toHaveBeenCalledWith('blob:mock-1'); // helper module
      expect(revoke).toHaveBeenCalledWith('blob:mock-2'); // main module
      expect(revoke).toHaveBeenCalledWith('blob:mock-3'); // worker bootstrap
    } finally {
      revoke.mockRestore();
    }
  });
  it('fails with a clear error when main is missing', async () => {
    const { loader } = makeLoader();
    const entry = { manifest: { main: 'main.js', provides: {}, permissions: [] }, builtin: false };
    await expect(loader.activate('p1', entry)).rejects.toThrow(/main\.js/);
    expect(Worker.instances).toHaveLength(0);
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
  it('fails when a declared metadata provider hook is missing', async () => {
    const { loader, imported } = makeLoader();
    imported['main.js'] = { activate: () => ({}) };
    const entry = { manifest: { main: 'main.js', provides: { metadata: true }, permissions: [] }, builtin: true };
    await expect(loader.activate('p1', entry)).rejects.toThrow(/fetchMetadata/);
  });
  it('worker path: rejects when a declared provider hook is not reported', async () => {
    const { loader, files } = makeLoader();
    captureBlobs();
    files['main.js'] = 'export function activate(api){ return {} }';
    const entry = { manifest: { main: 'main.js', provides: { lyrics: true }, permissions: [] }, builtin: false };
    const promise = loader.activate('p1', entry);
    const worker = await waitForWorker();
    worker.emit({ type: 'activated', hooks: ['fetchCover'] });
    await expect(promise).rejects.toThrow(/fetchLyrics/);
    expect(worker.terminated).toBe(true);
  });
  it('worker path: worker error rejects the activation promise', async () => {
    const { loader, files } = makeLoader();
    captureBlobs();
    files['main.js'] = 'export function activate(api){ return {} }';
    const entry = { manifest: { main: 'main.js', provides: {}, permissions: [] }, builtin: false };
    const promise = loader.activate('p1', entry);
    const worker = await waitForWorker();
    worker.fail('script crashed');
    await expect(promise).rejects.toThrow(/script crashed/);
  });
  it('worker path: activation timeout terminates the worker', async () => {
    const { loader, files } = makeLoader({ hookTimeoutMs: 20 });
    captureBlobs();
    files['main.js'] = 'export function activate(api){ return {} }';
    const entry = { manifest: { main: 'main.js', provides: {}, permissions: [] }, builtin: false };
    const promise = loader.activate('p1', entry);
    const worker = await waitForWorker();
    await expect(promise).rejects.toThrow(/timeout/);
    expect(worker.terminated).toBe(true);
  });
  it('worker path: reported hooks round-trip results and errors', async () => {
    const { loader, files } = makeLoader();
    captureBlobs();
    files['main.js'] = 'export function activate(api){ return {} }';
    const entry = { manifest: { main: 'main.js', provides: { lyrics: true }, permissions: [] }, builtin: false };
    const { worker, res } = await activateUserPlugin(loader, entry, { hooks: ['fetchLyrics'] });

    const resultP = res.hooks.fetchLyrics({ title: 'Sun' });
    const invoke = worker.sent.find((m) => m.type === 'invokeHook');
    expect(invoke).toMatchObject({ hook: 'fetchLyrics', payload: { title: 'Sun' } });
    worker.emit({ type: 'hookResult', seq: invoke.seq, result: 'lrc' });
    await expect(resultP).resolves.toBe('lrc');

    const errP = res.hooks.fetchLyrics({});
    const invoke2 = worker.sent.find((m) => m.type === 'invokeHook' && m.seq === invoke.seq + 1);
    worker.emit({ type: 'hookResult', seq: invoke2.seq, error: 'server 500' });
    await expect(errP).rejects.toThrow(/server 500/);
  });
  it('worker path: a missing hook reported by the worker propagates as hook missing', async () => {
    const { loader, files } = makeLoader();
    captureBlobs();
    files['main.js'] = 'export function activate(api){ return {} }';
    const entry = { manifest: { main: 'main.js', provides: {}, permissions: [] }, builtin: false };
    const { worker, res } = await activateUserPlugin(loader, entry, { hooks: ['fetchLyrics'] });
    // the worker's own guard posts 'hook missing' errors back to the host
    const resultP = res.hooks.fetchLyrics({});
    const invoke = worker.sent.find((m) => m.type === 'invokeHook');
    expect(invoke).toBeTruthy();
    worker.emit({ type: 'hookResult', seq: invoke.seq, error: 'hook missing: fetchLyrics' });
    await expect(resultP).rejects.toThrow(/hook missing/);
  });
  it('worker path: api calls dispatch through the permission-wrapped executor', async () => {
    const { loader, files, deps } = makeLoader();
    captureBlobs();
    files['main.js'] = 'export function activate(api){ return {} }';
    deps.createApi.mockReturnValue({
      http: { getJson: async (u) => ({ url: u }) },
      metadata: { deleteTrack: async () => 'deleted' },
    });
    const entry = {
      manifest: { main: 'main.js', provides: {}, permissions: ['http', 'metadata:admin'] },
      granted: ['http'],
      builtin: false,
    };
    const { worker } = await activateUserPlugin(loader, entry, { hooks: [] });

    worker.emit({ type: 'apiCall', seq: 1, method: 'http.getJson', args: ['https://x'] });
    await new Promise((r) => setTimeout(r, 0));
    const okReply = worker.sent.find((m) => m.type === 'apiResult' && m.seq === 1);
    expect(okReply.result).toEqual({ url: 'https://x' });

    // metadata:deleteTrack requires metadata:admin, only http granted
    worker.emit({ type: 'apiCall', seq: 2, method: 'metadata.deleteTrack', args: [9] });
    await new Promise((r) => setTimeout(r, 0));
    const deniedReply = worker.sent.find((m) => m.type === 'apiResult' && m.seq === 2);
    expect(deniedReply.error).toMatch(/Permission denied/);
    expect(deps.onDenied).toHaveBeenCalledWith('p1', 'metadata.deleteTrack');

    // unknown method -> error reply, no throw
    worker.emit({ type: 'apiCall', seq: 3, method: 'nope.missing', args: [] });
    await new Promise((r) => setTimeout(r, 0));
    const unknownReply = worker.sent.find((m) => m.type === 'apiResult' && m.seq === 3);
    expect(unknownReply.error).toMatch(/unknown api method/);
  });
  it('worker path: event subscriptions are gated and forwarded, then released on deactivate', async () => {
    const { loader, files, deps } = makeLoader();
    captureBlobs();
    files['main.js'] = 'export function activate(api){ return {} }';
    const registered = [];
    deps.createApi.mockReturnValue({
      events: {
        on: (ch, cb, owner) => registered.push({ ch, cb, owner }),
        off: (ch, cb) => { const i = registered.findIndex((e) => e.ch === ch && e.cb === cb); if (i >= 0) registered.splice(i, 1); },
        removeOwner: (owner) => { for (let i = registered.length - 1; i >= 0; i--) if (registered[i].owner === owner) registered.splice(i, 1); },
      },
    });
    const entry = { manifest: { main: 'main.js', provides: {}, permissions: ['player:read'] }, builtin: false };
    const { worker, res } = await activateUserPlugin(loader, entry, { hooks: [] });

    worker.emit({ type: 'eventsOn', channel: 'trackChanged' });
    expect(registered).toHaveLength(1);
    expect(registered[0].ch).toBe('trackChanged');
    // (owner tagging happens in createPluginApi — see api.test.js)
    registered[0].cb({ id: 5 }); // host bus fires -> forwarded to worker
    const evt = worker.sent.find((m) => m.type === 'event');
    expect(evt).toEqual({ type: 'event', channel: 'trackChanged', payload: { id: 5 } });

    worker.emit({ type: 'eventsOff', channel: 'trackChanged' });
    expect(registered).toHaveLength(0);

    // re-subscribe, then deactivate -> host subscription is dropped
    worker.emit({ type: 'eventsOn', channel: 'trackChanged' });
    expect(registered).toHaveLength(1);
    res.deactivate();
    await new Promise((r) => setTimeout(r, 5)); // grace
    expect(worker.terminated).toBe(true);
    expect(registered).toHaveLength(0);
  });
  it('worker path: events without player:read are denied', async () => {
    const { loader, files, deps } = makeLoader();
    captureBlobs();
    files['main.js'] = 'export function activate(api){ return {} }';
    const registered = [];
    deps.createApi.mockReturnValue({
      events: {
        on: (ch, cb, owner) => registered.push({ ch, cb, owner }),
        off: () => {}, removeOwner: () => {},
      },
    });
    const entry = { manifest: { main: 'main.js', provides: {}, permissions: [] }, builtin: false };
    const { worker } = await activateUserPlugin(loader, entry, { hooks: [] });

    worker.emit({ type: 'eventsOn', channel: 'trackChanged' });
    expect(registered).toHaveLength(0);
    expect(deps.onDenied).toHaveBeenCalledWith('p1', 'events.on');
  });
  it('worker path: deactivate posts deactivate, then terminates and revokes blobs', async () => {
    const { loader, files } = makeLoader();
    captureBlobs();
    files['main.js'] = 'export function activate(api){ return {} }';
    const entry = { manifest: { main: 'main.js', provides: {}, permissions: [] }, builtin: false };
    const { worker, res } = await activateUserPlugin(loader, entry, { hooks: [] });

    const revoke = vi.spyOn(URL, 'revokeObjectURL').mockImplementation(() => {});
    try {
      res.deactivate();
      expect(worker.sent.find((m) => m.type === 'deactivate')).toBeTruthy();
      await new Promise((r) => setTimeout(r, 5)); // grace
      expect(worker.terminated).toBe(true);
      expect(revoke).toHaveBeenCalledWith('blob:mock-1'); // main module
      expect(revoke).toHaveBeenCalledWith('blob:mock-2'); // worker bootstrap
    } finally {
      revoke.mockRestore();
    }
  });
  it('worker path: meta.info carries the real manifest identity', async () => {
    const { loader, files, deps } = makeLoader();
    captureBlobs();
    files['main.js'] = 'export function activate(api){ return {} }';
    deps.createApi.mockReturnValue({ meta: { info: { id: 'p1', name: '', version: '' } }, http: {} });
    const entry = {
      manifest: { main: 'main.js', provides: {}, permissions: [], name: 'My Plugin', version: '2.1.0' },
      builtin: false,
    };
    const { res } = await activateUserPlugin(loader, entry, { hooks: [] });
    expect(res.api.meta.info).toEqual({ id: 'p1', name: 'My Plugin', version: '2.1.0' });
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
