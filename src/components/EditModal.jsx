import { useState, useRef, useEffect } from 'react';
import { Button, ModalShell } from '../ui/components';

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
          // Provenance: these values were hand-edited rather than read from
          // the file, so the track stops claiming a file baseline for its tags.
          meta_source: 'user',
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
    <ModalShell
      title="Edit Track"
      onClose={onClose}
    >
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
          <Button variant="secondary" onClick={onClose}>Cancel</Button>
          <Button variant="primary" onClick={handleSave} disabled={saving}>
            {saving ? 'Saving…' : 'Save'}
          </Button>
        </div>
    </ModalShell>
  );
}
