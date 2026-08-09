// Auto-fetch of lyrics (LRCLIB) and cover art (iTunes Search API).
// ALL network requests go through the native bridge (window.freeplayer.
// httpGetJson / httpGetBase64, NSURLSession with a 10s timeout): the native
// stack has no CORS constraints (Chinese iTunes CDN edges omit
// Access-Control-Allow-Origin) and is more reliable than the WKWebView
// network process on unstable links.
//
// Rate limits (LRCLIB ~50 req/min/IP, iTunes ~20 req/min/IP): on 429/403
// we set a short module-level cooldown and return null — later calls short-
// circuit without touching the network. A min-interval paces back-to-back
// requests (rapid track skipping, batch + playback concurrency) so the
// burst never trips the limit in the first place. Tests can zero the
// intervals and reset the state via resetRateLimitState().

const COOLDOWN_MS = 5000;
let lrclibCooldownUntil = 0;
let itunesCooldownUntil = 0;
let lastLrclibAt = 0;
let lastItunesAt = 0;

export const rateConfig = {
  lrclibMinInterval: 1200,   // ~50/min
  itunesMinInterval: 3000,   // ~20/min
  retryDelayMs: 500,
};

async function pace(key) {
  const min = key === 'lrclib' ? rateConfig.lrclibMinInterval : rateConfig.itunesMinInterval;
  const last = key === 'lrclib' ? lastLrclibAt : lastItunesAt;
  const wait = min - (Date.now() - last);
  if (wait > 0) await new Promise((r) => setTimeout(r, wait));
  if (key === 'lrclib') lastLrclibAt = Date.now();
  else lastItunesAt = Date.now();
}

export function resetRateLimitState() {
  lrclibCooldownUntil = 0;
  itunesCooldownUntil = 0;
  lastLrclibAt = 0;
  lastItunesAt = 0;
}

function retryAfterMs(res) {
  const secs = res && res.retryAfter ? parseInt(res.retryAfter, 10) : NaN;
  return (Number.isFinite(secs) ? secs : COOLDOWN_MS / 1000) * 1000;
}

// Native JSON GET → { ok, status, body } | { ok: false, status?, retryAfter?, error? }
// Resolves null when the bridge is unavailable (e.g. plain-browser preview).
async function httpGetJson(url) {
  try {
    return await window.freeplayer.httpGetJson(url);
  } catch {
    return null;
  }
}

