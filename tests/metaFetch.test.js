import { describe, it, expect, vi, afterEach } from 'vitest';
import {
  normalizeForMatch, similarity, buildLrclibGetUrl, lrclibResponseToLrc,
  pickBestMatch, fetchLyricsForTrack, buildItunesUrl, itunesArtworkLarge,
  fetchCoverForTrack, resetRateLimitState, rateConfig,
} from '../src/services/metaFetch';

// The service keeps module-level rate-limit/cooldown state — reset it and
// zero the pacing intervals so tests are fast and order-independent.
afterEach(() => {
  vi.unstubAllGlobals();
  resetRateLimitState();
  rateConfig.lrclibMinInterval = 0;
  rateConfig.itunesMinInterval = 0;
  rateConfig.retryDelayMs = 0;
});

// All API requests go through the native bridge — mock it per test.
function mockHttp(routes) {
  const fn = vi.fn(async (url) => {
    for (const [needle, body] of routes) {
      if (String(url).includes(needle)) {
        return { ok: true, status: 200, body };
      }
    }
    return { ok: false, status: 404, error: 'mock miss' };
  });
  window.freeplayer.httpGetJson = fn;
  return fn;
}

describe('normalizeForMatch / similarity', () => {
  it('normalizes case, punctuation and whitespace', () => {
    expect(normalizeForMatch('  Some Song, (Live)! ')).toBe('some song live');
    expect(normalizeForMatch('晴天')).toBe('晴天');
  });
  it('scores exact matches 1 and containment 0.9', () => {
    expect(similarity('some song', 'Some Song')).toBe(1);
    expect(similarity('晴天', '晴天 (Live)')).toBe(0.9);
  });
  it('scores token overlap between 0 and 1', () => {
    expect(similarity('hello world', 'hello there')).toBe(0.5);
    expect(similarity('hello', 'world')).toBe(0);
  });
});

