import { pickBestMatch } from './match.js';

const COOLDOWN_MS = 5000;
let cooldownUntil = 0;
let lastRequestAt = 0;

export function activate(api) {
  return {
    async fetchCover(track) {
      if (Date.now() < cooldownUntil) return null;
      const minInterval = 3000;
      const wait = minInterval - (Date.now() - lastRequestAt);
      if (wait > 0) await new Promise((r) => setTimeout(r, wait));
      lastRequestAt = Date.now();

      const term = [track.title, track.artist && track.artist !== 'Unknown Artist' ? track.artist : ''].filter(Boolean).join(' ');
      const p = new URLSearchParams({ term, media: 'music', entity: 'song', limit: '10' });
      let res = await api.http.getJson(`https://itunes.apple.com/search?${p.toString()}`);
      if (!res) {
        await new Promise((r) => setTimeout(r, 500));
        res = await api.http.getJson(`https://itunes.apple.com/search?${p.toString()}`);
      }
      if (!res) return null;
      if (res.status === 403 || res.status === 429) { cooldownUntil = Date.now() + retryAfter(res); return null; }
      if (!res.ok) return null;
      const results = (res.body.results || []).map((r) => ({
        title: r.trackName, artist: r.artistName, artworkUrl: r.artworkUrl100,
      }));
      const minScore = await api.pluginSettings.get('minMatchScore') ?? 0.8;
      const best = pickBestMatch(results, track, { titleMin: minScore });
      if (!best) return null;
      const large = best.artworkUrl.replace(/\d+x\d+/, '600x600');
      const img = await api.http.getBase64(large);
      if (!img || !img.ok || !img.base64) return null;
      return img.base64;
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
