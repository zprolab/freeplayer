// Batch backfill for missing metadata, scoped to one kind
// ('lyrics' | 'cover' | 'metadata'). Moved out of Settings so plugin details
// can run per-backend backfills. ~1.5s/track keeps the APIs (LRCLIB ~50/min,
// iTunes ~20/min, MusicBrainz rate-limited) under their limits; the services'
// own pacing + 429/403 cooldowns also apply. Tests pass sleepMs: 0.

// Per-kind locks: a backfill of one kind no longer blocks a different kind,
// and a second backfill of the same kind no longer silently no-ops with zero
// feedback — the caller can pass an AbortSignal (or call cancelBackfill) to
// stop it, and the resolved result reports what happened.
const runningKinds = new Map(); // kind -> AbortController

// Backward-compatible: no argument → any kind running (PluginPage uses this
// to disable its buttons); a kind → only that kind.
export function isBackfillRunning(kind) {
  if (kind) return runningKinds.has(kind);
  return runningKinds.size > 0;
}

// Cancel an in-flight backfill of one kind (also clears a stale lock left by
// a failed run). No-op when nothing is running.
export function cancelBackfill(kind) {
  const controller = runningKinds.get(kind);
  if (controller) controller.abort();
  runningKinds.delete(kind);
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
// force: true — refetch every track, ignoring missingCheck (overwrites
//   existing data); the caller is expected to confirm before passing it.
// signal: optional AbortSignal — aborting stops the loop after the current
//   track; the result reports cancelled: true.
// Resolves with { ok, fail, noMatch, cancelled } so callers can surface
// per-bucket results; existing callers that ignore the return keep working.
export async function backfillMissing({
  tracks, kind, fetchForTrack, missingCheck, onProgress, sleepMs = 1500, force = false, signal,
}) {
  if (runningKinds.has(kind)) return;
  const total = tracks?.length || 0;
  if (!total) return;
  if (signal && signal.aborted) return;

  const controller = new AbortController();
  let cancelled = false;
  const onAbort = () => { cancelled = true; };
  controller.signal.addEventListener('abort', onAbort);
  if (signal) signal.addEventListener('abort', onAbort);
  runningKinds.set(kind, controller);

  let ok = 0;
  let fail = 0;
  let noMatch = 0;
  let done = 0;
  onProgress?.({ done: 0, total, ok, fail, noMatch });
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  try {
    for (const t of tracks) {
      if (cancelled) break;
      let saved = false;
      let threw = false;
      let hadMissing = force;
      try {
        if (force || (await missingCheck(t))) {
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
    runningKinds.delete(kind);
    controller.signal.removeEventListener('abort', onAbort);
    if (signal) signal.removeEventListener('abort', onAbort);
  }
  return { ok, fail, noMatch, cancelled };
}