describe('LRCLIB', () => {
  it('builds a get URL with all fields', () => {
    const url = buildLrclibGetUrl({ title: 'Sun', artist: 'A B', album: 'X', duration: 213.7 });
    // URLSearchParams serializes spaces as '+', which both APIs accept
    expect(url).toContain('artist_name=A+B');
    expect(url).toContain('track_name=Sun');
    expect(url).toContain('album_name=X');
    expect(url).toContain('duration=214');
  });
  it('omits unknown artist/album and missing duration', () => {
    const url = buildLrclibGetUrl({ title: 'Sun', artist: 'Unknown Artist' });
    expect(url).not.toContain('artist_name');
    expect(url).not.toContain('album_name');
    expect(url).not.toContain('duration');
  });
  it('returns synced lyrics, null for plain-only', () => {
    expect(lrclibResponseToLrc({ syncedLyrics: '[00:01.00]hi' })).toBe('[00:01.00]hi');
    expect(lrclibResponseToLrc({ syncedLyrics: '  ' })).toBeNull();
    expect(lrclibResponseToLrc({ plainLyrics: 'hi' })).toBeNull();
    expect(lrclibResponseToLrc(null)).toBeNull();
  });
  it('fetchLyricsForTrack: exact get hit', async () => {
    mockHttp([['lrclib.net/api/get', { syncedLyrics: '[00:01.00]hi' }]]);
    expect(await fetchLyricsForTrack({ title: 'Sun', artist: 'A' })).toBe('[00:01.00]hi');
  });
  it('fetchLyricsForTrack: unknown artist skips get (400s) and searches', async () => {
    const fn = mockHttp([
      ['lrclib.net/api/search', [{ track_name: 'Sun', artist_name: 'A', syncedLyrics: '[00:01.00]yes' }]],
    ]);
    expect(await fetchLyricsForTrack({ title: 'Sun', artist: 'Unknown Artist' })).toBe('[00:01.00]yes');
    expect(String(fn.mock.calls[0][0])).toContain('api/search');
    expect(String(fn.mock.calls[0][0])).not.toContain('api/get');
  });
  it('fetchLyricsForTrack: falls back to search with best match', async () => {
    mockHttp([
      ['lrclib.net/api/get', null],
      ['lrclib.net/api/search', [
        { track_name: 'Sun', artist_name: 'A', syncedLyrics: '[00:01.00]yes' },
        { track_name: 'Different', artist_name: 'Z', syncedLyrics: '[00:01.00]no' },
      ]],
    ]);
    expect(await fetchLyricsForTrack({ title: 'Sun', artist: 'A' })).toBe('[00:01.00]yes');
  });
  it('fetchLyricsForTrack: no acceptable match returns null', async () => {
    mockHttp([
      ['lrclib.net/api/get', null],
      ['lrclib.net/api/search', [{ track_name: 'Other Thing', artist_name: 'Z', syncedLyrics: '[00:01.00]x' }]],
    ]);
    expect(await fetchLyricsForTrack({ title: 'Sun', artist: 'A' })).toBeNull();
  });
  it('fetchLyricsForTrack: bridge unavailable resolves null without throwing', async () => {
    window.freeplayer.httpGetJson = vi.fn(async () => { throw new TypeError('bridge missing'); });
    expect(await fetchLyricsForTrack({ title: 'Sun', artist: 'A' })).toBeNull();
  });
  it('fetchLyricsForTrack: 429 throttling sets a cooldown and returns null', async () => {
    window.freeplayer.httpGetJson = vi.fn(async () => ({ ok: false, status: 429, error: 'rate' }));
    expect(await fetchLyricsForTrack({ title: 'Sun', artist: 'A' })).toBeNull();
    // second call within cooldown must not hit the network at all
    const calls = window.freeplayer.httpGetJson.mock.calls.length;
    expect(await fetchLyricsForTrack({ title: 'Sun', artist: 'A' })).toBeNull();
    expect(window.freeplayer.httpGetJson.mock.calls.length).toBe(calls);
  });
  it('fetchLyricsForTrack: search path 429 sets cooldown', async () => {
    window.freeplayer.httpGetJson = vi.fn(async (url) => {
      if (String(url).includes('/api/get')) {
        return { ok: false, status: 404, error: 'miss' }; // get miss -> fall through to search
      }
      return { ok: false, status: 429, error: 'rate' };
    });
    expect(await fetchLyricsForTrack({ title: 'Sun', artist: 'A' })).toBeNull();
    expect(String(window.freeplayer.httpGetJson.mock.calls[1][0])).toContain('api/search');
    // second call within cooldown must not hit the network at all
    const calls = window.freeplayer.httpGetJson.mock.calls.length;
    expect(await fetchLyricsForTrack({ title: 'Sun', artist: 'A' })).toBeNull();
    expect(window.freeplayer.httpGetJson.mock.calls.length).toBe(calls);
  });
});

describe('pickBestMatch', () => {
  it('requires title similarity >= 0.8 and artist >= 0.5', () => {
    const track = { title: 'Sun', artist: 'A B' };
    const good = { title: 'Sun', artist: 'A B' };
    const badTitle = { title: 'Moon', artist: 'A B' };
    const badArtist = { title: 'Sun', artist: 'Z Z' };
    expect(pickBestMatch([badTitle, good, badArtist], track)).toBe(good);
  });
  it('ignores artist criterion when artist is unknown', () => {
    const track = { title: 'Sun', artist: 'Unknown Artist' };
    const cand = { title: 'Sun', artist: 'Whatever' };
    expect(pickBestMatch([cand], track)).toBe(cand);
  });
});

