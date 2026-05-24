# Playback Modes & Playlists — Design Spec

**Date:** 2026-05-22
**Status:** Approved

## Overview

Add playback order control (list loop, repeat-one, shuffle) and playlist management (default "All Tracks" list + user-created playlists) to FreePlayer.

## Playback Modes

Three mutually exclusive modes stored as `playMode` state in `App.jsx`:

| Mode | State Value | Behavior |
|------|-------------|----------|
| List Loop | `'sequential'` | Play through queue in order; at end, wrap to index 0 |
| Repeat One | `'repeat-one'` | On `ended` event, reset `audio.currentTime = 0` and replay |
| Shuffle | `'shuffle'` | On play, shuffle queue with Fisher-Yates; store shuffled copy separate from original |

Default mode: `'sequential'` (matches current linear behavior, just adds wrap-around).

### handleNext Logic (pseudocode)

```
if playMode === 'repeat-one':
    audio.currentTime = 0; audio.play()
    return

if playMode === 'sequential':
    if queueIndex < queue.length - 1: next index
    else: index 0 (loop)

if playMode === 'shuffle':
    next index in shuffledQueue; re-shuffle on wrap-around
```

### UI Placement

**PlayerBar (compact):** Three SVG icon-only buttons in the extras area (left of volume). Active mode highlighted with `--gl-orange`. Icon shapes: loop-arrows, repeat-one (with "1" badge), crossed-arrows for shuffle.

**NowPlaying (full):** Three text-labeled segmented buttons below play controls, matching existing `.vis-mode-group` pattern. Labels: "List Loop", "Repeat One", "Shuffle".

Both locations share the same `playMode` state — changing one updates the other.

## Playlist System

### Data Layer (already implemented)

Database tables `playlists` and `playlist_tracks` exist with full CRUD in `database.js`. IPC handlers registered in `main.js`. Preload bridge exposes all methods via `window.freeplayer.*`.

### Sidebar Integration

Navigation area remains unchanged. New "PLAYLISTS" section added below nav, separated by a border:

```
[Navigation items...]
────────────────────
PLAYLISTS           [+]
  All Tracks  (default, always first)
  Favorites   (user-created)
  Workout     (user-created)
────────────────────
Import Music
```

- "All Tracks" is the default playlist representing the entire library — always present, non-deletable, non-renamable
- User-created playlists appear below; max display ~5-6 before scrolling
- "+" button opens Create Playlist modal
- Click a playlist name → switch to Library view, load that playlist's tracks
- Right-click user playlist → Rename / Delete context menu

### Create Playlist Modal

Simple modal matching existing `.modal` pattern:
- Title: "New Playlist"
- Fields: Name (required), Description (optional)
- Buttons: Cancel / Create (primary, `--gl-orange`)
- On create: call `window.freeplayer.createPlaylist()`, refresh playlist list, select new playlist

### Adding Tracks to Playlists

Extend the existing Library row context menu (currently: Edit Metadata, Delete Track):

```
Edit Metadata
Add to Playlist  ▶  ┌ Favorites
Delete Track         ├ Workout
                     ├ Chilled
                     └ + New Playlist...
```

- Submenu appears on hover/click of "Add to Playlist"
- Tracks already in the target playlist show a checkmark
- Duplicate additions silently ignored (UNIQUE constraint in DB)
- "New Playlist..." triggers Create Playlist modal; on create, auto-add the track

### Library View Enhancement (Playlist Context)

When viewing a playlist (not the full library), the top bar changes:

```
[Playlist Name] [12 tracks]          [Play All] [Search...]
```

- Title shows playlist name instead of "Library"
- Track count badge with `--gl-blue` styling
- "Play All" button (primary, `--gl-orange`) — sets queue to all playlist tracks and starts from index 0
- Right-click on track row adds "Remove from Playlist" option (user playlists only, not "All Tracks")

## Component Changes

| File | Change |
|------|--------|
| `src/App.jsx` | New state: `playMode`, `playlists`, `activePlaylistId`, `shuffledQueue`. Rewrite `handleNext`/`handlePrev` for modes. New handlers: `setPlayMode`, `loadPlaylists`, `selectPlaylist`, `createPlaylist`, `deletePlaylist`, `addToPlaylist`, `removeFromPlaylist`. |
| `src/App.css` | New styles: play-mode buttons (PlayerBar compact + NowPlaying full), playlist sidebar section, submenu, playlist top-bar (~150 lines). |
| `src/components/Sidebar.jsx` | Render playlists section from `playlists` prop. Accept `activePlaylistId`, `onSelectPlaylist`, `onCreatePlaylist`, `onDeletePlaylist`, `onRenamePlaylist` props. |
| `src/components/Library.jsx` | Accept `playlistContext` prop (playlist name/id or null for full library). Render enhanced top bar for playlist context. Show "Remove from Playlist" in context menu when applicable. Accept `onAddToPlaylist`, `onRemoveFromPlaylist` props. |
| `src/components/NowPlaying.jsx` | Add play mode segmented button group below controls. Accept `playMode`, `onPlayModeChange` props. |
| `src/components/PlayerBar.jsx` | Add compact play mode icon buttons in extras area. Accept `playMode`, `onPlayModeChange` props. |
| `src/components/PlaylistModal.jsx` | **New.** Create/Rename playlist modal. Props: `mode` ('create'|'rename'), `playlist` (for rename), `onClose`, `onSubmit`. |
| `src/components/PlaylistMenu.jsx` | **New.** Submenu component for "Add to Playlist" flyout. Props: `track`, `playlists`, `onAdd`, `onCreateNew`. |

## CSS Variables & Style

All new styles use the existing design system variables (`--gl-*`, `--font-ui`, `--font-mono`). No new design tokens introduced. No emoji/Unicode icons — all icons are inline SVG matching the existing pattern in Sidebar, PlayerBar, and NowPlaying.

## Edge Cases

- **Empty playlist:** Show empty state (existing `.empty-state` pattern) with "This playlist is empty" message and hint to add tracks via right-click
- **Deleting active playlist:** Fall back to "All Tracks", clear selection
- **Shuffle with 1 track:** No-op (single track can't be shuffled meaningfully)
- **Rapid mode switching:** Handle `ended` event correctly — check current `playMode` at event time, not at play-start time
