# FreePlayer (Android)

Lokaler Musikplayer. Kein Netzwerk, kein Login, keine Datensammlung. Deine Musik bleibt auf deinem Gerät, in deiner eigenen Ordnerstruktur.

> Eine macOS-Implementierung (SwiftUI) liegt im `Swift`-Branch; die alte Web-Version im `master`-Branch.

## Unterstützte Formate

MP3, FLAC, WAV, OGG, M4A, AAC, OPUS, MP4 (abhängig vom System-Decoder)

## Funktionen

- **Import & Teilen**: Ordner über den System-Dateiauswähler importieren; von anderen Apps (WeChat, Dateimanager…) geteilte Audiodateien per „Mit FreePlayer öffnen" mit einem Tipp importieren
- **Bibliothek**: automatische Metadaten-Extraktion (Titel, Künstler, Album, Jahr, Genre, Titelnummer, Bitrate, Abtastrate, Kanäle), gespeichert in Künstler/Album-Struktur mit eingebettetem Cover
- **Hörstatistik**: jede Wiedergabe wird erfasst (Start/Ende, Dauer, Prozent) — Gesamtzeit, Anzahl, Top-10 Titel/Künstler, Tagesstatistik der letzten 30 Tage
- **Wiedergabelisten**: erstellen/umbenennen/löschen, einzeln oder gesammelt hinzufügen, Liste bearbeiten
- **LRC-Texte**: automatische Erkennung oder manuelle Zuordnung von .lrc-Dateien; Kodierungs-Fallback UTF-8 → GB18030 → Shift_JIS
- **ReplayGain**: automatische Lautstärke-Anpassung
- **Visualizer**: Oszilloskop + Spektrum + Spektrogramm-Wasserfall
- **Immersiv-Modus**: Vollbild-Wiedergabe ohne Ablenkung
- **Medientasten / Benachrichtigung**: Steuerung über die Vordergrunddienst-Benachrichtigung; funktioniert im Sperrbildschirm und mit Bluetooth-Kopfhörern

## Build

Erfordert Android SDK (compileSdk 37, minSdk 26).

```bash
cd Android
./gradlew :app:assembleDebug     # Debug-APK
./gradlew :app:assembleRelease   # Release-APK (Signierungskonfiguration nötig)
./gradlew :app:testDebugUnitTest # Unit-Tests
```

Release-Signierung: `freeplayer-release.jks` und `keystore.properties` (storeFile/storePassword/keyAlias/keyPassword) nach `Android/` legen; die Datei ist git-ignoriert und wird nie committet.

## Datenbank

SQLite im privaten App-Datenverzeichnis:

- tracks — Titel (replaygain, lrc_path, …)
- play_history — Wiedergabeverlauf
- playlists / playlist_tracks — Wiedergabelisten und Titel
- settings — Schlüssel-Wert-Einstellungen

## Lizenz

GPL v3 — siehe LICENSE.

---

## Language / 语言

[English](README.en.md) · [简体中文](README.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Italiano](README.it.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)
