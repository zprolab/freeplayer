import { useCallback, useEffect, useRef } from 'react';
import { usePlayer } from '../context/PlayerContext';

export function useLibrary() {
  const { state, dispatch } = usePlayer();

  const loadTracks = useCallback(async () => {
    try {
      const data = await window.freeplayer.getTracks({
        search: state.searchQuery,
        sortBy: state.sortBy,
        sortDir: state.sortDir,
      });
      dispatch({ type: 'SET_TRACKS', payload: data });
    } catch (err) {
      console.error('Failed to load tracks:', err);
    }
  }, [state.searchQuery, state.sortBy, state.sortDir, dispatch]);

  const checkSetup = useCallback(async () => {
    try {
      const result = await window.freeplayer.isSetup();
      dispatch({ type: 'SET', payload: { isSetup: result.setup, libraryDir: result.libraryDir || '' } });
      const impMode = await window.freeplayer.getSetting('import_mode');
      if (impMode) dispatch({ type: 'SET', payload: { importMode: impMode } });
      const defVol = await window.freeplayer.getSetting('default_volume');
      if (defVol) {
        const vol = parseFloat(defVol);
        dispatch({ type: 'SET', payload: { defaultVolume: vol, volume: vol } });
      }
      const defVis = await window.freeplayer.getSetting('default_visualizer');
      if (defVis) {
        dispatch({ type: 'SET', payload: { defaultVisualizer: defVis, visualizerMode: defVis } });
      }
      if (result.setup) {
        await loadTracks();
      }
    } catch (err) {
      console.error('Setup check failed:', err);
    } finally {
      dispatch({ type: 'SET', payload: { isLoading: false } });
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
    checkSetup();
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
      libraryDir: '', isSetup: false, importMode: 'copy', defaultVolume: 0.8,
      defaultVisualizer: 'waveform', visualizerMode: 'waveform',
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
