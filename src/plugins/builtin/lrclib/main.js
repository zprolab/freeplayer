import { normalizeForMatch, similarity, pickBestMatch } from './match.js';

const COOLDOWN_MS = 5000;
let cooldownUntil = 0;
let lastRequestAt = 0;

async function pace(minInterval) {
  const wait = minInterval - (Date.now() - lastRequestAt);
  if (wait > 0) await new Promise((r) => setTimeout(r, wait));
  lastRequestAt = Date.now();
}

// Cooldown is checked before EVERY request in a batch (the /api/get call and
// the search fallback), not only the first — a 429 on the first request of a
// batch must suppress the rest.
async function getJson(api, url, minInterval) {
  if (Date.now() < cooldownUntil) return null;
  await pace(minInterval);
  const res = await api.http.getJson(url);
  if (res && res.status === 429) {
    cooldownUntil = Date.now() + retryAfter(res);
    return null;
  }
  return res;
}

export function activate(api) {
  return {
    async fetchLyrics(track) {
      if (Date.now() < cooldownUntil) return null;
      const minInterval = await api.pluginSettings.get('requestIntervalMs') ?? 1200;

      const artistKnown = track.artist && track.artist !== 'Unknown Artist';
      if (artistKnown) {
        const params = new URLSearchParams();
        params.set('artist_name', track.artist);
        if (track.title) params.set('track_name', track.title);
        if (track.album && track.album !== 'Unknown Album') params.set('album_name', track.album);
        if (track.duration) params.set('duration', String(Math.round(track.duration)));
        const res = await getJson(api, `https://lrclib.net/api/get?${params.toString()}`, minInterval);
        if (!res) return null;
        if (res.ok && res.body && typeof res.body.syncedLyrics === 'string' && res.body.syncedLyrics.trim()) {
          return res.body.syncedLyrics;
        }
      }
      const q = [track.title, artistKnown ? track.artist : ''].filter(Boolean).join(' ');
      const searchRes = await getJson(api, `https://lrclib.net/api/search?q=${encodeURIComponent(q)}`, minInterval);
      if (!searchRes) return null;
      if (!searchRes.ok || !Array.isArray(searchRes.body) || !searchRes.body.length) return null;
      const minScore = await api.pluginSettings.get('minMatchScore') ?? 0.8;
      const best = pickBestMatch(
        searchRes.body.map((c) => ({ title: c.track_name, artist: c.artist_name, raw: c })),
        track,
        { titleMin: minScore }
      );
      if (!best) return null;
      const lrc = best.raw.syncedLyrics;
      return lrc && lrc.trim() ? lrc : null;
    },
  };
}

// Retry-After is an attacker-controlled header: clamp to a sane window so a
// malicious response cannot set the cooldown years into the future (or a
// negative value that disables throttling entirely).
function retryAfter(res) {
  const secs = res && res.retryAfter ? parseInt(res.retryAfter, 10) : NaN;
  if (!Number.isFinite(secs)) return COOLDOWN_MS / 1000 * 1000;
  return Math.min(Math.max(secs, 1), 3600) * 1000;
}
