# FreePlayer (macOS)

Lecteur de musique local. Pas de réseau, pas de compte, aucune collecte de données. Votre musique reste sur votre disque, organisée selon vos propres dossiers.

Implémentation native macOS (SwiftUI + AppKit), sans dépendances tierces (frameworks système + SQLite uniquement).

## Formats pris en charge

MP3, FLAC, WAV, OGG, M4A, AAC, AIFF (décodables par AVFoundation)

## Fonctionnalités

- **Import & bibliothèque** : extraction automatique des métadonnées (titre, artiste, album, année, genre, piste, débit, fréquence, canaux); fichiers copiés ou liés symboliquement en structure Artiste/Album (mode au choix dans les réglages)
- **Statistiques d'écoute** : chaque session enregistrée dans SQLite (début/fin, durée, pourcentage) — temps total, lectures, Top 10 titres/artistes, stats quotidiennes sur 30 jours
- **Listes de lecture** : créer/renommer/supprimer, ajout simple ou groupé, édition
- **Paroles LRC** : détection automatique ou association manuelle de fichiers .lrc; encodages UTF-8 → GB18030 → Shift_JIS
- **ReplayGain** : ajustement automatique du volume selon les tags
- **Pochettes** : artwork intégré extrait à l'import dans le dossier .covers de l'album
- **Touches média / barre de menus** : touches système lecture/pause/précédent/suivant, infos dans le Control Center, contrôle par icône de menu; fermer la fenêtre la cache dans la barre de menus et continue la lecture
- **Visualiseur** : oscilloscope + spectre en temps réel, ou spectrogramme en cascade
- **Mode immersif** : lecture plein écran avec paroles karaoké et zoom de police

## Compilation (macOS 13+, Xcode CLT / Swift 6)

```bash
cd macos
make            # build release + paquet FreePlayer.app
make run        # exécuter directement le build debug
make run-app    # ouvrir l'app empaquetée
make test       # exécuter les tests unitaires
```

## Base de données

SQLite dans ~/Library/Application Support/FreePlayer/library.db :

- tracks — pistes (replaygain, play_count, last_played_at, lrc_path, …)
- play_history — historique d'écoute
- playlists / playlist_tracks — listes et pistes
- settings — réglages clé-valeur

## Licence

GPL v3 — voir LICENSE.

---

## Language / 语言

[English](README.en.md) · [简体中文](README.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Italiano](README.it.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)
