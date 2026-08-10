import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import lrclibManifest from '../../src/plugins/builtin/lrclib/manifest.json';
import * as lrclibMain from '../../src/plugins/builtin/lrclib/main.js';
import { validateManifest } from '../../src/plugins/manifest';

// The plugin keeps module-level pacing/cooldown state (min interval 1200ms,
// cooldown 5s) — advance Date.now past the previous test's window so tests
// are fast and order-independent.
let now = Date.now();
beforeEach(() => {
  now += 60000;
  vi.spyOn(Date, 'now').mockImplementation(() => now);
});
afterEach(() => {
  vi.restoreAllMocks();
});

function makeApi({ settings = {} } = {}) {
  const routes = new Map();
  const getJson = vi.fn(async (url) => {
    for (const [needle, body] of routes) {
      if (String(url).includes(needle)) return { ok: true, status: 200, body };
    }
    return { ok: false, status: 404, error: 'miss' };
  });
  const map = new Map(Object.entries({ requestIntervalMs: 0, minMatchScore: 0.8, ...settings }));
  const pluginSettings = {
    get: vi.fn(async (k) => map.get(k) ?? null),
    set: vi.fn(async (k, v) => map.set(k, v)),
  };
  return { api: { http: { getJson, getBase64: vi.fn() }, pluginSettings }, routes };
}

describe('lrclib builtin plugin', () => {
  it('manifest validates', () => {
    const r = validateManifest(lrclibManifest);
    expect(r.ok).toBe(true);
  });
  it('fetches lyrics via /api/get', async () => {
    const { api, routes } = makeApi();
    routes.set('lrclib.net/api/get', { syncedLyrics: '[00:01.00]hi' });
    const { fetchLyrics } = lrclibMain.activate(api);
    expect(await fetchLyrics({ title: 'Sun', artist: 'A' })).toBe('[00:01.00]hi');
  });
  it('falls back to search with best match', async () => {
    const { api, routes } = makeApi();
    routes.set('lrclib.net/api/get', null);
    routes.set('lrclib.net/api/search', [
      { track_name: 'Sun', artist_name: 'A', syncedLyrics: '[00:01.00]yes' },
      { track_name: 'Other', artist_name: 'Z', syncedLyrics: '[00:01.00]no' },
    ]);
    const { fetchLyrics } = lrclibMain.activate(api);
    expect(await fetchLyrics({ title: 'Sun', artist: 'A' })).toBe('[00:01.00]yes');
  });
  it('returns null when nothing matches', async () => {
    const { api, routes } = makeApi();
    routes.set('lrclib.net/api/get', null);
    routes.set('lrclib.net/api/search', [{ track_name: 'Zzz', artist_name: 'Q', syncedLyrics: 'x' }]);
    const { fetchLyrics } = lrclibMain.activate(api);
    expect(await fetchLyrics({ title: 'Sun', artist: 'A' })).toBeNull();
  });
  it('returns null when the best match has blank synced lyrics', async () => {
    const { api, routes } = makeApi();
    routes.set('lrclib.net/api/get', null);
    routes.set('lrclib.net/api/search', [{ track_name: 'Sun', artist_name: 'A', syncedLyrics: '   ' }]);
    const { fetchLyrics } = lrclibMain.activate(api);
    expect(await fetchLyrics({ title: 'Sun', artist: 'A' })).toBeNull();
  });
  it('paces before each request, including the search fallback', async () => {
    const { api, routes } = makeApi({ settings: { requestIntervalMs: 100 } });
    routes.set('lrclib.net/api/get', null);
    routes.set('lrclib.net/api/search', [{ track_name: 'Sun', artist_name: 'A', syncedLyrics: '[00:01.00]yes' }]);
    const timer = vi.spyOn(globalThis, 'setTimeout');
    const { fetchLyrics } = lrclibMain.activate(api);
    expect(await fetchLyrics({ title: 'Sun', artist: 'A' })).toBe('[00:01.00]yes');
    const waits = timer.mock.calls.map((c) => c[1]).filter((ms) => ms > 0);
    expect(waits).toContain(100);
  });
});
