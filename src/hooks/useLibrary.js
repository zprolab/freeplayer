import { useCallback, useEffect, useRef } from 'react';
import { usePlayer } from '../context/PlayerContext';
import { applyMonoFont } from '../utils/fonts';

export function useLibrary() {
  const { state, dispatch } = usePlayer();

  // Monotonic id per loadTracks call: a slow stale response must never
  // overwrite a newer one (debounced search racing a sort change).
  const loadSeqRef = useRef(0);

  const loadTracks = useCallback(async () => {
    const seq = ++loadSeqRef.current;
    try {
      const data = await window.freeplayer.getTracks({
        search: state.searchQuery,
        sortBy: state.sortBy,
        sortDir: state.sortDir,
      });
      if (seq !== loadSeqRef.current) return; // stale response — drop it
      dispatch({ type: 'SET_TRACKS', payload: data });
    } catch (err) {
      console.error('Failed to load tracks:', err);
    }
  }, [state.searchQuery, state.sortBy, state.sortDir, dispatch]);

  const checkSetup = useCallback(async (isCancelled) => {
    const cancelled = isCancelled || (() => false);
    try {
      const result = await window.freeplayer.isSetup();
      if (cancelled()) return;
      dispatch({ type: 'SET', payload: { isSetup: result.setup, libraryDir: result.libraryDir || '' } });
      const impMode = await window.freeplayer.getSetting('import_mode');
      if (impMode && !cancelled()) dispatch({ type: 'SET', payload: { importMode: impMode } });
      // Global persistent volume: restore last-used value; fall back to
      // default_volume (first run), then 0.8 — no jumps on restart.
      const savedVol = await window.freeplayer.getSetting('volume');
      const defVol = savedVol != null
        ? savedVol
        : await window.freeplayer.getSetting('default_volume');
      if (defVol != null && !cancelled()) {
        const vol = parseFloat(defVol);
        if (isFinite(vol)) {
          dispatch({ type: 'SET', payload: { defaultVolume: vol, volume: vol } });
        }
      }
      const defVis = await window.freeplayer.getSetting('default_visualizer');
      if (defVis && !cancelled()) {
        dispatch({ type: 'SET', payload: { defaultVisualizer: defVis, visualizerMode: defVis } });
      }
      // Mono font preference (local fonts only — never fetched from a CDN)
      const monoFont = await window.freeplayer.getSetting('mono_font');
      if (monoFont && !cancelled()) applyMonoFont(monoFont);
      if (result.setup && !cancelled()) {
        await loadTracks();
      }
    } catch (err) {
      console.error('Setup check failed:', err);
    } finally {
      if (!cancelled()) dispatch({ type: 'SET', payload: { isLoading: false } });
    }
  }, [dispatch, loadTracks]);

  const debounceRef = useRef(null);

  // Debounced search
  useEffect(() => {
    if (!state.isSetup) return;
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      loadTracks();
    }, 250);
    return () => clearTimeout(debounceRef.current);
  }, [state.searchQuery, state.isSetup]); // eslint-disable-line react-hooks/exhaustive-deps

  // Initial load and sort changes fire immediately (no debounce)
  useEffect(() => {
    let cancelled = false;
    checkSetup(() => cancelled);
    return () => { cancelled = true; };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (state.isSetup) loadTracks();
  }, [state.isSetup, state.sortBy, state.sortDir]); // eslint-disable-line react-hooks/exhaustive-deps

  const handleImportComplete = useCallback(async (result) => {
    dispatch({ type: 'SET', payload: { importModalOpen: false } });
    if (result && !result.canceled) {
      await loadTracks();
      const setupResult = await window.freeplayer.isSetup();
      dispatch({ type: 'SET', payload: { isSetup: setupResult.setup, libraryDir: setupResult.libraryDir || '' } });
    }
  }, [dispatch, loadTracks]);

  const handleImportModeChange = useCallback(async (mode) => {
    dispatch({ type: 'SET', payload: { importMode: mode } });
    await window.freeplayer.setSetting({ key: 'import_mode', value: mode });
  }, [dispatch]);

  const handleDefaultVolumeChange = useCallback(async (vol) => {
    dispatch({ type: 'SET', payload: { defaultVolume: vol } });
    await window.freeplayer.setSetting({ key: 'default_volume', value: String(vol) });
  }, [dispatch]);

  const handleDefaultVisualizerChange = useCallback(async (mode) => {
    dispatch({ type: 'SET', payload: { defaultVisualizer: mode } });
    await window.freeplayer.setSetting({ key: 'default_visualizer', value: mode });
  }, [dispatch]);

  const handleResetDatabase = useCallback(async () => {
    dispatch({ type: 'SET', payload: {
      tracks: [], currentTrack: null, isPlaying: false, queue: [], queueIndex: -1,
      shuffledQueue: [], playMode: 'sequential', volume: 0.8, currentTime: 0, duration: 0,
      eqEnabled: false, visualizerMode: 'waveform',
      libraryDir: '', isSetup: false, importMode: 'copy', defaultVolume: 0.8,
      defaultVisualizer: 'waveform', autoFetchMeta: false,
      playlists: [], activePlaylistId: null, playlistTracks: [],
    }});
  }, [dispatch]);

  return {
    loadTracks,
    handleImportComplete,
    handleImportModeChange,
    handleDefaultVolumeChange,
    handleDefaultVisualizerChange,
    handleResetDatabase,
  };
}
