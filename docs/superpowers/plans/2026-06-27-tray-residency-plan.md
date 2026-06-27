# Tray Residency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add system tray residency so clicking the close button hides FreePlayer to the tray instead of quitting. A Settings toggle controls this behavior (default: enabled).

**Architecture:** Tray lifecycle, close interception, and menu are managed in the Electron main process (`electron/main.js`). The renderer pushes playback state to main via IPC so the tray menu can show the correct "Play"/"Pause" label. Tray menu clicks send control commands back to the renderer via `webContents.send`, reusing the existing media-key handler pattern.

**Tech Stack:** Electron (Tray, Menu, nativeImage), React (Settings toggle), IPC (contextBridge)

## Global Constraints

- `tray_enabled` setting defaults to `true` (first install = tray on)
- Tray icon: inline base64 PNG musical note, 16×16, no external asset file
- Tray right-click menu: Show Window / Play-Pause / Previous Track / Next Track / separator / Quit FreePlayer
- Play-Pause label dynamically reflects `isPlaying` state
- Double-click tray icon: restores/shows window
- macOS cmd+q: always quits (force quit, bypasses tray)
- Setting toggle placed in Playback section of Settings page

---

### Task 1: Add tray logic to Electron main process

**Files:**
- Modify: `electron/main.js`

**Interfaces:**
- Consumes: (none — first task)
- Produces:
  - Tray created with context menu
  - `mainWindow.on('close')` intercepted — hides window when `tray_enabled` is true
  - IPC handler `playback:state-changed` updates tray menu Play/Pause label
  - Tray menu actions sent to renderer via `webContents.send('playback:control', { action })`

- [ ] **Step 1: Add Tray and Menu to Electron imports**

In `electron/main.js`, line 1, update the destructured require:

```js
const { app, BrowserWindow, Tray, Menu, nativeImage, ipcMain, dialog, protocol, globalShortcut } = require('electron');
```

- [ ] **Step 2: Add state variables and tray icon generator**

Add after the `let mainWindow;` line (~line 37), before `createWindow`:

```js
let mainWindow;
let tray = null;
let isQuitting = false;

// Generate a 16x16 tray icon programmatically — a simple musical note shape.
// No external asset file needed. Replace with a custom .png if desired.
function createTrayIcon() {
  // 16x16 musical note pixel art: '#' = white, '.' = transparent
  const note = [
    '................',
    '................',
    '.....##.........',
    '....#.#.........',
    '....##..........',
    '....##..........',
    '....#.#.........',
    '....##..........',
    '....##..........',
    '....##..........',
    '....##..........',
    '...####.........',
    '...##.##........',
    '..##..##........',
    '................',
    '................',
  ];
  const size = 16;
  const buffer = Buffer.alloc(size * size * 4);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const idx = (y * size + x) * 4;
      if (note[y][x] === '#') {
        buffer[idx] = 0xff;     // R
        buffer[idx + 1] = 0xff; // G
        buffer[idx + 2] = 0xff; // B
        buffer[idx + 3] = 0xff; // A
      } else {
        buffer[idx] = 0x1f;     // R
        buffer[idx + 1] = 0x1f; // G
        buffer[idx + 2] = 0x23; // B (background #1f1f23)
        buffer[idx + 3] = 0xff; // A
      }
    }
  }
  return nativeImage.createFromBuffer(buffer, { width: size, height: size });
}
```

- [ ] **Step 3: Create the tray with context menu**

Add a new function `createTray()` after `createWindow()`:

```js
function createTray() {
  const icon = createTrayIcon();
  tray = new Tray(icon);
  tray.setToolTip('FreePlayer');

  const updateMenu = (isPlaying) => {
    const contextMenu = Menu.buildFromTemplate([
      {
        label: 'Show Window',
        click: () => {
          mainWindow.show();
          mainWindow.focus();
        },
      },
      { type: 'separator' },
      {
        label: isPlaying ? 'Pause' : 'Play',
        click: () => {
          mainWindow.webContents.send('playback:control', { action: 'playpause' });
        },
      },
      {
        label: 'Previous Track',
        click: () => {
          mainWindow.webContents.send('playback:control', { action: 'previous' });
        },
      },
      {
        label: 'Next Track',
        click: () => {
          mainWindow.webContents.send('playback:control', { action: 'next' });
        },
      },
      { type: 'separator' },
      {
        label: 'Quit FreePlayer',
        click: () => {
          isQuitting = true;
          app.quit();
        },
      },
    ]);
    tray.setContextMenu(contextMenu);
  };

  // Initial menu (assume paused)
  updateMenu(false);

  // Double-click tray icon → show window
  tray.on('double-click', () => {
    mainWindow.show();
    mainWindow.focus();
  });

  // Store updateMenu for use in IPC handler
  tray._updateMenu = updateMenu;
}
```

