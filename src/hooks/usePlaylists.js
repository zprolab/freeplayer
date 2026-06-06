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

  const handleCreatePlaylist = useCallback(async ({ name, description, trackIds }) => {
    try {
      const result = await window.freeplayer.createPlaylist({ name, description });
      const playlistId = result.lastInsertRowid || result.id;

      // Combine pendingAddTrack with selected track IDs (deduped)
      const allTrackIds = trackIds || [];
      if (state.pendingAddTrack && !allTrackIds.includes(state.pendingAddTrack.id)) {
        allTrackIds.push(state.pendingAddTrack.id);
      }

      if (allTrackIds.length > 0) {
        await window.freeplayer.addTracksToPlaylist({ playlistId, trackIds: allTrackIds });
      }

      await loadPlaylists();
      dispatch({ type: 'SET', payload: { playlistModal: null, pendingAddTrack: null } });
    } catch (err) {
      console.error('Failed to create playlist:', err);
    }
  }, [dispatch, loadPlaylists, state.pendingAddTrack]);

  const handleRenamePlaylist = useCallback(async ({ name }) => {
    if (state.playlistModal?.playlist) {
      await window.freeplayer.renamePlaylist({ id: state.playlistModal.playlist.id, name });
      await loadPlaylists();
      dispatch({ type: 'SET', payload: { playlistModal: null } });
    }
  }, [dispatch, loadPlaylists, state.playlistModal]);

  const handleUpdatePlaylistTracks = useCallback(async ({ trackIds }, playlistId) => {
    // Use passed playlistId or fall back to modal state
    const pid = playlistId || state.playlistModal?.playlist?.id;
    if (!pid) return;

    try {
      await window.freeplayer.setPlaylistTracks({ playlistId: pid, trackIds });

      // If editing the currently active playlist, refresh displayed tracks
      if (state.activePlaylistId === pid) {
        const tracks = await window.freeplayer.getPlaylistTracks(pid);
        dispatch({ type: 'SET_PLAYLIST_TRACKS', payload: tracks });
      }

      await loadPlaylists();
      dispatch({ type: 'SET', payload: { playlistModal: null } });
    } catch (err) {
      console.error('Failed to update playlist tracks:', err);
    }
  }, [dispatch, loadPlaylists, state.playlistModal, state.activePlaylistId]);

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
    handleUpdatePlaylistTracks,
    handleAddToPlaylist,
    handleRemoveFromPlaylist,
    handleOpenCreateForTrack,
  };
}
