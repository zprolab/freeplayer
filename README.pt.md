# FreePlayer (Android)

Reprodutor de música local. Sem rede, sem login, sem coleta de dados. Sua música fica no seu dispositivo, com sua própria estrutura de pastas.

> Há uma implementação para macOS (SwiftUI) no branch `Swift`; a versão web antiga está no `master`.

## Formatos suportados

MP3, FLAC, WAV, OGG, M4A, AAC, OPUS, MP4 (conforme decodificadores do sistema)

## Recursos

- **Importar e compartilhar**: importe pastas pelo seletor de arquivos do sistema; áudio compartilhado de outros apps (WeChat, gerenciadores de arquivos…) é importado com um toque via “Abrir com FreePlayer”
- **Biblioteca**: extração automática de metadados (título, artista, álbum, ano, gênero, faixa, bitrate, taxa de amostragem, canais), armazenada em estrutura Artista/Álbum com capas embutidas
- **Estatísticas de audição**: cada reprodução é registrada (início/fim, duração, percentual) — tempo total, reproduções, Top 10 músicas/artistas, estatísticas diárias de 30 dias
- **Playlists**: criar/renomear/excluir, adicionar individual ou em lote, editar lista
- **Letras LRC**: detecção automática ou associação manual de arquivos .lrc; codificações UTF-8 → GB18030 → Shift_JIS
- **ReplayGain**: ajuste automático de volume
- **Visualizador**: osciloscópio + espectro + espectrograma cascata
- **Modo imersivo**: reprodução em tela cheia sem distrações
- **Teclas de mídia / notificação**: controles na notificação do serviço em primeiro plano; funciona na tela de bloqueio e com fones Bluetooth

## Compilação

Requer Android SDK (compileSdk 37, minSdk 26).

```bash
cd Android
./gradlew :app:assembleDebug     # APK debug
./gradlew :app:assembleRelease   # APK release (exige configuração de assinatura)
./gradlew :app:testDebugUnitTest # testes unitários
```

Assinatura de release: coloque `freeplayer-release.jks` e `keystore.properties` (storeFile/storePassword/keyAlias/keyPassword) dentro de `Android/`; o arquivo é ignorado pelo git e nunca é commitado.

## Banco de dados

SQLite, no diretório privado de dados do app:

- tracks — faixas (replaygain, lrc_path, …)
- play_history — histórico de reprodução
- playlists / playlist_tracks — playlists e faixas
- settings — configurações chave-valor

## Licença

GPL v3 — ver LICENSE.

---

## Language / 语言

[English](README.en.md) · [简体中文](README.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Italiano](README.it.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)
