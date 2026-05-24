import { useCallback } from 'react';
import { usePlayer } from '../context/PlayerContext';

export function usePlaylists() {
  const { state, dispatch } = usePlayer();

  const loadPlaylists = useCallback(async () => {
    try {
      const data = await window.freeplayer.getPlaylists();
      dispatch({ type: 'SET_PLAYLISTS', payload: data });
    } catch (err) {
      console.error('Failed to load playlists:', err);
    }
  }, [dispatch]);

  const handleSelectPlaylist = useCallback(async (playlistId) => {
    if (playlistId === null) {
      dispatch({ type: 'SET', payload: { activePlaylistId: null } });
    } else {
      dispatch({ type: 'SET', payload: { activePlaylistId: playlistId } });
      const tracks = await window.freeplayer.getPlaylistTracks(playlistId);
      dispatch({ type: 'SET_PLAYLIST_TRACKS', payload: tracks });
    }
    dispatch({ type: 'SET', payload: { view: 'library' } });
  }, [dispatch]);

  const handleCreatePlaylist = useCallback(async ({ name, description }) => {
    const result = await window.freeplayer.createPlaylist({ name, description });
    await loadPlaylists();
    dispatch({ type: 'SET', payload: { playlistModal: null } });
    if (state.pendingAddTrack) {
      const playlistId = result.lastInsertRowid || result.id;
      await window.freeplayer.addToPlaylist({ playlistId, trackId: state.pendingAddTrack.id });
      dispatch({ type: 'SET', payload: { pendingAddTrack: null } });
    }
  }, [dispatch, loadPlaylists, state.pendingAddTrack]);

  const handleRenamePlaylist = useCallback(async ({ name }) => {
    if (state.playlistModal?.playlist) {
      await window.freeplayer.renamePlaylist({ id: state.playlistModal.playlist.id, name });
      await loadPlaylists();
      dispatch({ type: 'SET', payload: { playlistModal: null } });
    }
  }, [dispatch, loadPlaylists, state.playlistModal]);

  const handleDeletePlaylist = useCallback(async (playlistId) => {
    await window.freeplayer.deletePlaylist(playlistId);
    if (state.activePlaylistId === playlistId) {
      dispatch({ type: 'SET', payload: { activePlaylistId: null } });
    }
    await loadPlaylists();
  }, [dispatch, loadPlaylists, state.activePlaylistId]);

  const handleAddToPlaylist = useCallback(async (playlistId, trackId) => {
    await window.freeplayer.addToPlaylist({ playlistId, trackId });
    if (state.activePlaylistId === playlistId) {
      const tracks = await window.freeplayer.getPlaylistTracks(playlistId);
      dispatch({ type: 'SET_PLAYLIST_TRACKS', payload: tracks });
    }
  }, [dispatch, state.activePlaylistId]);

  const handleRemoveFromPlaylist = useCallback(async (trackId) => {
    if (state.activePlaylistId === null) return;
    await window.freeplayer.removeFromPlaylist({ playlistId: state.activePlaylistId, trackId });
    const tracks = await window.freeplayer.getPlaylistTracks(state.activePlaylistId);
    dispatch({ type: 'SET_PLAYLIST_TRACKS', payload: tracks });
  }, [dispatch, state.activePlaylistId]);

  const handleOpenCreateForTrack = useCallback((track) => {
    dispatch({ type: 'SET', payload: { pendingAddTrack: track, playlistModal: { mode: 'create', playlist: null } } });
  }, [dispatch]);

  return {
    loadPlaylists,
    handleSelectPlaylist,
    handleCreatePlaylist,
    handleRenamePlaylist,
    handleDeletePlaylist,
    handleAddToPlaylist,
    handleRemoveFromPlaylist,
    handleOpenCreateForTrack,
  };
}
