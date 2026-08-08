# FreePlayer (macOS)

A local music player. No network, no login, no data collection. Your music stays on your disk, in your own folder structure.

Native macOS (SwiftUI + AppKit) implementation with no third-party runtime dependencies (system frameworks + SQLite only).

## Supported formats

MP3, FLAC, WAV, OGG, M4A, AAC, AIFF (decodable by AVFoundation)

## Features

- **Import & library**: metadata auto-extraction (title, artist, album, year, genre, track number, bitrate, sample rate, channels); files copied or symlinked into the library in Artist/Album structure (mode selectable in Settings)
- **Play statistics**: every session recorded in SQLite (start/end, duration, percentage) — total time, plays, Top 10 tracks/artists, 30-day daily stats
- **Playlists**: create/rename/delete, add single or batch tracks, edit list
- **LRC lyrics**: auto-detected or manually linked .lrc files; encoding fallback UTF-8 → GB18030 → Shift_JIS
- **ReplayGain**: automatic volume adjustment from file tags
- **Covers**: embedded artwork extracted on import into the album's .covers folder
- **Media keys / tray**: system play/pause/next/previous keys, Control Center track info, tray menu controls; closing the window hides to tray and keeps playing
- **Visualizer**: real-time oscilloscope + spectrum bars, or spectrogram waterfall
- **Immersive mode**: fullscreen distraction-free playback with karaoke lyrics and font scaling

## Build (macOS 13+, Xcode CLT / Swift 6)

```bash
cd macos
make            # release build + package FreePlayer.app
make run        # run the debug build directly
make run-app    # open the bundled app
make test       # run unit tests
```

## Database

SQLite at ~/Library/Application Support/FreePlayer/library.db:

- tracks — tracks (replaygain, play_count, last_played_at, lrc_path, …)
- play_history — play history
- playlists / playlist_tracks — playlists and their tracks
- settings — key-value settings

## License

GPL v3 — see LICENSE.

---

## Language / 语言

[English](README.en.md) · [简体中文](README.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Italiano](README.it.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)
