// Thin persistence facade: fetch + persist for one track. Delegates to the
// plugin metadata registry (meta = { fetchLyrics, fetchCover }) injected by
// the caller — used by the explicit Now Playing buttons, the Settings batch
// backfill and the auto-fetch hook, so all paths behave identically. Without
// a meta object (plugin runtime not ready) they no-op with { saved: false }.
export async function fetchAndSaveLyrics(track, meta) {
  if (!track?.id) return { saved: false };
  return meta ? meta.fetchLyrics(track) : { saved: false };
}

export async function fetchAndSaveCover(track, meta) {
  if (!track?.id) return { saved: false };
  return meta ? meta.fetchCover(track) : { saved: false };
}
