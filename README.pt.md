# FreePlayer (macOS)

Reprodutor de música local. Sem rede, sem login, sem coleta de dados. Sua música fica no seu disco, com sua própria estrutura de pastas.

Implementação nativa para macOS (SwiftUI + AppKit), sem dependências de terceiros (apenas frameworks do sistema + SQLite).

## Formatos suportados

MP3, FLAC, WAV, OGG, M4A, AAC, AIFF (decodificáveis pelo AVFoundation)

## Recursos

- **Importar e biblioteca** : extração automática de metadados (título, artista, álbum, ano, gênero, faixa, bitrate, taxa de amostragem, canais); arquivos copiados ou vinculados simbolicamente em estrutura Artista/Álbum (modo selecionável em Ajustes)
- **Estatísticas de audição** : cada sessão é registrada no SQLite (início/fim, duração, percentual) — tempo total, reproduções, Top 10 músicas/artistas, estatísticas diárias de 30 dias
- **Playlists** : criar/renomear/excluir, adicionar individual ou em lote, editar
- **Letras LRC** : detecção automática ou associação manual de arquivos .lrc; codificações UTF-8 → GB18030 → Shift_JIS
- **ReplayGain** : ajuste automático de volume pelas tags
- **Capas** : artwork embutido extraído na importação para a pasta .covers do álbum
- **Teclas de mídia / barra de menu** : teclas do sistema tocar/pausar/anterior/próxima, informações no Control Center, controle pelo ícone da barra de menu; fechar a janela a oculta na barra e continua a reprodução
- **Visualizador** : osciloscópio + espectro em tempo real, ou espectrograma cascata
- **Modo imersivo** : reprodução em tela cheia com letras karaokê e escala de fonte

## Compilação (macOS 13+, Xcode CLT / Swift 6)

```bash
cd macos
make            # build release + empacotamento FreePlayer.app
make run        # executar diretamente o build debug
make run-app    # abrir o app empacotado
make test       # executar testes unitários
```

## Banco de dados

SQLite em ~/Library/Application Support/FreePlayer/library.db:

- tracks — faixas (replaygain, play_count, last_played_at, lrc_path, …)
- play_history — histórico de reprodução
- playlists / playlist_tracks — playlists e faixas
- settings — configurações chave-valor

## Licença

GPL v3 — ver LICENSE.

---

## Language / 语言

[English](README.en.md) · [简体中文](README.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Italiano](README.it.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)
