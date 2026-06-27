# Tray Residency — Design Spec

**Date:** 2026-06-27  
**Status:** Approved

## Goal

Prevent accidental closure of FreePlayer by minimizing the window to the system tray when the user clicks the close button. If the feature is disabled, the app quits normally.

## Behavior

- **Default:** `tray_enabled = true` — closing the window hides it to the system tray. The app continues running and music keeps playing.
- **When disabled:** standard behavior — closing the window quits the app (macOS: app stays in dock but window closes).
- **Tray right-click menu:** Show Window / Play-Pause / Previous Track / Next Track / separator / Quit FreePlayer.
- **Play-Pause menu label** dynamically reflects current playback state.
- **Double-click tray icon:** restores/show the window.

## Files Changed

| File | Change |
|------|--------|
| `electron/main.js` | Tray creation, close interception, IPC channels for playback state and control |
| `electron/preload.js` | Bridge methods: `sendPlaybackState`, `onPlaybackControl` |
| `src/components/Settings.jsx` | Toggle switch for "Close to tray" preference |
| `src/hooks/usePlayback.js` | Push playback state changes to main process via IPC |

## Architecture

```
┌─ Settings Toggle ────────────────────────────────────┐
│  music:set-setting('tray_enabled', bool) ────────────→ stored in DB │
└──────────────────────────────────────────────────────┘

┌─ usePlayback (renderer) ─────────────────────────────┐
│  isPlaying changes ─── IPC ───→ main updates tray    │
│                              menu label: Play/Pause  │
└──────────────────────────────────────────────────────┘

┌─ Tray menu click ───────────────────────────────────┐
│  Play/Pause / Prev / Next ── webContents.send ──────→ renderer acts │
│  Show Window ── mainWindow.show() + focus            │
│  Quit ── force quit (skip tray)                      │
└──────────────────────────────────────────────────────┘

┌─ Window close event ────────────────────────────────┐
│  if tray_enabled → event.preventDefault() + hide()  │
│  else → destroy tray + app.quit() (or keep alive on │
│         macOS per existing behavior)                 │
└──────────────────────────────────────────────────────┘
```

## Main Process Details

### Tray Icon

- Use `nativeImage.createFromDataURL()` with an inline base64-encoded 16×16 PNG of a musical note.
- No external asset file needed.

### Close Interception

```js
mainWindow.on('close', (event) => {
  if (getSetting('tray_enabled', true)) {
    event.preventDefault();
    mainWindow.hide();
  } else {
    tray?.destroy();
    tray = null;
  }
});
```

On actual quit (via tray menu "Quit" or cmd+q): explicitly set a flag or call `app.exit(0)` to bypass the close handler.

### IPC Channels (new)

| Channel | Direction | Purpose |
|---------|-----------|---------|
| `playback:state-changed` | renderer → main | `{ isPlaying: boolean }` |
| `playback:control` | main → renderer | `{ action: 'playpause' \| 'next' \| 'previous' }` |

The `playback:control` event reuses the same renderer handlers already wired for media keys (`globalShortcut` → `webContents.send('media-key', ...)`).

### Tray Menu Structure

```
Show Window          → mainWindow.show() + focus
─────────────────────
Play (or Pause)      → webContents.send('playback:control', { action: 'playpause' })
Previous Track       → webContents.send('playback:control', { action: 'previous' })
Next Track           → webContents.send('playback:control', { action: 'next' })
─────────────────────
Quit FreePlayer      → app.exit(0)
```

The Play/Pause label updates dynamically: when `playback:state-changed` arrives with `isPlaying: true`, label becomes "Pause"; when `false`, label becomes "Play".

## Renderer Details

### Settings Toggle

In `Settings.jsx`, add a checkbox:

```jsx
<label>
  <input
    type="checkbox"
    checked={trayEnabled}
    onChange={(e) => {
      setTrayEnabled(e.target.checked);
      window.electronAPI.setSetting('tray_enabled', e.target.checked);
    }}
  />
  关闭窗口时最小化到系统托盘
</label>
```

On mount, read `tray_enabled` from `window.electronAPI.getSetting('tray_enabled')`, defaulting to `true`.

### Playback State Push

In `usePlayback.js`, inside the effect that watches `isPlaying`:

```js
useEffect(() => {
  window.electronAPI?.sendPlaybackState(isPlaying);
}, [isPlaying]);
```

### Preload Bridge

```js
sendPlaybackState: (isPlaying) => ipcRenderer.send('playback:state-changed', { isPlaying }),
onPlaybackControl: (callback) => ipcRenderer.on('playback:control', (_event, data) => callback(data)),
setSetting: (key, value) => ipcRenderer.invoke('music:set-setting', { key, value }),
getSetting: (key) => ipcRenderer.invoke('music:get-setting', key),
```

Note: `setSetting` and `getSetting` likely already exist in preload. Only add `sendPlaybackState` and `onPlaybackControl`.

## Edge Cases

1. **macOS cmd+q** — maps to `app.quit()`, should work regardless of tray setting (force quit).
2. **macOS dock close** — the `close` event on the window is intercepted normally; tray behavior applies.
3. **Tray disabled while window hidden** — if the user disables the setting while the window is in the tray, they need a way to restore it. The tray icon persists until the user explicitly quits. Disabling the setting mid-session doesn't immediately destroy the tray.
4. **Multiple windows** — FreePlayer has only one window (`mainWindow`). No multi-window handling needed.

## Testing

- Unit: verify `tray_enabled` setting defaults to `true`
- Manual: close window → verify it hides to tray, music continues playing
- Manual: click "Show Window" in tray menu → window reappears
- Manual: disable setting → close window → app quits normally
- Manual: tray menu play/pause/prev/next controls work
- Manual: macOS — cmd+q always quits
