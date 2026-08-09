import { useEffect, useRef } from 'react';
import { fetchLyricsForTrack, fetchCoverForTrack } from '../services/metaFetch';

// One fetch attempt per track per app session; failures stay quiet.
// Dispatch guards:
//  - currentIdRef: a slow fetch from a previous track can never clobber
//    state.currentTrack after the user switched tracks.
//  - enabledRef: toggling the setting off mid-flight cancels the refresh.
//  - "changed" check: no pointless re-render / re-fetch when nothing was
//    actually saved.
export function useAutoMeta(currentTrack, enabled, dispatch) {
  const attempted = useRef(new Set());
  const currentIdRef = useRef(currentTrack?.id ?? null);
  const enabledRef = useRef(enabled);
  currentIdRef.current = currentTrack?.id ?? null;
  enabledRef.current = enabled;

  useEffect(() => {
    if (!enabled) return;
    if (!currentTrack?.id || !currentTrack?.title) return;
    if (attempted.current.has(currentTrack.id)) return;
    attempted.current.add(currentTrack.id);

    const track = currentTrack;
    (async () => {
      try {
        let coverPath = track.cover_path;
        let lyricsSaved = false;
        // cover_path set but file deleted (getCover -> null) still counts
        // as missing, per the "only fetch when missing" rule.
        const coverMissing = !track.cover_path
          || !(await window.freeplayer.getCover(track.cover_path).catch(() => null));
        if (coverMissing) {
          const cover = await fetchCoverForTrack(track);
          if (cover) {
            const res = await window.freeplayer.saveCover(track.id, cover);
            if (res && res.success) coverPath = res.coverPath;
          }
        }
        const lrc = await window.freeplayer.getLrc(track.id);
        if (!lrc || !lrc.content) {
          const lyrics = await fetchLyricsForTrack(track);
          if (lyrics) {
            await window.freeplayer.saveLrcContent(track.id, lyrics);
            lyricsSaved = true;
          }
        }
        const changed = coverPath !== track.cover_path || lyricsSaved;
        if (changed && enabledRef.current && currentIdRef.current === track.id) {
          // Fresh object identity re-triggers NowPlaying's getLrc/cover
          // effects; cover_path merged so the fetched art actually shows.
          dispatch({ type: 'SET_CURRENT_TRACK', payload: { ...track, cover_path: coverPath } });
        }
      } catch (err) {
        console.warn('Auto meta fetch failed:', err.message || err);
      }
    })();
  }, [currentTrack, enabled, dispatch]);
}
