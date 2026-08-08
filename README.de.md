# FreePlayer (macOS)

Lokaler Musikplayer. Kein Netzwerk, kein Login, keine Datensammlung. Deine Musik bleibt auf deiner Festplatte, in deiner eigenen Ordnerstruktur.

Native macOS-Implementierung (SwiftUI + AppKit), ohne Drittanbieter-Laufzeit (nur System-Frameworks + SQLite).

## Unterstützte Formate

MP3, FLAC, WAV, OGG, M4A, AAC, AIFF (von AVFoundation dekodierbar)

## Funktionen

- **Import & Bibliothek** : automatische Metadaten-Extraktion (Titel, Künstler, Album, Jahr, Genre, Titelnummer, Bitrate, Abtastrate, Kanäle); Dateien werden in Künstler/Album-Struktur kopiert oder verlinkt (Modus wählbar in den Einstellungen)
- **Hörstatistik** : jede Sitzung wird in SQLite erfasst (Start/Ende, Dauer, Prozent) — Gesamtzeit, Wiedergaben, Top-10 Titel/Künstler, Tagesstatistik der letzten 30 Tage
- **Wiedergabelisten** : erstellen/umbenennen/löschen, einzeln oder gesammelt hinzufügen, bearbeiten
- **LRC-Texte** : automatische Erkennung oder manuelle Zuordnung von .lrc-Dateien; Kodierungs-Fallback UTF-8 → GB18030 → Shift_JIS
- **ReplayGain** : automatische Lautstärke-Anpassung über Tags
- **Cover** : eingebettete Artworks werden beim Import in den .covers-Ordner des Albums extrahiert
- **Medientasten / Menüleiste** : Systemtasten Play/Pause/Zurück/Weiter, Track-Info im Control Center, Steuerung über das Menüleisten-Symbol; Schließen versteckt das Fenster in der Menüleiste und spielt weiter
- **Visualizer** : Echtzeit-Oszilloskop + Spektrum oder Spektrogramm-Wasserfall
- **Immersiv-Modus** : Vollbild-Wiedergabe mit Karaoke-Texten und Schriftgrößen-Skalierung

## Build (macOS 13+, Xcode CLT / Swift 6)

```bash
cd macos
make            # Release-Build + FreePlayer.app-Paket
make run        # Debug-Build direkt ausführen
make run-app    # gepackte App öffnen
make test       # Unit-Tests ausführen
```

## Datenbank

SQLite unter ~/Library/Application Support/FreePlayer/library.db :

- tracks — Titel (replaygain, play_count, last_played_at, lrc_path, …)
- play_history — Wiedergabeverlauf
- playlists / playlist_tracks — Wiedergabelisten und Titel
- settings — Schlüssel-Wert-Einstellungen

## Lizenz

GPL v3 — siehe LICENSE.

---

## Language / 语言

[English](README.en.md) · [简体中文](README.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Italiano](README.it.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)
