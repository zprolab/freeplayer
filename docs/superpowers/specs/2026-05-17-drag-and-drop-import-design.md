# Drag-and-Drop Import — Design Spec

**Date:** 2026-05-17
**Status:** Approved

## Overview

Allow users to drag audio files or folders from their file manager directly into FreePlayer's Library view to trigger import. Reuses the existing ImportModal flow (scan → review → import) with a new `initialPaths` entry point. Drop zone is a drag-triggered overlay — only appears when a drag enters the Library view.

## Architecture

### Files Changed

| File | Change |
|------|--------|
| `src/App.jsx` | Add `dragOver` state, drag event handlers on content-area, pass `initialPaths` to ImportModal |
| `src/App.css` | Add drag overlay CSS (dim layer, centered dashed orange border, icon + text, fade animation) |
| `src/components/ImportModal.jsx` | Accept new `initialPaths` prop; when provided, skip dialog picker and scan paths directly |

### No backend changes

The existing IPC handlers (`music:scan`, `music:import-files`) handle the work. Drag-and-drop is purely a frontend entry-point change.

## Component Design

### App.jsx — Drag Handlers

New state: `const [dragOver, setDragOver] = useState(false);`

Event handlers on the content-area `<div>`:

- **`onDragEnter`** — If current view is `VIEWS.LIBRARY` and `!importModalOpen`: prevent default, set `dragOver = true`.
- **`onDragOver`** — When `dragOver && view === VIEWS.LIBRARY`: prevent default (required to allow drop).
- **`onDragLeave`** — When event target is the content-area itself (not a child): set `dragOver = false`.
- **`onDrop`** — Extract paths from `event.dataTransfer.files` using Electron's `file.path` property. Deduplicate. Hide overlay. Call `setImportModalOpen(true)` with the extracted paths.

To avoid interference: the drag overlay ONLY activates in Library view and ONLY when the ImportModal is not already open.

### App.css — Drag Overlay

```css
/* Dimming overlay */
.drag-overlay {
  position: absolute;
  inset: 0;
  background: rgba(0, 0, 0, 0.35);
  z-index: 50;
  display: flex;
  align-items: center;
  justify-content: center;
  animation: fadeIn 0.15s ease;
  pointer-events: none;
}

/* Centered drop zone */
.drag-zone {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 12px;
  padding: 48px 64px;
  border: 3px dashed var(--gl-orange);
  border-radius: 12px;
  background: var(--gl-orange-light);
  animation: slideUp 0.2s ease;
}

.drag-zone-icon {
  color: var(--gl-orange);
}

.drag-zone-title {
  font-size: 16px;
  font-weight: 600;
  color: var(--gl-orange);
}

.drag-zone-hint {
  font-size: 11px;
  color: var(--gl-text-secondary);
}
```

### ImportModal.jsx — initialPaths Prop

New prop: `initialPaths` (optional array of strings).

Move the auto-start logic from the existing `useEffect` to accept both entry points:

- If `initialPaths` is provided: skip the dialog picker. For each path, determine file vs directory:
  - **Directory paths** — Call `window.freeplayer.scanDirectory(dirPath)` to get all audio files within.
  - **File paths** — Add directly if the extension is a supported audio format (`.mp3`, `.flac`, `.wav`, `.ogg`, `.m4a`, `.aac`, `.wma`, `.opus`, `.aiff`, `.ape`).
  - **Deduplicate** the combined list.
  - Set `sourceDir` to the common parent or first path, `step` to `confirm`, and `files` to the result.
- If `initialPaths` is NOT provided: existing behavior (call `handleSelectSource()` which opens the native dialog).

Also set `libraryDir` from the existing setting (read via `window.freeplayer.getSetting('library_dir')` or from the `music:import` IPC).

## Data Flow

```
Drag files into Library view
    ↓
App.jsx extracts paths from DataTransfer
    ↓
Sets importModalOpen=true, passes initialPaths to ImportModal
    ↓
ImportModal.useEffect detects initialPaths
    ↓
For each path: if dir → scanDirectory, if file → validate extension
    ↓
Deduplicate combined file list
    ↓
Set step = 'confirm', files = [...]
    ↓
User reviews files in existing ImportModal confirm screen
    ↓
Click Import → calls importFiles() with library dir + files
    ↓
Import proceeds using current import_mode setting (copy or symlink)
```

## Error Handling

- **No audio files found** in dragged content → show confirm screen with 0 files, "Import 0 Files" button disabled or message "No supported audio files found in the dropped content."
- **Drag during active import** → ignored (`dragOver` state check guards against `importModalOpen`).
- **Drag on non-Library views** → ignored (view check in handler).
- **Scan errors on directory paths** — `scanDirectory` can throw; catch per-path, skip, continue with valid paths.

## Edge Cases

- **Mix of files and folders** — each path is checked individually, results merged.
- **Duplicate paths** — deduplicate via `Set` on the file list.
- **Very large file sets** — same scanning spinner UX as existing import.
- **Electron path availability** — `file.path` is available in Electron renderer even with `contextIsolation: true` because the preload exposes file system access.

## Testing

- Drag a folder of audio files → modal opens, files scanned, confirm shown.
- Drag individual audio files → same flow.
- Drag non-audio files → modal opens with 0 files, helpful message shown.
- Drag while already importing → ignored.
- Drag on Now Playing / Stats / Settings views → no overlay, no effect.
- Verify import uses the current `import_mode` setting (copy vs symlink).
- Verify the overlay appears on dragenter and disappears on dragleave.
- Test drag of mixed content (files + folders).

## Design System Notes

- Uses existing `--gl-orange`, `--gl-orange-light`, `--gl-text-secondary` variables.
- Uses existing `fadeIn` and `slideUp` keyframe animations.
- Overlay z-index: 50 (below modal's 200, above content).
