# FreePlayer (Android)

Lecteur de musique local. Pas de réseau, pas de compte, aucune collecte de données. Votre musique reste sur votre appareil, organisée selon vos propres dossiers.

> Une implémentation macOS (SwiftUI) est disponible sur la branche `Swift`; l'ancienne version web est sur `master`.

## Formats pris en charge

MP3, FLAC, WAV, OGG, M4A, AAC, OPUS, MP4 (selon les décodeurs système)

## Fonctionnalités

- **Import & partage** : importez des dossiers via le sélecteur de fichiers; l'audio partagé depuis d'autres apps (WeChat, gestionnaires de fichiers…) s'importe en un geste via « Ouvrir avec FreePlayer »
- **Bibliothèque** : extraction automatique des métadonnées (titre, artiste, album, année, genre, piste, débit, fréquence, canaux), rangée par artiste/album avec pochettes intégrées
- **Statistiques d'écoute** : chaque lecture est enregistrée (début/fin, durée, pourcentage) — temps total, compteur, Top 10 titres/artistes, statistiques quotidiennes sur 30 jours
- **Listes de lecture** : créer/renommer/supprimer, ajout simple ou groupé, édition de la liste
- **Paroles LRC** : détection automatique ou association manuelle de fichiers .lrc; encodages UTF-8 → GB18030 → Shift_JIS
- **ReplayGain** : ajustement automatique du volume
- **Visualiseur** : oscilloscope + spectre + spectrogramme en cascade
- **Mode immersif** : lecture plein écran sans distraction
- **Touches média / notification** : contrôles dans la notification du service avant-plan; fonctionne en veille et au casque Bluetooth

## Compilation

Nécessite le SDK Android (compileSdk 37, minSdk 26).

```bash
cd Android
./gradlew :app:assembleDebug     # APK debug
./gradlew :app:assembleRelease   # APK release (nécessite la config de signature)
./gradlew :app:testDebugUnitTest # tests unitaires
```

Signature de release : placez `freeplayer-release.jks` et `keystore.properties` (storeFile/storePassword/keyAlias/keyPassword) dans `Android/`; ce fichier est ignoré par git et jamais committé.

## Base de données

SQLite, dans le répertoire de données privé de l'application :

- tracks — pistes (replaygain, lrc_path, …)
- play_history — historique d'écoute
- playlists / playlist_tracks — listes et leurs pistes
- settings — réglages clé-valeur

## Licence

GPL v3 — voir LICENSE.

---

## Language / 语言

[English](README.en.md) · [简体中文](README.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Italiano](README.it.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)