describe('iTunes cover', () => {
  it('builds search URL with media/entity/limit', () => {
    const url = buildItunesUrl({ title: 'Sun', artist: 'A' });
    expect(url).toContain('term=Sun+A');
    expect(url).toContain('media=music');
    expect(url).toContain('entity=song');
    expect(url).toContain('limit=10');
  });
  it('upscales artwork from 100x100 to 600x600', () => {
    expect(itunesArtworkLarge('https://a.com/art/abc100x100bb.jpg')).toBe('https://a.com/art/abc600x600bb.jpg');
  });
  it('fetchCoverForTrack: picks best result and returns base64', async () => {
    mockHttp([['itunes.apple.com', {
      results: [
        { trackName: 'Moon', artistName: 'Z', artworkUrl100: 'https://img/x100x100.jpg' },
        { trackName: 'Sun', artistName: 'A', artworkUrl100: 'https://img/sun100x100bb.jpg' },
      ],
    }]]);
    window.freeplayer.httpGetBase64 = vi.fn(async (url) => {
      // artwork download through the native stack
      expect(String(url)).toContain('sun600x600bb.jpg');
      return { ok: true, status: 200, base64: Buffer.from('jpeg-bytes').toString('base64') };
    });
    const b64 = await fetchCoverForTrack({ title: 'Sun', artist: 'A' });
    expect(b64).toBe(Buffer.from('jpeg-bytes').toString('base64'));
  });
  it('fetchCoverForTrack: no results returns null', async () => {
    mockHttp([['itunes.apple.com', { results: [] }]]);
    expect(await fetchCoverForTrack({ title: 'Sun', artist: 'A' })).toBeNull();
  });
  it('fetchCoverForTrack: network failure retries once, then succeeds', async () => {
    let calls = 0;
    window.freeplayer.httpGetJson = vi.fn(async () => {
      calls++;
      if (calls === 1) return null; // network error -> null
      return { ok: true, status: 200, body: {
        results: [{ trackName: 'Sun', artistName: 'A', artworkUrl100: 'https://img/s100x100bb.jpg' }],
      } };
    });
    window.freeplayer.httpGetBase64 = vi.fn(async () => ({ ok: true, status: 200, base64: Buffer.from('jpeg-bytes').toString('base64') }));
    const b64 = await fetchCoverForTrack({ title: 'Sun', artist: 'A' });
    expect(b64).toBe(Buffer.from('jpeg-bytes').toString('base64'));
    expect(calls).toBeGreaterThanOrEqual(2);
  });
  it('fetchCoverForTrack: artwork download failure returns null', async () => {
    mockHttp([['itunes.apple.com', {
      results: [{ trackName: 'Sun', artistName: 'A', artworkUrl100: 'https://img/s100x100bb.jpg' }],
    }]]);
    window.freeplayer.httpGetBase64 = vi.fn(async () => ({ ok: false, status: 500, error: 'http error' }));
    expect(await fetchCoverForTrack({ title: 'Sun', artist: 'A' })).toBeNull();
  });
  it('fetchCoverForTrack: artwork bridge unavailable resolves null', async () => {
    mockHttp([['itunes.apple.com', {
      results: [{ trackName: 'Sun', artistName: 'A', artworkUrl100: 'https://img/s100x100bb.jpg' }],
    }]]);
    window.freeplayer.httpGetBase64 = vi.fn(async () => { throw new TypeError('bridge missing'); });
    expect(await fetchCoverForTrack({ title: 'Sun', artist: 'A' })).toBeNull();
  });
  it('fetchCoverForTrack: 403 throttling sets a cooldown and returns null', async () => {
    window.freeplayer.httpGetJson = vi.fn(async () => ({ ok: false, status: 403, error: 'region' }));
    expect(await fetchCoverForTrack({ title: 'Sun', artist: 'A' })).toBeNull();
    const calls = window.freeplayer.httpGetJson.mock.calls.length;
    expect(await fetchCoverForTrack({ title: 'Sun', artist: 'A' })).toBeNull();
    expect(window.freeplayer.httpGetJson.mock.calls.length).toBe(calls);
  });
});