- [ ] **Step 4: Add close interception to `createWindow`**

Inside `createWindow()`, after the window is created (after the if/else block for loading URL), add:

```js
  // Intercept close — hide to tray if tray_enabled, otherwise quit
  mainWindow.on('close', (event) => {
    if (!isQuitting) {
      const trayEnabled = getSetting('tray_enabled', true);
      if (trayEnabled) {
        event.preventDefault();
        mainWindow.hide();
        return;
      }
    }
    // Clean up tray when actually closing
    if (tray) {
      tray.destroy();
      tray = null;
    }
  });
```

- [ ] **Step 5: Call `createTray()` after `createWindow()` in app startup**

In the `app.whenReady()` block (~line 554), add `createTray();` after `createWindow();`:

```js
  createWindow();
  createTray();
```

- [ ] **Step 6: Add `playback:state-changed` IPC handler**

In the `setupIPC()` function, add before the closing `}` of the function:

```js
  // Playback state from renderer → update tray menu label
  ipcMain.on('playback:state-changed', (_event, { isPlaying }) => {
    if (tray && tray._updateMenu) {
      tray._updateMenu(isPlaying);
    }
  });
```

- [ ] **Step 7: Update `app.on('window-all-closed')` to destroy tray**

Replace the existing handler (~line 583):

```js
app.on('window-all-closed', () => {
  globalShortcut.unregisterAll();
  if (tray) {
    tray.destroy();
    tray = null;
  }
  closeDatabase();
  if (process.platform !== 'darwin') app.quit();
});
```

- [ ] **Step 8: Verify linting**

Run:

```bash
cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer && node -e "require('./electron/main.js')" 2>&1 | head -5
```

Expected: No syntax errors (may show "app.whenReady is not a function" in plain Node — that's fine, we're checking syntax only).

- [ ] **Step 9: Commit**

```bash
cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer
git add electron/main.js
git commit -m "feat: add system tray with close-to-tray and playback controls"
```

---

### Task 2: Add preload bridge methods

**Files:**
- Modify: `electron/preload.js`

**Interfaces:**
- Consumes: (none — independent of Task 1)
- Produces:
  - `window.freeplayer.sendPlaybackState(isPlaying)` — calls `ipcRenderer.send('playback:state-changed', { isPlaying })`
  - `window.freeplayer.onPlaybackControl(callback)` — listens for `playback:control` from main, calls `callback({ action })`

- [ ] **Step 1: Add the two bridge methods**

In `electron/preload.js`, add inside the `contextBridge.exposeInMainWorld('freeplayer', {` object, before the closing `});` on line 56:

```js
  // Tray playback state push
  sendPlaybackState: (isPlaying) => ipcRenderer.send('playback:state-changed', { isPlaying }),

  // Tray menu control listener
  onPlaybackControl: (callback) => {
    ipcRenderer.on('playback:control', (_event, data) => callback(data));
  },
```

- [ ] **Step 2: Commit**

```bash
cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer
git add electron/preload.js
git commit -m "feat: add preload bridge for tray playback state and control"
```

---

### Task 3: Push playback state from renderer to main

**Files:**
- Modify: `src/hooks/usePlayback.js`

**Interfaces:**
- Consumes: `window.freeplayer.sendPlaybackState(isPlaying)` (from Task 2)
- Produces: Playback state pushed to main process whenever `isPlaying` changes

- [ ] **Step 1: Add playback state push effect**

In `src/hooks/usePlayback.js`, find the existing media key effect at line ~197. Add this new effect **before** the media key effect, after the unmount cleanup effect:

```js
  // Push playback state to main process for tray menu
  useEffect(() => {
    window.freeplayer?.sendPlaybackState(state.isPlaying);
  }, [state.isPlaying]);
```

Note: `state` is already available from `usePlayer()` at the top of the hook (line 15). The `?.` guards against the case where `window.freeplayer` is not yet available (extremely rare since preload runs first, but defensive).

- [ ] **Step 2: Commit**

```bash
cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer
git add src/hooks/usePlayback.js
git commit -m "feat: push playback state to main for tray menu label"
```

---

### Task 4: Handle tray control commands in App

**Files:**
- Modify: `src/App.jsx`

**Interfaces:**
- Consumes: `window.freeplayer.onPlaybackControl` (from Task 2), `togglePlayPause`, `handleNext`, `handlePrev` (from `usePlayback`)
- Produces: Tray menu play/pause/prev/next commands dispatched to playback handlers

- [ ] **Step 1: Add tray control listener effect**

In `src/App.jsx`, after the keyboard shortcuts effect (~line 59) and before the drag-and-drop handlers, add:

```js
  // Tray menu playback control
  React.useEffect(() => {
    if (!window.freeplayer?.onPlaybackControl) return;
    const handler = ({ action }) => {
      switch (action) {
        case 'playpause': togglePlayPause(); break;
        case 'next': handleNext(); break;
        case 'previous': handlePrev(); break;
      }
    };
    window.freeplayer.onPlaybackControl(handler);
  }, [togglePlayPause, handleNext, handlePrev]);
```

