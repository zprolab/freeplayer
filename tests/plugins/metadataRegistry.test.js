import { describe, it, expect, vi } from 'vitest';
import { createMetadataRegistry } from '../../src/plugins/metadataRegistry';

function makeRegistry(plugins) {
  return {
    getPlugins: () => plugins,
    getPlugin: (id) => plugins.find((p) => p.id === id) || null,
    invokeHook: vi.fn(async () => null),
    logOp: vi.fn(),
  };
}

function plugin(id, provides, granted = ['metadata:write']) {
  return { id, status: 'enabled', perms: { granted }, manifest: { provides } };
}

describe('createMetadataRegistry', () => {
  it('defaults to lrclib-lyrics and itunes-cover backends', () => {
    const reg = createMetadataRegistry({
      registry: makeRegistry([plugin('lrclib-lyrics', { lyrics: true }), plugin('itunes-cover', { cover: true })]),
      getSetting: vi.fn(async () => null),
      saveLyrics: vi.fn(), saveCover: vi.fn(),
    });
    return Promise.all([reg.fetchLyrics({ id: 1, title: 'S' }), reg.fetchCover({ id: 2, title: 'S' })])
      .then(() => {
        expect(reg.getProviders('lyrics')).toEqual(['lrclib-lyrics']);
        expect(reg.getProviders('cover')).toEqual(['itunes-cover']);
      });
  });
  it('uses the configured backend', async () => {
    const getSetting = vi.fn(async (k) => k === 'meta.lyricsBackend' ? 'netease' : 'lrclib-lyrics');
    const registry = makeRegistry([
      plugin('lrclib-lyrics', { lyrics: true }),
      plugin('netease', { lyrics: true }),
    ]);
    const reg = createMetadataRegistry({ registry, getSetting, saveLyrics: vi.fn(), saveCover: vi.fn() });
    registry.invokeHook.mockResolvedValue('lrc-content');
    const res = await reg.fetchLyrics({ id: 5, title: 'Sun' });
    expect(registry.invokeHook).toHaveBeenCalledWith('netease', 'fetchLyrics', { id: 5, title: 'Sun' });
    expect(res).toEqual({ saved: true, content: 'lrc-content' });
  });
  it('refuses to save when the backend lacks the metadata:write grant', async () => {
    const registry = makeRegistry([
      plugin('lrclib-lyrics', { lyrics: true }, ['http']),
    ]);
    const saveLyrics = vi.fn();
    const reg = createMetadataRegistry({ registry, getSetting: vi.fn(async () => null), saveLyrics, saveCover: vi.fn() });
    registry.invokeHook.mockResolvedValue('[00:01.00]hi');
    const res = await reg.fetchLyrics({ id: 5, title: 'Sun' });
    expect(res).toEqual({ saved: false, reason: 'no-write-permission' });
    expect(saveLyrics).not.toHaveBeenCalled();
  });
  it('does not save when the backend is not an enabled provider', async () => {
    const reg = createMetadataRegistry({
      registry: makeRegistry([plugin('lrclib-lyrics', { lyrics: true })]),
      getSetting: vi.fn(async () => 'some-other-plugin'),
      saveLyrics: vi.fn(), saveCover: vi.fn(),
    });
    expect(await reg.fetchLyrics({ id: 1, title: 'S' })).toEqual({ saved: false, reason: 'no-plugin' });
  });
  it('reports no-plugin when the cover backend is not an enabled provider', async () => {
    const reg = createMetadataRegistry({
      registry: makeRegistry([plugin('lrclib-lyrics', { lyrics: true })]),
      getSetting: vi.fn(async () => 'some-other-plugin'),
      saveLyrics: vi.fn(), saveCover: vi.fn(),
    });
    expect(await reg.fetchCover({ id: 1, title: 'S' })).toEqual({ saved: false, reason: 'no-plugin' });
  });
  it('rejects empty or non-string lyrics', async () => {
    const registry = makeRegistry([plugin('lrclib-lyrics', { lyrics: true })]);
    const saveLyrics = vi.fn();
    const reg = createMetadataRegistry({ registry, getSetting: vi.fn(async () => null), saveLyrics, saveCover: vi.fn() });
    for (const bad of [null, '', '   ', 42]) {
      registry.invokeHook.mockResolvedValue(bad);
      const res = await reg.fetchLyrics({ id: 1, title: 'S' });
      expect(res).toEqual({ saved: false, reason: 'not-found' });
      expect(saveLyrics).not.toHaveBeenCalled();
    }
  });
  it('rejects invalid base64 covers', async () => {
    const registry = makeRegistry([plugin('itunes-cover', { cover: true })]);
    const reg = createMetadataRegistry({ registry, getSetting: vi.fn(async () => null), saveLyrics: vi.fn(), saveCover: vi.fn() });
    registry.invokeHook.mockResolvedValue('not-base64!!!');
    expect(await reg.fetchCover({ id: 1, title: 'S' })).toEqual({ saved: false, reason: 'not-found' });
  });
  it('persists through saveLyrics/saveCover and returns saved', async () => {
    const registry = makeRegistry([plugin('lrclib-lyrics', { lyrics: true })]);
    const saveLyrics = vi.fn(async () => ({ success: true }));
    const reg = createMetadataRegistry({ registry, getSetting: vi.fn(async () => null), saveLyrics, saveCover: vi.fn() });
    registry.invokeHook.mockResolvedValue('[00:01.00]hi');
    const res = await reg.fetchLyrics({ id: 7, title: 'S' });
    expect(saveLyrics).toHaveBeenCalledWith(7, '[00:01.00]hi');
    expect(res.saved).toBe(true);
  });
  it('audits fetchLyrics validity and saveLyrics result', async () => {
    const registry = makeRegistry([plugin('lrclib-lyrics', { lyrics: true })]);
    const saveLyrics = vi.fn(async () => ({ success: true }));
    const reg = createMetadataRegistry({ registry, getSetting: vi.fn(async () => null), saveLyrics, saveCover: vi.fn() });
    registry.invokeHook.mockResolvedValue('[00:01.00]hi');
    await reg.fetchLyrics({ id: 7, title: 'S' });
    expect(registry.logOp).toHaveBeenCalledWith('lrclib-lyrics', 'fetchLyrics', 7, true);
    expect(registry.logOp).toHaveBeenCalledWith('lrclib-lyrics', 'saveLyrics', 7, true);
  });
  it('audits an invalid fetch as failed without saving', async () => {
    const registry = makeRegistry([plugin('lrclib-lyrics', { lyrics: true })]);
    const saveLyrics = vi.fn();
    const reg = createMetadataRegistry({ registry, getSetting: vi.fn(async () => null), saveLyrics, saveCover: vi.fn() });
    registry.invokeHook.mockResolvedValue(null);
    expect(await reg.fetchLyrics({ id: 7, title: 'S' })).toEqual({ saved: false, reason: 'not-found' });
    expect(registry.logOp).toHaveBeenCalledWith('lrclib-lyrics', 'fetchLyrics', 7, false);
    expect(saveLyrics).not.toHaveBeenCalled();
  });
  it('reports plugin-error when invokeHook rejects', async () => {
    const registry = makeRegistry([plugin('lrclib-lyrics', { lyrics: true }), plugin('itunes-cover', { cover: true })]);
    const reg = createMetadataRegistry({ registry, getSetting: vi.fn(async () => null), saveLyrics: vi.fn(), saveCover: vi.fn() });
    registry.invokeHook.mockRejectedValue(new Error('timeout'));
    expect(await reg.fetchLyrics({ id: 7, title: 'S' })).toEqual({ saved: false, reason: 'plugin-error' });
    expect(await reg.fetchCover({ id: 7, title: 'S' })).toEqual({ saved: false, reason: 'plugin-error' });
    expect(registry.logOp).toHaveBeenCalledWith('lrclib-lyrics', 'fetchLyrics', 7, false);
    expect(registry.logOp).toHaveBeenCalledWith('itunes-cover', 'fetchCover', 7, false);
  });
  it('audits a failed save as failed', async () => {
    const registry = makeRegistry([plugin('lrclib-lyrics', { lyrics: true })]);
    const saveLyrics = vi.fn(async () => ({ success: false }));
    const reg = createMetadataRegistry({ registry, getSetting: vi.fn(async () => null), saveLyrics, saveCover: vi.fn() });
    registry.invokeHook.mockResolvedValue('[00:01.00]hi');
    expect(await reg.fetchLyrics({ id: 7, title: 'S' })).toEqual({ saved: false, content: '[00:01.00]hi' });
    expect(registry.logOp).toHaveBeenCalledWith('lrclib-lyrics', 'saveLyrics', 7, false);
  });
  it('audits cover fetch and save with the cover backend id', async () => {
    const registry = makeRegistry([plugin('itunes-cover', { cover: true })]);
    const saveCover = vi.fn(async () => ({ success: true, coverPath: '/x.jpg' }));
    const reg = createMetadataRegistry({ registry, getSetting: vi.fn(async () => null), saveLyrics: vi.fn(), saveCover });
    registry.invokeHook.mockResolvedValue('aGVsbG8gd29ybGQgd29ybGQ=');
    const res = await reg.fetchCover({ id: 3, title: 'S' });
    expect(res.saved).toBe(true);
    expect(registry.logOp).toHaveBeenCalledWith('itunes-cover', 'fetchCover', 3, true);
    expect(registry.logOp).toHaveBeenCalledWith('itunes-cover', 'saveCover', 3, true);
  });
});
