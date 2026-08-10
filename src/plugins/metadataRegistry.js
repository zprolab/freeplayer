const BASE64_RE = /^[A-Za-z0-9+/]+={0,2}$/;
const DEFAULTS = { lyrics: 'lrclib-lyrics', cover: 'itunes-cover' };

export function createMetadataRegistry(deps) {
  const { registry, getSetting, saveLyrics, saveCover } = deps;

  function getProviders(kind) {
    return registry.getPlugins()
      .filter((p) => p.status === 'enabled' || p.status === 'active')
      .filter((p) => p.manifest && p.manifest.provides && p.manifest.provides[kind])
      .map((p) => p.id);
  }

  async function backendFor(kind) {
    const saved = await getSetting(kind === 'lyrics' ? 'meta.lyricsBackend' : 'meta.coverBackend');
    return saved || DEFAULTS[kind];
  }

  function validLyrics(v) {
    return typeof v === 'string' && v.trim().length > 0;
  }

  function validBase64(v) {
    return typeof v === 'string' && v.length > 16 && BASE64_RE.test(v);
  }

  // The host persists hook results on the backend's behalf — that write must
  // be covered by the user-granted metadata:write permission, matching what
  // the permission dialog showed. Backends without the grant cannot save.
  function canWrite(backend) {
    const p = registry.getPlugin(backend);
    return !!(p && Array.isArray(p.perms?.granted) && p.perms.granted.includes('metadata:write'));
  }

  async function fetchLyrics(track) {
    const backend = await backendFor('lyrics');
    if (!getProviders('lyrics').includes(backend)) return { saved: false, reason: 'no-plugin' };
    let content;
    try {
      content = await registry.invokeHook(backend, 'fetchLyrics', track);
    } catch (err) {
      registry.logOp(backend, 'fetchLyrics', track.id, false);
      return { saved: false, reason: 'plugin-error' };
    }
    if (!validLyrics(content)) {
      registry.logOp(backend, 'fetchLyrics', track.id, false);
      return { saved: false, reason: 'not-found' };
    }
    if (!canWrite(backend)) {
      registry.logOp(backend, 'saveLyrics', track.id, false);
      return { saved: false, reason: 'no-write-permission' };
    }
    registry.logOp(backend, 'fetchLyrics', track.id, true);
    const res = await saveLyrics(track.id, content);
    const ok = !(res && res.success === false);
    registry.logOp(backend, 'saveLyrics', track.id, ok);
    return { saved: ok, content };
  }

  async function fetchCover(track) {
    const backend = await backendFor('cover');
    if (!getProviders('cover').includes(backend)) return { saved: false, reason: 'no-plugin' };
    let base64;
    try {
      base64 = await registry.invokeHook(backend, 'fetchCover', track);
    } catch (err) {
      registry.logOp(backend, 'fetchCover', track.id, false);
      return { saved: false, reason: 'plugin-error' };
    }
    if (!validBase64(base64)) {
      registry.logOp(backend, 'fetchCover', track.id, false);
      return { saved: false, reason: 'not-found' };
    }
    if (!canWrite(backend)) {
      registry.logOp(backend, 'saveCover', track.id, false);
      return { saved: false, reason: 'no-write-permission' };
    }
    registry.logOp(backend, 'fetchCover', track.id, true);
    const res = await saveCover(track.id, base64);
    // coverPath passes through the native saveCover result so the caller can
    // refresh the track's stored cover_path (auto-fetch + manual buttons).
    const ok = !(res && res.success === false);
    registry.logOp(backend, 'saveCover', track.id, ok);
    return { saved: ok, coverPath: res && res.coverPath, base64 };
  }

  return { getBackend: backendFor, getProviders, fetchLyrics, fetchCover };
}
