# Drag-and-Drop Import — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add drag-and-drop import to FreePlayer's Library view, reusing the existing ImportModal flow with a drag-triggered overlay.

**Architecture:** CSS overlay appears when drag enters Library view (dim background + centered orange dashed drop zone). App.jsx extracts file/folder paths from Electron's DataTransfer, passes them as `initialPaths` to ImportModal. ImportModal skips the dialog picker and scans paths directly into the confirm step.

**Tech Stack:** React 18, Electron 33, CSS animations

---

### Task 1: Add drag overlay CSS

**Files:**
- Modify: `src/App.css` (append at end)

- [ ] **Step 1: Append drag overlay CSS**

Read the end of `src/App.css`, then append:

```css
/* ═══════════════════════════════════════════════════════════════════
   Drag-and-Drop Overlay
   ═══════════════════════════════════════════════════════════════════ */

.content-area {
  position: relative;
}

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

Note: `.content-area { position: relative; }` adds `position: relative` to the existing `.content-area` rule. Find the existing `.content-area` block (around line 365) and add `position: relative;` inside it. The rest appends at the end of the file.

- [ ] **Step 2: Verify build**

Run: `cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer && npx vite build 2>&1 | tail -5`
Expected: Build succeeds.

---

### Task 2: Update ImportModal.jsx with initialPaths support

**Files:**
- Modify: `src/components/ImportModal.jsx`

- [ ] **Step 1: Add `initialPaths` prop and supported formats constant**

Change the component signature from:
```jsx
export default function ImportModal({ onClose, onComplete, importMode }) {
```
To:
```jsx
const SUPPORTED_FORMATS = ['.mp3', '.flac', '.wav', '.ogg', '.m4a', '.aac', '.wma', '.opus', '.aiff', '.ape'];

export default function ImportModal({ onClose, onComplete, importMode, initialPaths }) {
```

- [ ] **Step 2: Replace the auto-start useEffect to handle both entry points**

Find the existing auto-start `useEffect` (lines 67-72):
```jsx
  // Auto-start source selection — guard against double-invoke (e.g. StrictMode)
  useEffect(() => {
    if (!startedRef.current) {
      startedRef.current = true;
      handleSelectSource();
    }
  }, [handleSelectSource]);
```

Replace with:
```jsx
  // Auto-start — handle both dialog picker and drag-and-drop entry points
  useEffect(() => {
    if (!startedRef.current) {
      startedRef.current = true;
      if (initialPaths && initialPaths.length > 0) {
        handleInitialPaths(initialPaths);
      } else {
        handleSelectSource();
      }
    }
  }, [handleSelectSource, initialPaths]);

  const handleInitialPaths = useCallback(async (paths) => {
    try {
      // Get library directory
      let libDir = await window.freeplayer.getSetting('library_dir');
      if (!libDir) {
        // Fall back to import dialog to set library dir
        const result = await window.freeplayer.importDialog();
        if (result.canceled) {
          onComplete({ canceled: true });
          return;
        }
        libDir = result.libraryDir;
      }
      setLibraryDir(libDir);

      setScanning(true);
      setStep('scanning');

      // Process each path: directories get scanned, files get validated by extension
      const allFiles = [];
      for (const p of paths) {
        try {
          const stat = await window.freeplayer.scanDirectory(p);
          if (Array.isArray(stat)) {
            // It's a directory — scanDirectory returned file list
            allFiles.push(...stat);
          }
        } catch {
          // Not a directory or scan failed — treat as a file, validate extension
          const ext = p.slice(p.lastIndexOf('.')).toLowerCase();
          if (SUPPORTED_FORMATS.includes(ext)) {
            allFiles.push(p);
          }
        }
      }

      // Deduplicate
      const uniqueFiles = [...new Set(allFiles)];

      // Determine source display name
      const firstPath = paths[0];
      const sourceName = paths.length === 1
        ? firstPath
        : `${paths.length} paths (${firstPath}...)`;

      setSourceDir(sourceName);
      setFiles(uniqueFiles);
      setScanning(false);
      setStep('confirm');
    } catch (err) {
      console.error('Drag import scan error:', err);
      setError(err.message || 'Failed to process dropped files');
      setScanning(false);
      setStep('error');
    }
  }, [onComplete]);
```

The approach: scan each path — if `scanDirectory` returns an array, it was a directory. If it throws, treat as a file and validate by extension. This avoids needing a separate IPC to stat paths.

- [ ] **Step 3: Handle 0 files case in confirm step**

The existing confirm step already shows file count. When `files.length === 0`, the "Import 0 Files" button is still rendered. No changes needed — the user sees the count is 0 and can cancel. But let's make it explicit. Find the confirm footer button (line 244-246):

```jsx
              <button className="btn btn-primary" onClick={handleImport}>
                Import {files.length} Files
              </button>
```

No change needed — the existing confirm UI with `Import 0 Files` button and the file list showing empty is sufficient feedback. The user can click Cancel.

- [ ] **Step 4: Verify build**

Run: `cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer && npx vite build 2>&1 | tail -5`
Expected: Build succeeds.

---

### Task 3: Update App.jsx with drag handlers and initialPaths state

**Files:**
- Modify: `src/App.jsx`

- [ ] **Step 1: Add dragOver and initialPaths state**

After the existing state declarations (around line 38), add:

```js
  const [dragOver, setDragOver] = useState(false);
  const [initialPaths, setInitialPaths] = useState(null);
```

- [ ] **Step 2: Add drag event handlers**

After the `handleResetDatabase` function (around line 282), add:

```js
  const handleDragEnter = (e) => {
    if (view !== VIEWS.LIBRARY || importModalOpen) return;
    e.preventDefault();
    e.stopPropagation();
    setDragOver(true);
  };

  const handleDragOver = (e) => {
    if (view !== VIEWS.LIBRARY || importModalOpen) return;
    e.preventDefault();
    e.stopPropagation();
  };

  const handleDragLeave = (e) => {
    if (e.currentTarget === e.target) {
      setDragOver(false);
    }
  };

  const handleDrop = (e) => {
    e.preventDefault();
    e.stopPropagation();
    setDragOver(false);

    if (view !== VIEWS.LIBRARY || importModalOpen) return;

    const paths = [];
    const { files } = e.dataTransfer;
    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      if (file.path) {
        paths.push(file.path);
      }
    }

    if (paths.length > 0) {
      setInitialPaths(paths);
      setImportModalOpen(true);
    }
  };
```

- [ ] **Step 3: Wire handlers and overlay to content-area div**

Find the content-area div (line 345). Add drag handlers and overlay to it. Change:

```jsx
        <div className="content-area">
```

To:

```jsx
        <div
          className="content-area"
          onDragEnter={handleDragEnter}
          onDragOver={handleDragOver}
          onDragLeave={handleDragLeave}
          onDrop={handleDrop}
        >
          {dragOver && view === VIEWS.LIBRARY && !importModalOpen && (
            <div className="drag-overlay">
              <div className="drag-zone">
                <svg className="drag-zone-icon" width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round">
                  <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
                  <polyline points="17 8 12 3 7 8"/>
                  <line x1="12" y1="3" x2="12" y2="15"/>
                </svg>
                <span className="drag-zone-title">Drop to Import</span>
                <span className="drag-zone-hint">Audio files and folders supported</span>
              </div>
            </div>
          )}
```

- [ ] **Step 4: Pass initialPaths to ImportModal**

Find the `<ImportModal` usage (around line 432). Add `initialPaths` prop and clear it on close/complete:

```jsx
      {importModalOpen && (
        <ImportModal
          onClose={() => {
            setImportModalOpen(false);
            setInitialPaths(null);
          }}
          onComplete={(result) => {
            setInitialPaths(null);
            handleImportComplete(result);
          }}
          importMode={importMode}
          initialPaths={initialPaths}
        />
      )}
```

- [ ] **Step 5: Verify build**

Run: `cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer && npx vite build 2>&1`
Expected: Build succeeds with no errors.

---

### Task 4: Final integration verification

- [ ] **Step 1: Full build**

Run: `cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer && npx vite build 2>&1`
Expected: Build succeeds with no warnings or errors.

- [ ] **Step 2: Manual smoke test checklist**

Launch with `npm run dev` and verify:
- Drag a folder of audio files onto Library view → overlay appears → drop triggers ImportModal with files pre-scanned
- Drag individual audio files → same, files show in confirm list
- Drag non-audio files → modal opens showing 0 files
- Drag on Now Playing view → no overlay, no effect
- Drag on Settings view → no overlay, no effect
- Drag on Stats view → no overlay, no effect
- Overlay dims background and shows orange dashed drop zone
- Drag leaves Library area → overlay disappears
- Cancel on confirm screen → modal closes, no import
- Proceed with import → uses current import mode (copy/symlink) from Settings
- Clicking Import button still works as before (no initialPaths passed)
