# FreePlayer (macOS)

Reproductor de música local. Sin red, sin inicio de sesión, sin recopilación de datos. Tu música permanece en tu disco, con tu propia estructura de carpetas.

Implementación nativa para macOS (SwiftUI + AppKit), sin dependencias de terceros (solo frameworks del sistema + SQLite).

## Formatos admitidos

MP3, FLAC, WAV, OGG, M4A, AAC, AIFF (decodificables por AVFoundation)

## Características

- **Importar y biblioteca** : extracción automática de metadatos (título, artista, álbum, año, género, pista, bitrate, frecuencia, canales); archivos copiados o enlazados simbólicamente en estructura Artista/Álbum (modo configurable en Ajustes)
- **Estadísticas de escucha** : cada sesión se registra en SQLite (inicio/fin, duración, porcentaje) — tiempo total, reproducciones, Top 10 canciones/artistas, estadísticas diarias de 30 días
- **Listas de reproducción** : crear/renombrar/eliminar, añadir individual o en lote, editar
- **Letras LRC** : detección automática o asociación manual de archivos .lrc; codificaciones UTF-8 → GB18030 → Shift_JIS
- **ReplayGain** : ajuste automático del volumen según etiquetas
- **Portadas** : arte incrustado extraído al importar a la carpeta .covers del álbum
- **Teclas multimedia / barra de menú** : teclas del sistema reproducir/pausar/anterior/siguiente, información en Control Center, control desde el icono de la barra de menú; cerrar la ventana la oculta en la barra y sigue reproduciendo
- **Visualizador** : osciloscopio + espectro en tiempo real, o espectrograma en cascada
- **Modo inmersivo** : reproducción a pantalla completa con letras karaoke y escalado de fuente

## Compilación (macOS 13+, Xcode CLT / Swift 6)

```bash
cd macos
make            # build release + empaquetado FreePlayer.app
make run        # ejecutar directamente el build debug
make run-app    # abrir la app empaquetada
make test       # ejecutar pruebas unitarias
```

## Base de datos

SQLite en ~/Library/Application Support/FreePlayer/library.db:

- tracks — pistas (replaygain, play_count, last_played_at, lrc_path, …)
- play_history — historial de reproducción
- playlists / playlist_tracks — listas y pistas
- settings — ajustes clave-valor

## Licencia

GPL v3 — ver LICENSE.

---

## Language / 语言

[English](README.en.md) · [简体中文](README.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Italiano](README.it.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)
