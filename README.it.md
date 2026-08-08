# FreePlayer (macOS)

Lettore musicale locale. Nessuna rete, nessun accesso, nessuna raccolta dati. La tua musica resta sul tuo disco, con la tua struttura di cartelle.

Implementazione nativa macOS (SwiftUI + AppKit), senza dipendenze di terze parti (solo framework di sistema + SQLite).

## Formati supportati

MP3, FLAC, WAV, OGG, M4A, AAC, AIFF (decodificabili da AVFoundation)

## Funzionalità

- **Importazione e libreria** : estrazione automatica dei metadati (titolo, artista, album, anno, genere, traccia, bitrate, frequenza, canali); file copiati o collegati simbolicamente in struttura Artista/Album (modalità selezionabile nelle Impostazioni)
- **Statistiche di ascolto** : ogni sessione registrata in SQLite (inizio/fine, durata, percentuale) — tempo totale, riproduzioni, Top 10 brani/artisti, statistiche giornaliere su 30 giorni
- **Playlist** : crea/rinomina/elimina, aggiunta singola o in blocco, modifica
- **Testi LRC** : rilevamento automatico o associazione manuale di file .lrc; codifiche UTF-8 → GB18030 → Shift_JIS
- **ReplayGain** : regolazione automatica del volume tramite tag
- **Copertine** : artwork incorporato estratto all'importazione nella cartella .covers dell'album
- **Tasti multimediali / barra dei menu** : tasti di sistema play/pausa/precedente/successiva, info nel Control Center, controllo dall'icona della barra dei menu; chiudere la finestra la nasconde nella barra e continua la riproduzione
- **Visualizzatore** : oscilloscopio + spettro in tempo reale, o spettrogramma a cascata
- **Modalità immersiva** : riproduzione a schermo intero con testi karaoke e scala del font

## Compilazione (macOS 13+, Xcode CLT / Swift 6)

```bash
cd macos
make            # build release + pacchetto FreePlayer.app
make run        # eseguire direttamente la build debug
make run-app    # aprire l'app pacchettizzata
make test       # eseguire i test unitari
```

## Database

SQLite in ~/Library/Application Support/FreePlayer/library.db:

- tracks — brani (replaygain, play_count, last_played_at, lrc_path, …)
- play_history — cronologia di ascolto
- playlists / playlist_tracks — playlist e brani
- settings — impostazioni chiave-valore

## Licenza

GPL v3 — vedi LICENSE.

---

## Language / 语言

[English](README.en.md) · [简体中文](README.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Italiano](README.it.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)
