# FreePlayer (Android)

A local music player. No network, no login, no data collection. Your music stays on your device, organized with your own folder structure.

> A macOS (SwiftUI) implementation is available on the `Swift` branch; the legacy web version lives on `master`.

## Supported formats

MP3, FLAC, WAV, OGG, M4A, AAC, OPUS, MP4 (limited by system decoders)

## Features

- **Import & share**: import folders via the system file picker; audio shared from other apps (WeChat, file managers…) can be imported with "Open with FreePlayer" in one tap
- **Library**: metadata auto-extraction (title, artist, album, year, genre, track number, bitrate, sample rate, channels), stored in Artist/Album structure with embedded cover art
- **Play statistics**: every playback is recorded (start/end, duration, play percentage) — total time, play count, Top 10 tracks/artists, 30-day daily stats
- **Playlists**: create/rename/delete, add single or batch tracks, edit track list
- **LRC lyrics**: auto-detect or manually associate .lrc files; encoding fallback UTF-8 → GB18030 → Shift_JIS
- **ReplayGain**: automatic volume adjustment
- **Visualizer**: oscilloscope + spectrum + spectrogram waterfall modes
- **Immersive mode**: fullscreen distraction-free playback
- **Media keys / notification**: foreground-service playback controls; works from lock screen and Bluetooth headsets

## Build

Requires Android SDK (compileSdk 37, minSdk 26).

```bash
cd Android
./gradlew :app:assembleDebug     # debug APK
./gradlew :app:assembleRelease   # release APK (needs signing config)
./gradlew :app:testDebugUnitTest # unit tests
```

Release signing: place `freeplayer-release.jks` and `keystore.properties` (storeFile/storePassword/keyAlias/keyPassword) inside `Android/`; the file is git-ignored and never committed.

## Database

SQLite in the app-private data directory:
- tracks — tracks (replaygain, lrc_path, …)
- play_history — play history
- playlists / playlist_tracks — playlists and their tracks
- settings — key-value settings

## License

GPL v3 — see LICENSE.

---

## Language / 语言

[English](README.en.md) · [简体中文](README.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Italiano](README.it.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)
