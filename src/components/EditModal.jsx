import { useState, useRef, useEffect } from 'react';
import { Button, ModalShell } from '../ui/components';
import * as client from '../core/client';

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
    // Validate the year before it reaches the bridge. parseInt('') is NaN, which
    // JSON-serialises to null, binds as SQL NULL and silently CLEARS a year the
    // track already had; negative and out-of-range values were stored as-is
    // because the column carries no constraint.
    let yearValue = null;
    const rawYear = year.trim();
    if (rawYear) {
      const parsed = Number.parseInt(rawYear, 10);
      if (!/^[0-9]{1,4}$/.test(rawYear) || parsed < 1 || parsed > 9999) {
        setError('Year must be a number between 1 and 9999');
        return;
      }
      yearValue = parsed;
    }

    setSaving(true);
    setError('');
    try {
      // The native handler reads a FLAT payload (`d["id"]` plus one key per
      // column) — the shape App.jsx and the plugin api already send. Nesting the
      // columns under `fields` left the native whitelist loop with nothing to
      // match, so Database.updateTrack returned false and EVERY edit was
      // silently discarded while the dialog still closed as though it saved.
      await client.tracks.update({
        id: track.id,
        title: title.trim(),
        artist: artist.trim() || 'Unknown Artist',
        album: album.trim() || 'Unknown Album',
        genre: genre.trim() || null,
        year: yearValue,
        // Provenance: these values were hand-edited rather than read from the
        // file, so the track stops claiming a file baseline for its tags.
        meta_source: 'user',
      });
      onSaved();
    } catch (err) {
      setError(err.message || 'Failed to save');
    } finally {
      // Released on success too: the caller may keep the dialog mounted, and a
      // stuck `saving` leaves the Save button disabled forever.
      setSaving(false);
    }
  };

  const handleKeyDown = (e) => {
    // Ignore while a save is in flight so the shortcut cannot queue a second one.
    if (e.key === 'Enter' && (e.metaKey || e.ctrlKey) && !saving) {
      e.preventDefault();
      handleSave();
    }
  };

  return (
    <ModalShell
      title="Edit Track"
      onClose={onClose}
    >
      {/* The shell owns Escape; Cmd/Ctrl+Enter is this dialog's own shortcut,
          so it stays on the body element it belongs to. */}
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
