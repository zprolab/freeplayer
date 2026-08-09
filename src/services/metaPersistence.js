import { fetchLyricsForTrack, fetchCoverForTrack } from './metaFetch';

// Fetch + persist for one track. Used by both the explicit Now Playing
// buttons and the auto-fetch hook, so both paths behave identically.
export async function fetchAndSaveLyrics(track) {
  if (!track?.id) return { saved: false };
  const lyrics = await fetchLyricsForTrack(track);
  if (!lyrics) return { saved: false };
  const res = await window.freeplayer.saveLrcContent(track.id, lyrics);
  return { saved: !!(res && res.success), lrcPath: res && res.lrcPath };
}

export async function fetchAndSaveCover(track) {
  if (!track?.id) return { saved: false };
  const cover = await fetchCoverForTrack(track);
  if (!cover) return { saved: false };
  const res = await window.freeplayer.saveCover(track.id, cover);
  return { saved: !!(res && res.success), coverPath: res && res.coverPath };
}
