import { useState, useEffect, useRef } from 'react';
import { usePlayer } from '../context/PlayerContext';
import { Button, ModalShell } from '../ui/components';
import TrackPicker from './TrackPicker';
import * as client from '../core/client';

export default function PlaylistModal({ mode, playlist, allTracks, onClose, onSubmit }) {
  const { state } = usePlayer();
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [selectedIds, setSelectedIds] = useState(new Set());
  const [isLoadingTracks, setIsLoadingTracks] = useState(mode === 'edit');
  const [tracksLoaded, setTracksLoaded] = useState(mode !== 'edit');
  const [tracksError, setTracksError] = useState(null);
  const inputRef = useRef(null);

  const showTrackPicker = mode === 'create' || mode === 'edit';

  useEffect(() => {
    if (mode === 'rename' && playlist) {
      setName(playlist.name || '');
    }
  }, [mode, playlist]);

  useEffect(() => {
    inputRef.current?.focus();
    if (mode === 'rename') {
      inputRef.current?.select();
    }
    // `mode` is read here; an empty array pinned its first value, so opening the
    // dialog in rename right after an edit would not select the existing name.
  }, [mode]);

  // Load existing playlist tracks in edit mode
  useEffect(() => {
    let stale = false;
    if (mode === 'edit' && playlist) {
      setIsLoadingTracks(true);
      setTracksLoaded(false);
      setTracksError(null);
      client.playlists.tracks(playlist.id).then(tracks => {
        if (stale) return;
        setSelectedIds(new Set(tracks.map(t => t.id)));
        setIsLoadingTracks(false);
        setTracksLoaded(true);
      }).catch((err) => {
        if (stale) return;
        setIsLoadingTracks(false);
        // Leave tracksLoaded false: submitting an empty selection in edit mode
        // makes the native side DELETE every row and re-insert nothing, which
        // silently empties the playlist. A failed load must block Save.
        setTracksError(err?.message || 'Could not load this playlist');
      });
    }
    return () => { stale = true; };
  }, [mode, playlist]);

  // Pre-select pendingAddTrack in create mode
  useEffect(() => {
    if (mode === 'create' && state.pendingAddTrack) {
      setSelectedIds(new Set([state.pendingAddTrack.id]));
    }
  }, [mode, state.pendingAddTrack]);

  const handleToggle = (trackId) => {
    setSelectedIds(prev => {
      const next = new Set(prev);
      if (next.has(trackId)) next.delete(trackId);
      else next.add(trackId);
      return next;
    });
  };

  const handleSelectAll = (trackIds) => {
    setSelectedIds(prev => new Set([...prev, ...trackIds]));
  };

  const handleDeselectAll = (trackIds) => {
    setSelectedIds(prev => {
      const next = new Set(prev);
      trackIds.forEach(id => next.delete(id));
      return next;
    });
  };

  const handleSubmit = (e) => {
    e.preventDefault();
    if (mode === 'create') {
      const trimmed = name.trim();
      if (!trimmed) return;
      onSubmit({ name: trimmed, description: description.trim(), trackIds: [...selectedIds] });
    } else if (mode === 'rename') {
      const trimmed = name.trim();
      if (!trimmed) return;
      onSubmit({ name: trimmed });
    } else if (mode === 'edit') {
      // Refuse to submit an empty selection: the native handler deletes all
      // rows first, so an empty array wipes the playlist.
      if (!tracksLoaded || selectedIds.size === 0) return;
      onSubmit({ trackIds: [...selectedIds] }, playlist?.id);
    }
  };


  const modalTitle = mode === 'create' ? 'New Playlist'
    : mode === 'rename' ? 'Rename Playlist'
    : 'Edit Playlist Tracks';

  const submitLabel = mode === 'create' ? 'Create'
    : mode === 'rename' ? 'Rename'
    : 'Save';

  const canSubmit = mode === 'create' ? name.trim().length > 0
    : mode === 'rename' ? name.trim().length > 0
    // Edit mode: Save must stay disabled until the existing tracks have really
    // loaded, and must never push an empty list (see handleSubmit).
    : tracksLoaded && !tracksError && selectedIds.size > 0;

  return (
    <ModalShell
      title={mode === 'edit' && playlist ? `${modalTitle} — ${playlist.name}` : modalTitle}
      onClose={onClose}
      width={showTrackPicker ? 'var(--fp-dialog-width)' : '420px'}
    >
        <form onSubmit={handleSubmit}>
          <div className="modal-body" style={showTrackPicker ? { display: 'flex', flexDirection: 'column', maxHeight: '70vh', overflow: 'hidden' } : {}}>
            {(mode === 'create' || mode === 'rename') && (
              <div className="edit-fields">
                <div className="edit-field">
                  <label className="edit-label">Name</label>
                  <input
                    ref={inputRef}
                    type="text"
                    className="edit-input"
                    placeholder="My Playlist"
                    value={name}
                    onChange={(e) => setName(e.target.value)}
                    maxLength={200}
                    autoFocus
                  />
                </div>
                {mode === 'create' && (
                  <div className="edit-field">
                    <label className="edit-label">
                      Description <span style={{ fontWeight: 400, textTransform: 'none', letterSpacing: 0 }}>(optional)</span>
                    </label>
                    <input
                      type="text"
                      className="edit-input"
                      placeholder="A few words about this playlist..."
                      value={description}
                      onChange={(e) => setDescription(e.target.value)}
                      maxLength={500}
                    />
                  </div>
                )}
              </div>
            )}

            {showTrackPicker && (
              isLoadingTracks ? (
                <div className="track-picker-empty" style={{ marginTop: '24px' }}>
                  Loading tracks...
                </div>
              ) : tracksError ? (
                <div className="form-error" style={{ marginTop: '24px' }}>
                  {tracksError} — saving is disabled to avoid emptying the playlist.
                </div>
              ) : (
                <TrackPicker
                  tracks={allTracks || []}
                  selectedIds={selectedIds}
                  onToggle={handleToggle}
                  onSelectAll={handleSelectAll}
                  onDeselectAll={handleDeselectAll}
                />
              )
            )}
          </div>

          <div className="modal-footer">
            <Button variant="secondary" onClick={onClose}>Cancel</Button>
            {/* type="submit" is load-bearing: Button defaults to type="button",
                which would silently stop Enter-to-submit and the form's
                onSubmit handler. */}
            <Button type="submit" variant="primary" disabled={!canSubmit}>
              {submitLabel}
            </Button>
          </div>
        </form>
    </ModalShell>
  );
}
