import { describe, it, expect, vi } from 'vitest';
import mbManifest from '../../src/plugins/builtin/musicbrainz/manifest.json';
import mbMain from '../../src/plugins/builtin/musicbrainz/main.js';
import { validateManifest } from '../../src/plugins/manifest';

function makeApi({ apiToken = '' } = {}) {
  const routes = new Map();
  const getJson = vi.fn(async (url) => {
    for (const [needle, body] of routes) {
      if (String(url).includes(needle)) return { ok: true, status: 200, body };
    }
    return { ok: false, status: 404, error: 'miss' };
  });
  const settings = new Map([['requestIntervalMs', 0], ['minMatchScore', 0.8], ['apiEndpoint', 'https://musicbrainz.org/ws/2'], ['apiToken', apiToken]]);
  const pluginSettings = {
    get: vi.fn(async (k) => settings.get(k) ?? null),
    set: vi.fn(async (k, v) => settings.set(k, v)),
  };
  const getBase64 = vi.fn(async () => ({ ok: true, status: 200, base64: Buffer.from('jpeg').toString('base64') }));
  return { api: { http: { getJson, getBase64 }, pluginSettings }, routes };
}

describe('musicbrainz builtin plugin', () => {
  it('manifest validates (metadata + cover, notice, write permission)', () => {
    const r = validateManifest(mbManifest);
    expect(r.ok).toBe(true);
    expect(r.manifest.provides.metadata).toBe(true);
    expect(r.manifest.notice.length).toBeGreaterThan(0);
  });
  it('fetchMetadata: search + assemble fields with inc', async () => {
    const { api, routes } = makeApi();
    routes.set('musicbrainz.org/ws/2/recording?query=', {
      recordings: [{
        id: 'rec-1', title: 'Sun', 'artist-credit': [{ name: 'A B' }],
        releases: [{ title: 'X', 'release-group': { id: 'rg-1', 'first-release-date': '2020-03-01', tags: [{ name: 'Rock', count: 10 }] }, media: [{ track: [{ id: 'rec-1', number: '3' }] }] }],
      }],
    });
    const { fetchMetadata } = mbMain.activate(api);
    const out = await fetchMetadata({ id: 7, title: 'Sun', artist: 'A B', album: 'Old' });
    expect(out.title).toBe('Sun');
    expect(out.year).toBe(2020);
    expect(out.genre).toBe('Rock');
    expect(out.album).toBe('X');
    expect(out.track_number).toBe('3');
    expect(String(api.http.getJson.mock.calls[0][0])).toContain('inc=');
  });
  it('fetchMetadata: returns null when nothing matches', async () => {
    const { api, routes } = makeApi();
    routes.set('musicbrainz.org', { recordings: [] });
    const { fetchMetadata } = mbMain.activate(api);
    expect(await fetchMetadata({ title: 'Zzz', artist: 'Q' })).toBeNull();
  });
  it('fetchCover: downloads front art via coverartarchive', async () => {
    const { api, routes } = makeApi();
    routes.set('musicbrainz.org/ws/2/recording?query=', {
      recordings: [{ id: 'rec-1', title: 'Sun', 'artist-credit': [{ name: 'A' }], releases: [{ 'release-group': { id: 'rg-1' } }] }],
    });
    routes.set('coverartarchive.org/release-group/rg-1', {
      images: [{ front: true, thumbnails: { '500': 'https://art.example/front-500.jpg' } }],
    });
    const { fetchCover } = mbMain.activate(api);
    const b64 = await fetchCover({ title: 'Sun', artist: 'A' });
    expect(b64).toBe(Buffer.from('jpeg').toString('base64'));
    expect(String(api.http.getBase64.mock.calls[0][0])).toContain('front-500.jpg');
  });
  it('fetchCover reuses the MBID cached by fetchMetadata (no second search)', async () => {
    const { api, routes } = makeApi();
    routes.set('musicbrainz.org/ws/2/recording?query=', {
      recordings: [{ id: 'rec-9', title: 'Sun', 'artist-credit': [{ name: 'A' }], releases: [{ 'release-group': { id: 'rg-9' } }] }],
    });
    routes.set('coverartarchive.org/release-group/rg-9', {
      images: [{ front: true, thumbnails: { '500': 'https://art.example/front-500.jpg' } }],
    });
    const { fetchMetadata, fetchCover } = mbMain.activate(api);
    await fetchMetadata({ id: 9, title: 'Sun', artist: 'A' });
    const b64 = await fetchCover({ id: 9, title: 'Sun', artist: 'A' });
    expect(b64).toBe(Buffer.from('jpeg').toString('base64'));
    const searchCalls = api.http.getJson.mock.calls.filter(([u]) => String(u).includes('recording?query='));
    expect(searchCalls.length).toBe(1);
  });
  it('access_token goes to MusicBrainz only, never to coverartarchive', async () => {
    const { api, routes } = makeApi({ apiToken: 's3cret-token' });
    routes.set('musicbrainz.org/ws/2/recording?query=', {
      recordings: [{ id: 'rec-1', title: 'Sun', 'artist-credit': [{ name: 'A' }], releases: [{ 'release-group': { id: 'rg-1' } }] }],
    });
    routes.set('coverartarchive.org/release-group/rg-1', {
      images: [{ front: true, thumbnails: { '500': 'https://art.example/front-500.jpg' } }],
    });
    const { fetchCover } = mbMain.activate(api);
    const b64 = await fetchCover({ title: 'Sun', artist: 'A' });
    expect(b64).toBe(Buffer.from('jpeg').toString('base64'));
    const calls = api.http.getJson.mock.calls.map(([u]) => String(u));
    expect(calls[0]).toContain('musicbrainz.org');
    expect(calls[0]).toContain('access_token=s3cret-token');
    const caa = calls.filter((u) => u.includes('coverartarchive.org'));
    expect(caa.length).toBe(1);
    expect(caa[0]).not.toContain('access_token');
  });
});
