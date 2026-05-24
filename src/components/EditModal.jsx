import React, { useState, useRef, useEffect } from 'react';

export default function EditModal({ track, onClose, onSaved }) {
  const [title, setTitle] = useState(track.title || '');
  const [artist, setArtist] = useState(track.artist || '');
  const [album, setAlbum] = useState(track.album || '');
  const [genre, setGenre] = useState(track.genre || '');
  const [year, setYear] = useState(track.year ? String(track.year) : '');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const titleRef = useRef(null);

  useEffect(() => {
    titleRef.current?.focus();
    titleRef.current?.select();
  }, []);

  const handleSave = async () => {
    if (!title.trim()) {
      setError('Title cannot be empty');
      return;
    }
    setSaving(true);
    setError('');
    try {
      await window.freeplayer.updateTrack({
        id: track.id,
        fields: {
          title: title.trim(),
          artist: artist.trim() || 'Unknown Artist',
          album: album.trim() || 'Unknown Album',
          genre: genre.trim() || null,
          year: year ? parseInt(year, 10) : null,
        },
      });
      onSaved();
    } catch (err) {
      setError(err.message || 'Failed to save');
      setSaving(false);
    }
  };

  const handleKeyDown = (e) => {
    if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
      handleSave();
    }
  };

  return (
    <div className="modal-overlay" onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="modal" style={{ width: 480 }}>
        <div className="modal-header">
          <h2 className="modal-title">Edit Track</h2>
          <button className="btn-icon modal-close" onClick={onClose}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
              <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
            </svg>
          </button>
        </div>

        <div className="modal-body" onKeyDown={handleKeyDown}>
          {error && <div className="import-error">{error}</div>}

          <div className="edit-fields">
            <div className="edit-field">
              <label className="edit-label">Title</label>
              <input
                ref={titleRef}
                type="text"
                className="edit-input"
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                placeholder="Track title"
              />
            </div>

            <div className="edit-field">
              <label className="edit-label">Artist</label>
              <input
                type="text"
                className="edit-input"
                value={artist}
                onChange={(e) => setArtist(e.target.value)}
                placeholder="Artist name"
              />
            </div>

            <div className="edit-field">
              <label className="edit-label">Album</label>
              <input
                type="text"
                className="edit-input"
                value={album}
                onChange={(e) => setAlbum(e.target.value)}
                placeholder="Album name"
              />
            </div>

            <div className="edit-row">
              <div className="edit-field">
                <label className="edit-label">Genre</label>
                <input
                  type="text"
                  className="edit-input"
                  value={genre}
                  onChange={(e) => setGenre(e.target.value)}
                  placeholder="Genre"
                />
              </div>
              <div className="edit-field edit-field--year">
                <label className="edit-label">Year</label>
                <input
                  type="number"
                  className="edit-input"
                  value={year}
                  onChange={(e) => setYear(e.target.value)}
                  placeholder="Year"
                  min="0"
                  max="2099"
                />
              </div>
            </div>
          </div>
        </div>

        <div className="modal-footer">
          <span className="edit-hint mono">⌘↵ to save</span>
          <button className="btn btn-secondary" onClick={onClose}>Cancel</button>
          <button className="btn btn-primary" onClick={handleSave} disabled={saving}>
            {saving ? 'Saving…' : 'Save'}
          </button>
        </div>
      </div>
    </div>
  );
}
