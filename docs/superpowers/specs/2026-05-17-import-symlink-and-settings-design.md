# Import Symlink Mode & Settings Page — Design Spec

**Date:** 2026-05-17
**Status:** Approved

## Overview

Add two related features to FreePlayer:

1. **Symlink import mode** — Alternative to copying files; creates symbolic links in the library directory instead of duplicating data.
2. **Settings page** — New view where users configure import mode, library directory, default volume, default visualizer, and reset the database.

## Architecture

### Files Changed

| File | Change |
|------|--------|
| `electron/main.js` | Modify `music:import-files` to branch on import mode (copy vs symlink). Add `fs.symlinkSync` path. |
| `electron/preload.js` | Add `selectLibraryDir` method for the library directory picker dialog. |
| `src/App.jsx` | Add `settings` view to `VIEWS`. On mount, call `getSetting` for each setting key (`import_mode`, `default_volume`, `default_visualizer`) and store in state. Apply `default_volume` to audio element. Use `default_visualizer` as initial `visualizerMode`. Pass settings and setters to `<Settings>`. |
| `src/components/Sidebar.jsx` | Add "Settings" nav item (gear icon) at the bottom of the nav section. |
| `src/components/ImportModal.jsx` | Show import mode badge/indicator during import flow so user knows which mode is active. |
| `src/App.css` | Add styles for settings page: setting cards, radio cards for import mode, segmented button for visualizer, danger zone, toggle switches. |

### Files Created

| File | Purpose |
|------|---------|
| `src/components/Settings.jsx` | New settings page component with all setting sections. |

## Component Design

### Settings Page (`Settings.jsx`)

Organized as a vertical stack of setting cards, each with a title, description, and controls. Uses the existing CSS variable system (`--gl-*`).

**Sections (top to bottom):**

1. **Import Mode** — Two radio-card options (`Copy Files` / `Symlink`). Selected card gets orange border + light orange background. Each card has a title and one-line description of the trade-off. Persists to DB immediately on click via `setSetting('import_mode', 'copy'|'symlink')`.

2. **Library Directory** — Read-only path display in monospace, inside a bordered box with a folder icon. "Change..." button opens a native directory picker dialog. On change: updates the `library_dir` setting and refreshes the display.

3. **Playback** — Two controls:
   - **Default Volume** — Horizontal slider (0–100%) with percentage readout in monospace. On change: saves `default_volume` setting.
   - **Default Visualizer** — Segmented button group (Waveform | Spectrogram | Off), matching the Now Playing visualizer controls. Saves `default_visualizer` setting.

4. **Danger Zone** — Red-bordered card. "Reset Database" row with description and a "Reset..." button. On click: shows a confirmation dialog. On confirm: clears all rows from `tracks`, `play_history`, `playlist_tracks`, `playlists`, and `settings` tables, then resets app to empty setup state (pressing Cancel on the dialog does nothing). Files on disk are not touched.

### Import Flow Changes (`electron/main.js`)

The `music:import-files` handler branches on `import_mode` setting:

- **`copy` (default):** Current behavior — `fs.copyFileSync` file to `libraryDir/Artist/Album/`.
- **`symlink`:** Creates `Artist/Album/` directory structure in `libraryDir`, then `fs.symlinkSync(originalPath, libraryPath)`.

In both modes, the `file_path` stored in the database is the path inside the library directory (the copy or the symlink), so playback and file resolution work identically.

### ImportModal Changes

Add a small badge/indicator at the top of the import modal (next to step indicator) showing the current import mode: "Copy Mode" or "Symlink Mode". This is informational — the user changes the mode in Settings.

## Data Flow

```
Settings stored in SQLite `settings` table (key/value pairs, already exists):

  library_dir         → "/Users/.../FreePlayer Library"
  import_mode         → "copy" | "symlink"     (NEW)
  default_volume      → "0.8"                  (NEW)
  default_visualizer  → "waveform"             (NEW)
```

**Startup:** App.jsx reads all settings on mount (one IPC call). Settings component receives values as props.

**Save:** Each control saves immediately on change via `window.freeplayer.setSetting({ key, value })`. No "Save" button.

**Propagation:** `default_volume` is applied to the audio element on app init. `default_visualizer` is used as initial state for `visualizerMode` in App.jsx. `import_mode` is read by `music:import-files` IPC handler when importing.

### New IPC Handlers

None needed — the existing `getSetting`/`setSetting` handlers are sufficient. The `music:import-files` handler reads `import_mode` directly from the database.

One additional IPC for the "Change Library Directory" dialog:

- `music:select-library-dir` — Opens native directory picker, returns the chosen path (or `{ canceled: true }`).

## Error Handling

### Symlink Failures
- On platforms without symlink support (rare on macOS/Linux), `fs.symlinkSync` throws. Catch per-file, add to `results.errors`, continue with remaining files.
- Edge case: symlink to a file that later gets deleted. The media protocol handler already returns 404 for missing files — no change needed.

### Settings Save Failures
- Database write failures are silent (existing pattern). The `setSetting` call is fire-and-forget from the frontend perspective.

### Reset Database
- Requires explicit confirmation in a two-step dialog ("Are you sure?" → "This cannot be undone.").
- After reset: clear all DB tables, redirect to the empty library setup screen.

## Testing Considerations

- Test import with `import_mode = "symlink"` — verify symlinks created, tracks play correctly.
- Verify mode switch — import in copy mode, switch to symlink, import again, both sets of files coexist.
- Verify settings persist across app restart.
- Verify default volume is applied on app launch.
- Verify visualizer default is respected on Now Playing view.
- Verify "Reset Database" clears everything and returns to setup state.
- Handle edge case: symlink import when original file has been moved (expect 404 on playback).

## Design System Notes

- All new CSS uses existing `--gl-*` variables — no new colors or tokens.
- Radio cards for import mode follow the same border-radius/spacing as stat cards.
- Segmented button for visualizer mirrors the existing `.vis-mode-group` styles.
- Danger zone uses `--gl-red` for border and text, consistent with delete actions elsewhere.
- The settings icon in sidebar uses a gear SVG, consistent with the 18px icon set.