export function normalizeForMatch(s) {
  return (s || '')
    .toLowerCase()
    .replace(/[^a-z0-9\u4e00-\u9fff]+/g, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

export function similarity(a, b) {
  const na = normalizeForMatch(a);
  const nb = normalizeForMatch(b);
  if (!na || !nb) return 0;
  if (na === nb) return 1;
  if (na.includes(nb) || nb.includes(na)) return 0.9;
  const ta = na.split(' ');
  const tb = nb.split(' ');
  const common = ta.filter((w) => tb.includes(w)).length;
  return common / Math.max(ta.length, tb.length);
}

export function buildLrclibGetUrl(track) {
  const p = new URLSearchParams();
  if (track.artist && track.artist !== 'Unknown Artist') p.set('artist_name', track.artist);
  if (track.title) p.set('track_name', track.title);
  if (track.album && track.album !== 'Unknown Album') p.set('album_name', track.album);
  if (track.duration) p.set('duration', String(Math.round(track.duration)));
  return `https://lrclib.net/api/get?${p.toString()}`;
}

export function lrclibResponseToLrc(body) {
  if (!body) return null;
  const synced = body.syncedLyrics;
  return synced && synced.trim() ? synced : null;
}

export function pickBestMatch(candidates, track, opts = {}) {
  const titleKey = opts.titleKey || 'title';
  const artistKey = opts.artistKey || 'artist';
  const titleMin = opts.titleMin ?? 0.8;
  const artistMin = opts.artistMin ?? 0.5;
  const artistUnknown = !track.artist || track.artist === 'Unknown Artist';
  let best = null;
  let bestScore = 0;
  for (const c of candidates) {
    const titleSim = similarity(c[titleKey], track.title);
    if (titleSim < titleMin) continue;
    const artistSim = artistUnknown ? 1 : similarity(c[artistKey], track.artist);
    if (!artistUnknown && artistSim < artistMin) continue;
    const score = titleSim * 0.7 + artistSim * 0.3;
    if (score > bestScore) { bestScore = score; best = c; }
  }
  return best;
}

export async function fetchLyricsForTrack(track) {
  if (Date.now() < lrclibCooldownUntil) return null;
  // LRCLIB's /api/get REQUIRES artist_name (400 without it) — go straight
  // to /api/search for unknown-artist tracks instead of burning a request.
  const artistKnown = track.artist && track.artist !== 'Unknown Artist';
  if (artistKnown) {
    await pace('lrclib');
    const getRes = await httpGetJson(buildLrclibGetUrl(track));
    if (getRes && getRes.status === 429) {
      lrclibCooldownUntil = Date.now() + retryAfterMs(getRes);
      return null;
    }
    if (getRes && getRes.ok) {
      const lrc = lrclibResponseToLrc(getRes.body);
      if (lrc) return lrc;
    }
  }
  const q = [track.title, artistKnown ? track.artist : ''].filter(Boolean).join(' ');
  await pace('lrclib');
  const searchRes = await httpGetJson(`https://lrclib.net/api/search?q=${encodeURIComponent(q)}`);
  if (searchRes && searchRes.status === 429) {
    lrclibCooldownUntil = Date.now() + retryAfterMs(searchRes);
    return null;
  }
  if (!searchRes || !searchRes.ok) return null;
  const list = searchRes.body;
  if (!Array.isArray(list) || !list.length) return null;
  const normalized = list.map((c) => ({
    title: c.track_name, artist: c.artist_name, raw: c,
  }));
  const best = pickBestMatch(normalized, track);
  return best ? lrclibResponseToLrc(best.raw) : null;
}

export function buildItunesUrl(track) {
  const term = [track.title, track.artist && track.artist !== 'Unknown Artist' ? track.artist : '']
    .filter(Boolean).join(' ');
  const p = new URLSearchParams({ term, media: 'music', entity: 'song', limit: '10' });
  return `https://itunes.apple.com/search?${p.toString()}`;
}

export function itunesArtworkLarge(url) {
  return url.replace(/\d+x\d+/, '600x600');
}

export async function fetchCoverForTrack(track) {
  if (Date.now() < itunesCooldownUntil) return null;
  await pace('itunes');
  // One-shot retry: iTunes' search API is served from many edge nodes and
  // is intermittently unreachable — a failed native request must not
  // silently kill the cover for the whole session.
  let res = await httpGetJson(buildItunesUrl(track));
  if (!res) {
    await new Promise((r) => setTimeout(r, rateConfig.retryDelayMs));
    res = await httpGetJson(buildItunesUrl(track));
  }
  if (!res) return null;
  // 403 = region throttle, 429 = rate limit (iTunes returns 403 when hit)
  if (res.status === 403 || res.status === 429) {
    itunesCooldownUntil = Date.now() + retryAfterMs(res);
    return null;
  }
  if (!res.ok) return null;
  const body = res.body || {};
  const results = (body.results || []).map((r) => ({
    title: r.trackName, artist: r.artistName, artworkUrl: r.artworkUrl100,
  }));
  const best = pickBestMatch(results, track);
  if (!best) return null;
  // Artwork download also goes through the native stack (mzstatic is CORS-
  // open, but the WKWebView network process is the same unstable path we
  // route around everywhere else). Native timeout covers hung downloads.
  const img = await httpGetBase64(itunesArtworkLarge(best.artworkUrl));
  if (!img || !img.ok || !img.base64) return null;
  return img.base64;
}

// Native binary GET → { ok, status, base64 } | { ok: false, error? }
// Resolves null when the bridge is unavailable (e.g. plain-browser preview).
async function httpGetBase64(url) {
  try {
    return await window.freeplayer.httpGetBase64(url);
  } catch {
    return null;
  }
}
