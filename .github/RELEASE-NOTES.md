# FreePlayer 1.3.1

## Read this first

**If you are on 1.3.0, this is not an urgent upgrade.** The tray play/pause icon
worked correctly in 1.3.0; it broke during development afterwards and **never
appeared in any released version**. 1.3.1 restores it. (The `setAppearance`
bridge had the same payload defect, but nothing has ever called it — fixed as
hardening, not as a user-visible repair.)

Two long-standing defects are worth the upgrade on their own:

* **Collapsing the sidebar did nothing.** The collapse button set a width
  variable that nothing read, so the sidebar stayed at its full 220px. The
  tablet breakpoint was dead for the same reason.
* **The track-count badge was unreadable.** The "N tracks" pill at the top of the
  Library rendered pale blue on a pale blue background — 1.78:1, well under the
  4.5:1 minimum. It measured as a contrast failure that the test suite could not
  see, because translucent backgrounds were being skipped rather than composited.

## Fixed

* **Tray play/pause state** (a regression, fixed before release): the bridge
  payload was nested twice, so the native side read a dictionary where it
  expected a number, the cast failed, and it fell back to `false` — the icon
  stayed on Play permanently and the in-app button never showed Pause.
* **Sidebar collapse** now narrows to the 72px icon rail, and the 768–1023px
  tablet width applies again.
* **Track-count badge** contrast is 5.99:1 (new `--fp-info-ink`), and the muted
  text in the sidebar was lifted from 3.62:1 to 5.12:1.
* **Plugin notice** background no longer uses a border token (4.31:1 → 4.64:1).
* The contrast suite now composites translucent surfaces and asserts that the
  pre-fix colours fail, so this class of defect cannot pass by being skipped.
* `sendPlaybackState` / `setAppearance` argument shapes are now guarded by
  `tests/bridgeContract.test.js`, which derives the convention from both the
  client and the bridge rather than documenting it.

## Internal structural changes

This release contains a large amount of work that does not change behaviour. It
is listed because it changes where things live, which matters if you read or
build this project.

* **One seam for the native bridge.** `window.freeplayer` was called directly
  from 22 files. It is now reached only through `src/core/client.js`, which also
  validates the payload shapes that had previously caused silent failures (a
  playlist id that arrived as `true`, a file read that returned text where the
  loader expected `{ source, bytes }`).
* **The module tree is grouped by feature.** The `hooks/`, `context/`, `data/`,
  `components/`, `audio/`, `player/` and `services/` directories are gone;
  features now live under `src/features/<domain>/` with their own `ui/`, and
  imports use `@/` aliases instead of relative paths.
* **Settings keys have a registry** (`src/core/settings.js`) instead of string
  literals spread across six files.
* **Library data logic** moved out of the component layer into
  `src/features/library/store.js`.
* **Contract tests** derive the playback engine's and media graph's interfaces
  from the consuming code, so replacing either one is a matter of implementing
  the members rather than editing call sites. No production code changed for
  this — it is a description of what exists, with the difference that it can now
  fail.
* **CI** runs ESLint (which had a config, a script and disable-comments, but no
  dependency — the gate was fictional) and the iOS XCTest suite, which had no CI
  at all.

## Notes

* **Your library and listening history are untouched.** The database schema did
  not change and existing files carry over as-is.
* macOS build is ad-hoc signed (not notarized): the first launch needs
  right-click → Open, or `xattr -d com.apple.quarantine <path>`.
* macOS 13+ / Apple Silicon only.
* The `.ipa` files are unsigned Release arm64 **device** builds — sideloadable
  via a jailbreak, Filza, or your own signing tool. iOS 17+.
