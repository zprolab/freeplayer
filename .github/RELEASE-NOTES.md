# FreePlayer 1.3.0

## Read this first if you used 1.2.0

Several things in 1.2.0 were **broken without telling you**. They failed silently:
the UI reported success, nothing appeared in any log, and the damage was only
visible if you went looking for it.

* **Editing a track's metadata never saved anything.** The edit dialog sent its
  fields nested under a `fields` key; the native side reads them flat. The column
  whitelist therefore matched nothing, the update returned `false` without
  raising, and the dialog closed as though it had saved. Every tag edit made in
  1.2.0 was discarded.
* **Creating a playlist filed your tracks under playlist #1.** The insert
  returned a success flag instead of the new row id, which serialised to `true`
  and was read as row id 1.
* **No plugin could run at all.** The host's `readFile` handed the plugin loader
  the file's text where it expected `{source, bytes}`, so every user plugin threw
  during its own module scan.
* **Saving an empty track list in the playlist editor deleted every track in it.**
* **Shuffle never shuffled** — enabling it kept playing the list in stored order.
* **Repeat-one recorded one ever-growing play per track.** An hour of looping a
  3-minute track was logged as a single 3600-second play rather than 20 plays.

The metadata editor also had no year validation: `parseInt('')` is `NaN`, which
serialised to null and **silently cleared** a year the track already had.

## Fixed

* The six defects above, plus an out-of-range year being stored as-is.
* The visualiser drew a 2048-sample analysis window into a 1024-sample buffer, so
  the waveform ran at double its true frequency; it now draws a per-column
  min/max envelope instead of one sample per pixel, which previously aliased
  anything above ~6.5 kHz into phantom low-frequency shapes.
* The frequency axis was linear while its labels sat at hand-picked positions, so
  the labels did not mark the frequencies they claimed. One log mapping now
  positions both the spectrogram and the labels.
* The spectrogram drew every row twice (3.3 ms/frame → 0.99 ms).
* Playlist and library edits that fail now report the failure instead of only
  writing to the console.

## Added

* **A shared design system** with one source of truth per value, replacing two
  competing token layers and 97 hardcoded colours. This is not only cosmetic: 23
  controls had no focus state, disabled buttons looked enabled, and five text
  tokens failed WCAG AA — the dimmest measured 2.05:1 against its background.
  One z-index scale also fixes dialogs that could open beneath other dialogs.
* **A playback engine** separated from React, with listening accounting measured
  from playback position rather than wall-clock. Two minutes spent paused used to
  be logged as two minutes of listening.
* **Selectable analysis quality** for the scope (Reactive / Balanced / Precise).
* Unused parts of the UI system deleted rather than left as dead weight.

## Smaller

* macOS app 1.3 MB → 1.0 MB (stripped binary, indexed-colour icons); download
  432 KB → 376 KB.
* The `.git` history no longer contains 104 MB of Android build output (a 40 MB
  `classes.dex`, debug and release APKs) plus twelve translated READMEs.
* ESLint runs in CI. It previously had no config, no dependency and no script,
  while the code carried `eslint-disable` comments asserting things nobody checked.

## Notes

* **Your library and listening history are untouched.** The database schema did
  not change and existing files carry over as-is.
* Statistics recorded by 1.2.0 keep their inflated durations; only new plays are
  measured correctly.
* macOS build is ad-hoc signed (not notarized): the first launch needs
  right-click → Open, or `xattr -d com.apple.quarantine <path>`.
* macOS 13+ / Apple Silicon only.
* The `.ipa` files are unsigned Release arm64 **device** builds — sideloadable
  via a jailbreak, Filza, or your own signing tool. iOS 17+.
