// Where a track's metadata came from — the `meta_source` / `cover_source` /
// `lyrics_source` columns the shell records. The audio file itself is the
// baseline: online backends only fill in what the file could not answer, and
// a manual edit is neither.
//
//   file      tags/artwork/lyrics embedded in the audio file
//   sidecar   a .lrc sitting next to the audio file
//   filename  title derived from the file name (no readable tags)
//   plugin    written by an online metadata backend
//   user      hand-edited in the Edit Track dialog

export const SOURCE_LABELS = {
  file: 'From file',
  sidecar: 'Sidecar .lrc',
  filename: 'From filename',
  plugin: 'Online',
  user: 'Edited',
};

export function sourceLabel(source) {
  return SOURCE_LABELS[source] || 'Unknown';
}

/// 'file' (from the audio file / a sidecar next to it) vs 'online' vs 'other',
/// for styling the badge.
export function sourceKind(source) {
  if (source === 'file' || source === 'sidecar' || source === 'filename') return 'file';
  if (source === 'plugin') return 'online';
  if (source === 'user') return 'user';
  return 'unknown';
}
