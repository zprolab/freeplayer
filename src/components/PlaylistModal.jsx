import React, { useState, useEffect, useRef } from 'react';

export default function PlaylistModal({ mode, playlist, onClose, onSubmit }) {
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const inputRef = useRef(null);

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

  const handleSubmit = (e) => {
    e.preventDefault();
    const trimmed = name.trim();
    if (!trimmed) return;
    const payload = { name: trimmed };
    if (mode === 'create') payload.description = description.trim();
    onSubmit(payload);
  };

  const handleKeyDown = (e) => {
    if (e.key === 'Escape') onClose();
  };

  return (
    <div className="modal-overlay" onClick={onClose} onKeyDown={handleKeyDown}>
      <div className="modal" onClick={(e) => e.stopPropagation()} style={{ width: '420px' }}>
        <div className="modal-header">
          <h2 className="modal-title">
            {mode === 'create' ? 'New Playlist' : 'Rename Playlist'}
          </h2>
          <button className="modal-close btn-icon" onClick={onClose}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
              <line x1="18" y1="6" x2="6" y2="18"/>
              <line x1="6" y1="6" x2="18" y2="18"/>
            </svg>
          </button>
        </div>

        <form onSubmit={handleSubmit}>
          <div className="modal-body">
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
          </div>

          <div className="modal-footer">
            <button type="button" className="btn btn-secondary" onClick={onClose}>Cancel</button>
            <button type="submit" className="btn btn-primary" disabled={!name.trim()}>
              {mode === 'create' ? 'Create' : 'Rename'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
