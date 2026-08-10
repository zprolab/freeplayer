// Batch backfill for missing metadata, scoped to one kind
// ('lyrics' | 'cover' | 'metadata'). Moved out of Settings so plugin details
// can run per-backend backfills. ~1.5s/track keeps the APIs (LRCLIB ~50/min,
// iTunes ~20/min, MusicBrainz rate-limited) under their limits; the services'
// own pacing + 429/403 cooldowns also apply. Tests pass sleepMs: 0.
let backfillRunning = false;

export function isBackfillRunning() {
  return backfillRunning;
}

// Shared missing-metadata predicate: a track needs filling when
// title/artist/album are missing or still the placeholder "Unknown"
// values. Used by the batch backfill (PluginPage) and the auto-fetch
// hook (useAutoMeta) so both judge "missing" identically.
export function needsMetadataFill(t) {
  return !t.title || !t.artist || !t.album
    || t.title === 'Unknown Title' || t.artist === 'Unknown Artist';
}

// kind: 'lyrics' — fetch lyrics only; 'cover' — fetch covers only;
// 'metadata' — fill missing title/artist/album fields.
// fetchForTrack: (track) => meta.fetchLyrics(track) | meta.fetchCover(track)
//   | meta.fetchMetadata(track)
// missingCheck: (track) => Promise<boolean> — true when the item is missing;
//   supplied by the caller (each kind knows its own missing condition).
export async function backfillMissing({
  tracks, kind, fetchForTrack, missingCheck, onProgress, sleepMs = 1500,
}) {
  if (backfillRunning) return;
  const total = tracks?.length || 0;
  if (!total) return;
  backfillRunning = true;
  let ok = 0;
  let fail = 0;
  let noMatch = 0;
  let done = 0;
  onProgress?.({ done: 0, total, ok, fail, noMatch });
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  try {
    for (const t of tracks) {
      let saved = false;
      let threw = false;
      let hadMissing = false;
      try {
        if (await missingCheck(t)) {
          hadMissing = true;
          const res = await fetchForTrack(t);
          if (res && res.saved) { ok++; saved = true; }
        }
      } catch {
        threw = true;
      }
      // noMatch only counts when something WAS missing but nothing got saved
      // (complete tracks must not inflate the bucket)
      if (threw) fail++;
      else if (hadMissing && !saved) noMatch++;
      done++;
      onProgress?.({ done, total, ok, fail, noMatch });
      await sleep(sleepMs);
    }
  } finally {
    backfillRunning = false;
  }
}
