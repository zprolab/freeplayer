const BASE64_RE = /^[A-Za-z0-9+/]+={0,2}$/;
const METADATA_FIELDS = ['title', 'artist', 'album', 'genre', 'year', 'track_number'];
const DEFAULTS = { lyrics: 'lrclib-lyrics', cover: 'itunes-cover', metadata: 'musicbrainz-meta' };

export function createMetadataRegistry(deps) {
  const { registry, getSetting, saveLyrics, saveCover, updateTrack } = deps;

  function getProviders(kind) {
    return registry.getPlugins()
      .filter((p) => p.status === 'enabled' || p.status === 'active')
      .filter((p) => p.manifest && p.manifest.provides && p.manifest.provides[kind])
      .map((p) => p.id);
  }

  async function backendFor(kind) {
    const key = kind === 'lyrics' ? 'meta.lyricsBackend' : kind === 'metadata' ? 'meta.metadataBackend' : 'meta.coverBackend';
    const saved = await getSetting(key);
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

  async function fetchMetadata(track) {
    const backend = await backendFor('metadata');
    if (!getProviders('metadata').includes(backend)) return { saved: false, reason: 'no-plugin' };
    let result;
    try {
      result = await registry.invokeHook(backend, 'fetchMetadata', track);
    } catch (err) {
      registry.logOp(backend, 'fetchMetadata', track.id, false);
      return { saved: false, reason: 'plugin-error' };
    }
    if (!canWrite(backend)) {
      registry.logOp(backend, 'saveMetadata', track.id, false);
      return { saved: false, reason: 'no-write-permission' };
    }
    const fields = {};
    for (const key of METADATA_FIELDS) {
      const value = result?.[key];
      if (value === undefined || value === null || value === '') continue;
      const numeric = key === 'year' || key === 'track_number';
      const normalized = numeric ? Number(value) : String(value);
      if (numeric && !Number.isInteger(normalized)) continue;
      if (String(normalized) === String(track[key] ?? '')) continue; // unchanged
      fields[key] = normalized;
    }
    if (Object.keys(fields).length === 0) {
      registry.logOp(backend, 'fetchMetadata', track.id, true);
      return { saved: false, reason: 'not-found' };
    }
    registry.logOp(backend, 'fetchMetadata', track.id, true);
    const ok = await updateTrack(track.id, fields);
    registry.logOp(backend, 'saveMetadata', track.id, ok);
    return { saved: !!ok, updated: fields };
  }

  return { getBackend: backendFor, getProviders, fetchLyrics, fetchCover, fetchMetadata };
}
