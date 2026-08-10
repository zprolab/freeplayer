import { useEffect, useRef, useState } from 'react';

// One fetch attempt per track per app session; failures stay quiet.
// meta = { fetchLyrics, fetchCover, fetchMetadata, getBackend } from the
// plugin metadata registry. Auto-fetch is controlled per backend by the
// `plugin.<backend>.autoFetch` setting (default off); lyrics, covers and
// metadata are independent — each only runs when its own backend switch is
// on. Metadata auto-fetch only runs for tracks with unknown/missing
// title/artist/album, and dispatches SET_CURRENT_TRACK with the fetched
// fields so lists refresh.
// Dispatch guards:
//  - currentIdRef: a slow fetch from a previous track can never clobber
//    state.currentTrack after the user switched tracks.
//  - "changed" check: no pointless re-render / re-fetch when nothing was
//    actually saved.

function autoSettingOn(value) {
  const s = String(value ?? '').toLowerCase();
  return s === '1' || s === '1.0' || s === 'true' || s === 'yes' || s === 'on';
}

export function useAutoMeta(currentTrack, meta, dispatch) {
  const attempted = useRef(new Set());
  const currentIdRef = useRef(currentTrack?.id ?? null);
  const [auto, setAuto] = useState({ lyrics: false, cover: false, metadata: false });
  currentIdRef.current = currentTrack?.id ?? null;

  // Resolve per-backend auto-fetch switches; re-runs when the plugin runtime
  // (meta) appears so toggling a switch in the Plugins page takes effect on
  // the current track without a track change.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (!meta) return;
      const [lyricsBackend, coverBackend, metadataBackend] = await Promise.all([
        meta.getBackend('lyrics'),
        meta.getBackend('cover'),
        meta.getBackend('metadata'),
      ]);
      const [lyricsOn, coverOn, metadataOn] = await Promise.all([
        lyricsBackend
          ? window.freeplayer.getSetting(`plugin.${lyricsBackend}.autoFetch`).then(autoSettingOn).catch(() => false)
          : Promise.resolve(false),
        coverBackend
          ? window.freeplayer.getSetting(`plugin.${coverBackend}.autoFetch`).then(autoSettingOn).catch(() => false)
          : Promise.resolve(false),
        metadataBackend
          ? window.freeplayer.getSetting(`plugin.${metadataBackend}.autoFetch`).then(autoSettingOn).catch(() => false)
          : Promise.resolve(false),
      ]);
      if (!cancelled) setAuto({ lyrics: lyricsOn, cover: coverOn, metadata: metadataOn });
    })();
    return () => { cancelled = true; };
  }, [meta]);

  useEffect(() => {
    if (!meta) return;
    if (!currentTrack?.id) return;
    if (!auto.lyrics && !auto.cover && !auto.metadata) return;
    if (attempted.current.has(currentTrack.id)) return;
    attempted.current.add(currentTrack.id);

    const track = currentTrack;
    (async () => {
      try {
        let out = track;
        let coverPath = track.cover_path;
        let lyricsSaved = false;
        let metaSaved = false;
        if (auto.cover) {
          // cover_path set but file deleted (getCover -> null) still counts
          // as missing, per the "only fetch when missing" rule.
          const coverMissing = !track.cover_path
            || !(await window.freeplayer.getCover(track.cover_path).catch(() => null));
          if (coverMissing) {
            const { saved, coverPath: newCoverPath } = await meta.fetchCover(track);
            if (saved && newCoverPath) coverPath = newCoverPath;
          }
        }
        if (auto.lyrics) {
          const lrc = await window.freeplayer.getLrc(track.id);
          if (!lrc || !lrc.content) {
            const { saved } = await meta.fetchLyrics(track);
            if (saved) lyricsSaved = true;
          }
        }
        if (auto.metadata) {
          const needsMeta = track.title === 'Unknown Title'
            || track.artist === 'Unknown Artist'
            || !track.title
            || !track.artist
            || !track.album;
          if (needsMeta) {
            const { saved, updated } = await meta.fetchMetadata(track);
            // Merge fetched fields into out so a later cover/lyrics dispatch
            // can never clobber them (reducer replaces the whole track).
            if (saved && updated) {
              out = { ...out, ...updated };
              metaSaved = true;
            }
          }
        }
        const changed = coverPath !== track.cover_path || lyricsSaved || metaSaved;
        if (changed && currentIdRef.current === track.id) {
          // Fresh object identity re-triggers NowPlaying's getLrc/cover
          // effects; cover_path merged so the fetched art actually shows.
          dispatch({ type: 'SET_CURRENT_TRACK', payload: { ...out, cover_path: coverPath } });
        }
      } catch (err) {
        console.warn('Auto meta fetch failed:', err.message || err);
      }
    })();
  }, [currentTrack, meta, auto, dispatch]);
}
