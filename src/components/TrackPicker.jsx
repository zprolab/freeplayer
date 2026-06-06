import React, { useState, useMemo } from 'react';

function formatDuration(seconds) {
  if (!seconds || seconds <= 0) return '0:00';
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, '0')}`;
}

export default function TrackPicker({ tracks, selectedIds, onToggle, onSelectAll, onDeselectAll }) {
  const [searchQuery, setSearchQuery] = useState('');

  const filtered = useMemo(() => {
    if (!searchQuery.trim()) return tracks;
    const q = searchQuery.toLowerCase();
    return tracks.filter(t =>
      t.title.toLowerCase().includes(q) ||
      t.artist.toLowerCase().includes(q) ||
      t.album.toLowerCase().includes(q)
    );
  }, [tracks, searchQuery]);

  const filteredIds = useMemo(() => new Set(filtered.map(t => t.id)), [filtered]);

  const handleSelectAll = () => {
    onSelectAll(filtered.map(t => t.id));
  };

  const handleDeselectAll = () => {
    onDeselectAll(filtered.map(t => t.id));
  };

  const allFilteredSelected = filtered.length > 0 && filtered.every(t => selectedIds.has(t.id));

  return (
    <div className="track-picker">
      <div className="track-picker-label">Select Tracks</div>

      <div className="track-picker-header">
        <div className="track-picker-search">
          <input
            type="text"
            className="search-input"
            placeholder="Filter tracks..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
          />
        </div>
        <div className="track-picker-actions">
          {allFilteredSelected ? (
            <button type="button" className="btn btn-secondary" onClick={handleDeselectAll}>
              Clear
            </button>
          ) : (
            <button type="button" className="btn btn-secondary" onClick={handleSelectAll}>
              Select All
            </button>
          )}
        </div>
        <span className="track-picker-count">{selectedIds.size} selected</span>
      </div>

      <div className="track-picker-list">
        {filtered.length === 0 ? (
          <div className="track-picker-empty">
            {tracks.length === 0 ? 'No tracks in library' : 'No tracks match your search'}
          </div>
        ) : (
          filtered.map(track => (
            <label
              key={track.id}
              className={`track-picker-item${selectedIds.has(track.id) ? ' selected' : ''}`}
            >
              <input
                type="checkbox"
                checked={selectedIds.has(track.id)}
                onChange={() => onToggle(track.id)}
              />
              <span className="track-picker-title">{track.title}</span>
              <span className="track-picker-artist">{track.artist}</span>
              <span className="track-picker-album">{track.album}</span>
              <span className="track-picker-duration">{formatDuration(track.duration)}</span>
            </label>
          ))
        )}
      </div>
    </div>
  );
}
