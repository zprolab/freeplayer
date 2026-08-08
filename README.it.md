# FreePlayer (Android)

Lettore musicale locale. Nessuna rete, nessun accesso, nessuna raccolta dati. La tua musica resta sul tuo dispositivo, con la tua struttura di cartelle.

> Un'implementazione macOS (SwiftUI) è disponibile sul branch `Swift`; la vecchia versione web è su `master`.

## Formati supportati

MP3, FLAC, WAV, OGG, M4A, AAC, OPUS, MP4 (a seconda dei decoder di sistema)

## Funzionalità

- **Importazione e condivisione**: importa cartelle tramite il selettore file di sistema; l'audio condiviso da altre app (WeChat, gestori file…) si importa con un tocco tramite «Apri con FreePlayer»
- **Libreria**: estrazione automatica dei metadati (titolo, artista, album, anno, genere, traccia, bitrate, frequenza, canali), salvati in struttura Artista/Album con copertine incorporate
- **Statistiche di ascolto**: ogni riproduzione viene registrata (inizio/fine, durata, percentuale) — tempo totale, riproduzioni, Top 10 brani/artisti, statistiche giornaliere su 30 giorni
- **Playlist**: crea/rinomina/elimina, aggiunta singola o in blocco, modifica elenco
- **Testi LRC**: rilevamento automatico o associazione manuale dei file .lrc; codifiche UTF-8 → GB18030 → Shift_JIS
- **ReplayGain**: regolazione automatica del volume
- **Visualizzatore**: oscilloscopio + spettro + spettrogramma a cascata
- **Modalità immersiva**: riproduzione a schermo intero senza distrazioni
- **Tasti multimediali / notifica**: controlli nella notifica del servizio in primo piano; funziona su schermata di blocco e con cuffie Bluetooth

## Compilazione

Richiede Android SDK (compileSdk 37, minSdk 26).

```bash
cd Android
./gradlew :app:assembleDebug     # APK debug
./gradlew :app:assembleRelease   # APK release (richiede configurazione di firma)
./gradlew :app:testDebugUnitTest # test unitari
```

Firma di release: inserisci `freeplayer-release.jks` e `keystore.properties` (storeFile/storePassword/keyAlias/keyPassword) in `Android/`; il file è ignorato da git e mai committato.

## Database

SQLite, nella directory dati privata dell'app:

- tracks — brani (replaygain, lrc_path, …)
- play_history — cronologia di ascolto
- playlists / playlist_tracks — playlist e brani
- settings — impostazioni chiave-valore

## Licenza

GPL v3 — vedi LICENSE.

---

## Language / 语言

[English](README.en.md) · [简体中文](README.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Italiano](README.it.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)
