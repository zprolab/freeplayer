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