- [ ] **Step 2: Commit**

```bash
cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer
git add src/App.jsx
git commit -m "feat: handle tray menu playback control commands"
```

---

### Task 5: Add tray setting toggle to Settings page

**Files:**
- Modify: `src/components/Settings.jsx`

**Interfaces:**
- Consumes: `window.freeplayer.getSetting('tray_enabled')`, `window.freeplayer.setSetting({ key: 'tray_enabled', value })`
- Produces: Toggle switch in Settings UI, persisted to DB

- [ ] **Step 1: Add local state and load on mount**

At the top of the `Settings` component function, after the `showResetConfirm` state line (~line 14):

```js
  const [trayEnabled, setTrayEnabled] = useState(true); // default true
```

Add a useEffect to load the saved value:

```js
  React.useEffect(() => {
    window.freeplayer.getSetting('tray_enabled').then(val => {
      if (val !== undefined && val !== null) {
        setTrayEnabled(val === true || val === 'true' || val === 1 || val === '1');
      }
    }).catch(() => {});
  }, []);
```

- [ ] **Step 2: Add tray toggle UI in the Playback section**

Inside the Playback settings section (`<div className="settings-section">` that contains the Playback header), after the Default Visualizer row (after its closing `</div>`), add:

```jsx
          <div className="playback-row">
            <div className="playback-label-group">
              <span className="playback-label">Close to Tray</span>
              <span className="playback-hint">Minimize to system tray instead of quitting when closing the window</span>
            </div>
            <label className="toggle-switch">
              <input
                type="checkbox"
                checked={trayEnabled}
                onChange={(e) => {
                  const val = e.target.checked;
                  setTrayEnabled(val);
                  window.freeplayer.setSetting({ key: 'tray_enabled', value: val });
                }}
              />
              <span className="toggle-slider" />
            </label>
          </div>
```

- [ ] **Step 3: Add toggle CSS styles**

In `src/App.css`, add at the end:

```css
/* Toggle Switch */
.toggle-switch {
  position: relative;
  display: inline-block;
  width: 44px;
  height: 24px;
  flex-shrink: 0;
}
.toggle-switch input {
  opacity: 0;
  width: 0;
  height: 0;
}
.toggle-slider {
  position: absolute;
  cursor: pointer;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background-color: rgba(255,255,255,0.15);
  border-radius: 12px;
  transition: background-color 0.2s;
}
.toggle-slider::before {
  content: "";
  position: absolute;
  height: 18px;
  width: 18px;
  left: 3px;
  bottom: 3px;
  background-color: white;
  border-radius: 50%;
  transition: transform 0.2s;
}
.toggle-switch input:checked + .toggle-slider {
  background-color: #6366f1;
}
.toggle-switch input:checked + .toggle-slider::before {
  transform: translateX(20px);
}
```

- [ ] **Step 4: Commit**

```bash
cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer
git add src/components/Settings.jsx src/App.css
git commit -m "feat: add close-to-tray toggle in Settings"
```

---

### Task 6: Integration verification

**Files:**
- No file changes — verification only

- [ ] **Step 1: Start the dev app**

```bash
cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer && npm run dev
```

- [ ] **Step 2: Manual verification checklist**

| # | Test | Expected |
|---|------|----------|
| 1 | App starts normally | Window appears, tray icon visible in system tray |
| 2 | Right-click tray icon | Context menu shows: Show Window / — / Play / Previous Track / Next Track / — / Quit FreePlayer |
| 3 | Click "Show Window" | Window comes to front (no-op if already visible) |
| 4 | Play a track, check tray menu label | Menu item changes from "Play" to "Pause" |
| 5 | Click "Pause" in tray menu | Playback pauses, menu label changes back to "Play" |
| 6 | Click "Next Track" in tray menu | Skips to next track |
| 7 | Click "Previous Track" in tray menu | Goes to previous track |
| 8 | Close window (click red X) | Window hides, music continues playing, tray icon remains |
| 9 | Double-click tray icon | Window reappears |
| 10 | Toggle "Close to Tray" off in Settings | Setting persists |
| 11 | Close window with setting off | App quits normally (no tray icon) |
| 12 | Re-enable "Close to Tray", close window | Window hides to tray again |
| 13 | Click "Quit FreePlayer" in tray menu | App exits completely |
| 14 | macOS: press Cmd+Q | App quits completely |

- [ ] **Step 3: If any check fails, fix and re-verify**

- [ ] **Step 4: Commit any fixes**

```bash
cd /Users/eason/Documents/Coding/hi-zcy/FreePlayer
git add -A
git commit -m "fix: tray residency integration fixes"
```
