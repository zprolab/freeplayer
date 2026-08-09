import { describe, it, expect, vi, afterEach } from 'vitest';
import { fetchAndSaveLyrics, fetchAndSaveCover } from '../src/services/metaPersistence';
import { resetRateLimitState, rateConfig } from '../src/services/metaFetch';

afterEach(() => {
  vi.unstubAllGlobals();
  resetRateLimitState();
  rateConfig.lrclibMinInterval = 0;
  rateConfig.itunesMinInterval = 0;
  rateConfig.retryDelayMs = 0;
});

function mockBridge(httpJson, saveLrc, saveCover, httpBase64) {
  window.freeplayer.httpGetJson = vi.fn(httpJson);
  window.freeplayer.httpGetBase64 = vi.fn(httpBase64 || (async () => ({ ok: true, status: 200, base64: Buffer.from('jpeg').toString('base64') })));
  window.freeplayer.saveLrcContent = vi.fn(saveLrc || (async () => ({ success: true, lrcPath: '/x.lrc' })));
  window.freeplayer.saveCover = vi.fn(saveCover || (async () => ({ success: true, coverPath: '/x.jpg' })));
}

describe('fetchAndSaveLyrics', () => {
  it('fetches and saves lyrics, returns lrcPath', async () => {
    mockBridge(async () => ({ ok: true, status: 200, body: { syncedLyrics: '[00:01.00]hi' } }));
    const r = await fetchAndSaveLyrics({ id: 5, title: 'Sun', artist: 'A' });
    expect(r.saved).toBe(true);
    expect(r.lrcPath).toBe('/x.lrc');
    expect(window.freeplayer.saveLrcContent).toHaveBeenCalledWith(5, '[00:01.00]hi');
  });

  it('save failure yields saved:false', async () => {
    mockBridge(
      async () => ({ ok: true, status: 200, body: { syncedLyrics: '[00:01.00]hi' } }),
      async () => ({ success: false }),
    );
    const r = await fetchAndSaveLyrics({ id: 5, title: 'Sun', artist: 'A' });
    expect(r.saved).toBe(false);
  });

  it('no lyrics found: nothing saved, bridge not called', async () => {
    const saveLrc = vi.fn(async () => ({ success: true }));
    mockBridge(async () => ({ ok: false, status: 404, error: 'miss' }), saveLrc);
    const r = await fetchAndSaveLyrics({ id: 5, title: 'Sun', artist: 'A' });
    expect(r.saved).toBe(false);
    expect(saveLrc).not.toHaveBeenCalled();
  });

  it('no track id: short-circuits', async () => {
    mockBridge(async () => ({ ok: true, status: 200, body: {} }));
    expect(await fetchAndSaveLyrics(null)).toEqual({ saved: false });
    expect(window.freeplayer.httpGetJson).not.toHaveBeenCalled();
  });
});

describe('fetchAndSaveCover', () => {
  it('fetches and saves cover, returns coverPath', async () => {
    mockBridge(async (url) => (String(url).includes('itunes.apple.com')
      ? { ok: true, status: 200, body: { results: [{ trackName: 'Sun', artistName: 'A', artworkUrl100: 'https://img/s100x100bb.jpg' }] } }
      : { ok: false, status: 404, error: 'miss' }));
    const r = await fetchAndSaveCover({ id: 5, title: 'Sun', artist: 'A' });
    expect(r.saved).toBe(true);
    expect(r.coverPath).toBe('/x.jpg');
    expect(window.freeplayer.saveCover).toHaveBeenCalledWith(5, Buffer.from('jpeg').toString('base64'));
  });

  it('save failure yields saved:false', async () => {
    mockBridge(
      async (url) => (String(url).includes('itunes.apple.com')
        ? { ok: true, status: 200, body: { results: [{ trackName: 'Sun', artistName: 'A', artworkUrl100: 'https://img/s100x100bb.jpg' }] } }
        : { ok: false, status: 404, error: 'miss' }),
      undefined,
      async () => ({ success: false }),
    );
    const r = await fetchAndSaveCover({ id: 5, title: 'Sun', artist: 'A' });
    expect(r.saved).toBe(false);
  });

  it('no cover found: saveCover not called', async () => {
    const saveCover = vi.fn(async () => ({ success: true }));
    mockBridge(async () => ({ ok: false, status: 404, error: 'miss' }), undefined, saveCover);
    const r = await fetchAndSaveCover({ id: 5, title: 'Sun', artist: 'A' });
    expect(r.saved).toBe(false);
    expect(saveCover).not.toHaveBeenCalled();
  });

  it('no track id: short-circuits', async () => {
    mockBridge(async () => ({ ok: true, status: 200, body: {} }));
    expect(await fetchAndSaveCover(null)).toEqual({ saved: false });
    expect(window.freeplayer.httpGetJson).not.toHaveBeenCalled();
  });
});
