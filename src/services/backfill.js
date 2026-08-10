// Batch backfill for missing metadata, scoped to one kind ('lyrics' | 'cover').
// Moved out of Settings so plugin details can run per-backend backfills.
// ~1.5s/track keeps both APIs (LRCLIB ~50/min, iTunes ~20/min) under their
// rate limits; the services' own pacing + 429/403 cooldowns also apply.
let backfillRunning = false;

export function isBackfillRunning() {
  return backfillRunning;
}

// kind: 'lyrics' — fetch lyrics only; 'cover' — fetch covers only.
// fetchForTrack: (track) => meta.fetchLyrics(track) | meta.fetchCover(track)
// missingCheck: (track) => Promise<boolean> — true when the item is missing.
export async function backfillMissing({ tracks, kind, fetchForTrack, missingCheck, onProgress }) {
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
      await sleep(1500);
    }
  } finally {
    backfillRunning = false;
  }
}
