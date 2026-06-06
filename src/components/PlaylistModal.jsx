import React, { useState, useEffect, useRef } from 'react';
import { usePlayer } from '../context/PlayerContext';
import TrackPicker from './TrackPicker';

export default function PlaylistModal({ mode, playlist, allTracks, onClose, onSubmit }) {
  const { state } = usePlayer();
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [selectedIds, setSelectedIds] = useState(new Set());
  const [isLoadingTracks, setIsLoadingTracks] = useState(false);
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
  }, []);

  // Load existing playlist tracks in edit mode
  useEffect(() => {
    if (mode === 'edit' && playlist) {
      setIsLoadingTracks(true);
      window.freeplayer.getPlaylistTracks(playlist.id).then(tracks => {
        setSelectedIds(new Set(tracks.map(t => t.id)));
        setIsLoadingTracks(false);
      }).catch(() => {
        setIsLoadingTracks(false);
      });
    }
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
      onSubmit({ trackIds: [...selectedIds] }, playlist?.id);
    }
  };

  const handleKeyDown = (e) => {
    if (e.key === 'Escape') onClose();
  };

  const modalTitle = mode === 'create' ? 'New Playlist'
    : mode === 'rename' ? 'Rename Playlist'
    : 'Edit Playlist Tracks';

  const submitLabel = mode === 'create' ? 'Create'
    : mode === 'rename' ? 'Rename'
    : 'Save';

  const canSubmit = mode === 'edit' ? true
    : name.trim().length > 0;

  return (
    <div className="modal-overlay" onClick={onClose} onKeyDown={handleKeyDown}>
      <div
        className="modal"
        onClick={(e) => e.stopPropagation()}
        style={{ width: showTrackPicker ? '680px' : '420px' }}
      >
        <div className="modal-header">
          <h2 className="modal-title">{modalTitle}</h2>
          {mode === 'edit' && playlist && (
            <span style={{ fontSize: '12px', color: 'var(--gl-text-secondary)', marginLeft: '8px' }}>
              — {playlist.name}
            </span>
          )}
          <button className="modal-close btn-icon" onClick={onClose}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
              <line x1="18" y1="6" x2="6" y2="18"/>
              <line x1="6" y1="6" x2="18" y2="18"/>
            </svg>
          </button>
        </div>

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
            <button type="button" className="btn btn-secondary" onClick={onClose}>Cancel</button>
            <button type="submit" className="btn btn-primary" disabled={!canSubmit}>
              {submitLabel}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
