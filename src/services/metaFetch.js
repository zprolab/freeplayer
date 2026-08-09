// Auto-fetch of lyrics (LRCLIB) and cover art (iTunes Search API).
// Both sources send Access-Control-Allow-Origin: *, so plain fetch()
// works from the WKWebView renderer.
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
  const ra = res && res.headers ? res.headers.get('retry-after') : null;
  const secs = ra ? parseInt(ra, 10) : NaN;
  return (Number.isFinite(secs) ? secs : COOLDOWN_MS / 1000) * 1000;
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
    const getRes = await fetch(buildLrclibGetUrl(track));
    if (getRes.status === 429) {
      lrclibCooldownUntil = Date.now() + retryAfterMs(getRes);
      return null;
    }
    if (getRes.ok) {
      const lrc = lrclibResponseToLrc(await getRes.json());
      if (lrc) return lrc;
    }
  }
  const q = [track.title, artistKnown ? track.artist : ''].filter(Boolean).join(' ');
  await pace('lrclib');
  const searchRes = await fetch(`https://lrclib.net/api/search?q=${encodeURIComponent(q)}`);
  if (searchRes.status === 429) {
    lrclibCooldownUntil = Date.now() + retryAfterMs(searchRes);
    return null;
  }
  if (!searchRes.ok) return null;
  const list = await searchRes.json();
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
  // an occasional node omits CORS headers — a rejected fetch must not
  // silently kill the cover for the whole session.
  let res = await fetch(buildItunesUrl(track)).catch(() => null);
  if (!res) {
    await new Promise((r) => setTimeout(r, rateConfig.retryDelayMs));
    res = await fetch(buildItunesUrl(track)).catch(() => null);
  }
  if (!res) return null;
  // 403 = region throttle, 429 = rate limit (iTunes returns 403 when hit)
  if (res.status === 403 || res.status === 429) {
    itunesCooldownUntil = Date.now() + retryAfterMs(res);
    return null;
  }
  if (!res.ok) return null;
  const body = await res.json();
  const results = (body.results || []).map((r) => ({
    title: r.trackName, artist: r.artistName, artworkUrl: r.artworkUrl100,
  }));
  const best = pickBestMatch(results, track);
  if (!best) return null;
  const img = await fetch(itunesArtworkLarge(best.artworkUrl)).catch(() => null);
  if (!img || !img.ok) return null;
  const buf = new Uint8Array(await img.arrayBuffer());
  let bin = '';
  for (let i = 0; i < buf.length; i++) bin += String.fromCharCode(buf[i]);
  return btoa(bin);
}
