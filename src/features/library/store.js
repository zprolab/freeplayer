// Library data logic — the non-React half of the library feature.
//
// Same split as features/playback/engine.js: the module that owns fetching and
// ordering knows nothing about React, and the hook on top of it is a thin
// adapter. What lives here is the part that was previously spread across
// src/App.jsx (a client-side reimplementation of the database's sort) and
// useLibrary (a fetch whose ordering rules are the host's, not the caller's).
//
// Keeping the two orderings side by side is the point: the library view asks
// the host to sort, while the playlist view cannot (getPlaylistTracks takes no
// sort parameters and returns playlist position) and must reimplement it. When
// those two drift, the same list appears in two different orders depending on
// which screen you opened — so they are documented together here.

import * as client from '@/core/client.js';

/** Sort keys the host accepts for the library query. */
const HOST_SORTABLE = new Set(['title', 'artist', 'album', 'genre', 'year', 'duration']);

/**
 * Load tracks for the library view.
 *
 * The host performs search and sort, so this passes them through rather than
 * filtering locally — a local pass would disagree with the host on
 * case-folding and on numeric vs text comparison for year/duration.
 *
 * Returns an array; a host that answers with something else yields an empty
 * list rather than a crash downstream (`data.map` on undefined was reachable
 * through a rejected bridge call that had been caught one level up).
 */
export async function fetchTracks({ search = '', sortBy = 'title', sortDir = 'ASC' } = {}) {
  const sort = HOST_SORTABLE.has(sortBy) ? sortBy : 'title';
  const dir = sortDir === 'DESC' ? 'DESC' : 'ASC';
  const data = await client.library.tracks({ search, sortBy: sort, sortDir: dir });
  return Array.isArray(data) ? data : [];
}

/**
 * Compare two tracks the way the database would, for views the host cannot sort.
 *
 * Mirrors the host's semantics deliberately: text keys compare
 * case-insensitively, duration and year compare numerically (with a missing
 * value reading as 0 rather than NaN, which would make `sort` behave
 * inconsistently depending on array length).
 */
export function compareTracks(a, b, sortBy, sortDir) {
  const sign = sortDir === 'ASC' ? 1 : -1;
  let cmp;
  if (sortBy === 'duration' || sortBy === 'year') {
    cmp = (Number(a[sortBy]) || 0) - (Number(b[sortBy]) || 0);
  } else {
    const av = String(a[sortBy] ?? '').toLowerCase();
    const bv = String(b[sortBy] ?? '').toLowerCase();
    cmp = av < bv ? -1 : av > bv ? 1 : 0;
  }
  return cmp * sign;
}

/** Sort a copy (never mutates the caller's array — Redux state is frozen). */
export function sortTracks(tracks, sortBy, sortDir) {
  return tracks.slice().sort((a, b) => compareTracks(a, b, sortBy, sortDir));
}
