import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import itunesManifest from '../../src/plugins/builtin/itunes/manifest.json';
import * as itunesMain from '../../src/plugins/builtin/itunes/main.js';
import { validateManifest } from '../../src/plugins/manifest';

// The plugin keeps module-level pacing/cooldown state (min interval 3000ms,
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
  const jsonRoutes = new Map();
  const getJson = vi.fn(async (url) => {
    for (const [needle, body] of jsonRoutes) {
      if (String(url).includes(needle)) return { ok: true, status: 200, body };
    }
    return { ok: false, status: 404, error: 'miss' };
  });
  const b64Routes = new Map();
  const getBase64 = vi.fn(async (url) => {
    for (const [needle, base64] of b64Routes) {
      if (String(url).includes(needle)) return { ok: true, status: 200, base64 };
    }
    return { ok: false, status: 404, error: 'miss' };
  });
  const map = new Map(Object.entries(settings));
  const pluginSettings = {
    get: vi.fn(async (k) => map.get(k) ?? null),
    set: vi.fn(async (k, v) => map.set(k, v)),
  };
  return { api: { http: { getJson, getBase64 }, pluginSettings }, jsonRoutes, b64Routes };
}

describe('itunes builtin plugin', () => {
  it('manifest validates', () => {
    const r = validateManifest(itunesManifest);
    expect(r.ok).toBe(true);
  });
  it('picks best result and returns artwork base64', async () => {
    const { api, jsonRoutes, b64Routes } = makeApi();
    jsonRoutes.set('itunes.apple.com', {
      results: [
        { trackName: 'Moon', artistName: 'Z', artworkUrl100: 'https://img/x100x100.jpg' },
        { trackName: 'Sun', artistName: 'A', artworkUrl100: 'https://img/sun100x100bb.jpg' },
      ],
    });
    b64Routes.set('sun600x600bb.jpg', 'b64-jpeg');
    const { fetchCover } = itunesMain.activate(api);
    expect(await fetchCover({ title: 'Sun', artist: 'A' })).toBe('b64-jpeg');
    expect(api.http.getJson.mock.calls[0][0]).toContain('term=Sun+A');
  });
  it('returns null when nothing matches', async () => {
    const { api, jsonRoutes } = makeApi();
    jsonRoutes.set('itunes.apple.com', {
      results: [{ trackName: 'Moon', artistName: 'Z', artworkUrl100: 'https://img/x100x100.jpg' }],
    });
    const { fetchCover } = itunesMain.activate(api);
    expect(await fetchCover({ title: 'Sun', artist: 'A' })).toBeNull();
    expect(api.http.getBase64).not.toHaveBeenCalled();
  });
  it('honors the minMatchScore setting when picking a match', async () => {
    const { api, jsonRoutes } = makeApi({ settings: { minMatchScore: 0.95 } });
    jsonRoutes.set('itunes.apple.com', {
      results: [{ trackName: 'Sun (Live)', artistName: 'A', artworkUrl100: 'https://img/s100x100bb.jpg' }],
    });
    const { fetchCover } = itunesMain.activate(api);
    expect(await fetchCover({ title: 'Sun', artist: 'A' })).toBeNull();
    expect(api.http.getBase64).not.toHaveBeenCalled();
  });
  it('403 throttling sets a cooldown; no further network calls', async () => {
    const { api } = makeApi();
    api.http.getJson.mockResolvedValue({ ok: false, status: 403, error: 'region' });
    const { fetchCover } = itunesMain.activate(api);
    expect(await fetchCover({ title: 'Sun', artist: 'A' })).toBeNull();
    const calls = api.http.getJson.mock.calls.length;
    expect(await fetchCover({ title: 'Sun', artist: 'A' })).toBeNull();
    expect(api.http.getJson.mock.calls.length).toBe(calls);
  });
});
