# FreePlayer (Android)

Reproductor de música local. Sin red, sin inicio de sesión, sin recopilación de datos. Tu música permanece en tu dispositivo, con tu propia estructura de carpetas.

> Hay una implementación para macOS (SwiftUI) en la rama `Swift`; la versión web antigua está en `master`.

## Formatos admitidos

MP3, FLAC, WAV, OGG, M4A, AAC, OPUS, MP4 (según los decodificadores del sistema)

## Características

- **Importar y compartir**: importa carpetas con el selector de archivos del sistema; el audio compartido desde otras apps (WeChat, gestores de archivos…) se importa con un toque mediante «Abrir con FreePlayer»
- **Biblioteca**: extracción automática de metadatos (título, artista, álbum, año, género, número de pista, bitrate, frecuencia de muestreo, canales), guardada en estructura Artista/Álbum con portadas integradas
- **Estadísticas de escucha**: cada reproducción queda registrada (inicio/fin, duración, porcentaje) — tiempo total, reproducciones, Top 10 canciones/artistas, estadísticas diarias de 30 días
- **Listas de reproducción**: crear/renombrar/eliminar, añadir individual o en lote, editar lista
- **Letras LRC**: detección automática o asociación manual de archivos .lrc; codificaciones UTF-8 → GB18030 → Shift_JIS
- **ReplayGain**: ajuste automático del volumen
- **Visualizador**: osciloscopio + espectro + espectrograma en cascada
- **Modo inmersivo**: reproducción a pantalla completa sin distracciones
- **Teclas multimedia / notificación**: controles en la notificación del servicio en primer plano; funciona en pantalla de bloqueo y con auriculares Bluetooth

## Compilación

Requiere Android SDK (compileSdk 37, minSdk 26).

```bash
cd Android
./gradlew :app:assembleDebug     # APK debug
./gradlew :app:assembleRelease   # APK release (requiere configuración de firma)
./gradlew :app:testDebugUnitTest # pruebas unitarias
```

Firma de release: coloca `freeplayer-release.jks` y `keystore.properties` (storeFile/storePassword/keyAlias/keyPassword) dentro de `Android/`; el archivo está ignorado por git y nunca se commitea.

## Base de datos

SQLite, en el directorio de datos privado de la app:

- tracks — pistas (replaygain, lrc_path, …)
- play_history — historial de reproducción
- playlists / playlist_tracks — listas y sus pistas
- settings — ajustes clave-valor

## Licencia

GPL v3 — ver LICENSE.

---

## Language / 语言

[English](README.en.md) · [简体中文](README.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Italiano](README.it.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)
