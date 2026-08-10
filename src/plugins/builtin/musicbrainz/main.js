import { pickBestMatch } from './match.js';

const COOLDOWN_MS = 5000;
const PACING_MS = 1000; // MusicBrainz hard limit: 1 req/s
const INC_PARAMS = 'inc=releases+release-groups+artist-credits';
let cooldownUntil = 0;
let lastRequestAt = 0;
const mbidCache = new Map();

export function activate(api) {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  async function pace() {
    if (Date.now() < cooldownUntil) throw new Error('cooldown');
    const wait = PACING_MS - (Date.now() - lastRequestAt);
    if (wait > 0) await sleep(wait);
    lastRequestAt = Date.now();
  }

  async function getJson(url) {
    // token via header needs api.http support; the bridge httpGetJson has no
    // headers param, so the token is appended as a query param when set (MB
    // accepts ?access_token= for OAuth access tokens) — otherwise the official
    // endpoint needs no auth. Self-hosted Basic-auth setups are out of scope
    // for v1 (see manifest notice).
    const token = await api.pluginSettings.get('apiToken');
    const sep = url.includes('?') ? '&' : '?';
    const full = token ? `${url}${sep}access_token=${encodeURIComponent(token)}` : url;
    return api.http.getJson(full);
  }

  async function searchRecording(track) {
    await pace();
    const artist = track.artist && track.artist !== 'Unknown Artist' ? track.artist : null;
    const query = artist
      ? `recording:${track.title} AND artist:${artist}`
      : `recording:${track.title}`;
    const endpoint = (await api.pluginSettings.get('apiEndpoint')) || 'https://musicbrainz.org/ws/2';
    const base = `${endpoint}/recording?query=${encodeURIComponent(query)}&fmt=json&limit=10`;
    let res = await getJson(`${base}&${INC_PARAMS}`);
    // inc requires a specific MB WS version; older instances may 400 on it —
    // degrade to a plain search (no release-group data) once.
    if (res && res.status === 400) res = await getJson(base);
    if (res && res.status === 429) { cooldownUntil = Date.now() + COOLDOWN_MS; throw new Error('rate limited'); }
    if (!res || !res.ok || !res.body || !Array.isArray(res.body.recordings)) return null;
    const minScore = (await api.pluginSettings.get('minMatchScore')) ?? 0.8;
    const candidates = res.body.recordings.map((r) => ({
      title: r.title, artist: (r['artist-credit'] || []).map((c) => c.name).join(' '),
      raw: r,
    }));
    return pickBestMatch(candidates, track, { titleMin: minScore })?.raw || null;
  }

  function coverFrom(body) {
    if (!body) return null;
    const images = body.images || [];
    const front = images.find((i) => i.front) || images[0];
    if (!front || !front.thumbnails?.['500']) return null;
    return front.thumbnails['500'];
  }

  return {
    async fetchMetadata(track) {
      try {
        const rec = await searchRecording(track);
        if (!rec) return null;
        if (track.id != null) {
          mbidCache.set(track.id, { recId: rec.id, rgId: rec.releases?.[0]?.['release-group']?.id });
        }
        const fields = { title: rec.title };
        const artistCredit = rec['artist-credit'] || [];
        if (artistCredit.length) fields.artist = artistCredit.map((c) => c.name).join('');
        const rg = rec.releases?.[0]?.['release-group'];
        if (rg) {
          if (rg['first-release-date']) {
            const y = parseInt(rg['first-release-date'].slice(0, 4), 10);
            if (Number.isInteger(y)) fields.year = y;
          }
          const tags = rg.tags || [];
          if (tags.length) fields.genre = [...tags].sort((a, b) => b.count - a.count)[0].name;
        }
        if (rec.releases?.[0]?.title) fields.album = rec.releases[0].title;
        if (rec.releases?.[0]?.media?.[0]?.track) {
          const t = rec.releases[0].media[0].track.find((x) => x.id === rec.id)
            || rec.releases[0].media[0].track[0];
          if (t && t.number) fields.track_number = String(t.number);
        }
        return fields;
      } catch {
        return null;
      }
    },

    async fetchCover(track) {
      try {
        const cached = track.id != null ? mbidCache.get(track.id) : null;
        let rgId = cached?.rgId;
        let recId = cached?.recId;
        let rec = null;
        if (!rgId) {
          rec = await searchRecording(track);
          if (!rec || !rec.id) return null;
          recId = rec.id;
          rgId = rec.releases?.[0]?.['release-group']?.id;
        }
        if (rgId) {
          // Cover Art Archive needs no auth — bypass getJson so the user's
          // access_token never leaks to a third-party host.
          const res = await api.http.getJson(`https://coverartarchive.org/release-group/${rgId}`);
          const thumb = coverFrom(res?.body);
          if (thumb) {
            await pace();
            const img = await api.http.getBase64(thumb);
            if (img && img.ok && img.base64) return img.base64;
          }
        }
        // fallback: release-level art
        if (recId) {
          const res = await api.http.getJson(`https://coverartarchive.org/release/${recId}`);
          const thumb = coverFrom(res?.body);
          if (thumb) {
            await pace();
            const img = await api.http.getBase64(thumb);
            if (img && img.ok && img.base64) return img.base64;
          }
        }
        return null;
      } catch {
        return null;
      }
    },
  };
}

export default { activate };
