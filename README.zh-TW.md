# FreePlayer (macOS)

本機音樂播放器，不連網、不登入、不收集任何資料。你的音樂在你硬碟上，用你自己的資料夾結構管理。

原生 macOS（SwiftUI + AppKit）實作，無第三方執行階段依賴（僅系統框架 + SQLite）。

## 支援格式

MP3, FLAC, WAV, OGG, M4A, AAC, AIFF（AVFoundation 可解碼格式）

## 主要功能

- **匯入與媒體庫管理**：匯入時自動讀取 metadata（標題、藝人、專輯、年份、類型、音軌號、位元率、取樣率、聲道數），按 藝人/專輯 目錄結構複製或軟連結到媒體庫資料夾（複製/軟連結模式可在設定裡選）
- **播放統計**：每次播放記錄到 SQLite（開始/結束、播放時長、播放比例），彙總總播放時長、播放次數、常聽曲目 Top 10、常聽藝人 Top 10、最近 30 天每日統計
- **播放清單**：建立、重新命名、刪除播放清單，支援單首/批次加入、編輯曲目
- **LRC 歌詞**：自動偵測或手動關聯 .lrc 歌詞檔；編碼回退鏈 UTF-8 → GB18030 → Shift_JIS
- **ReplayGain**：音訊檔案的 ReplayGain 標籤自動調整播放音量
- **封面**：匯入時自動提取內嵌封面，存到專輯目錄的 .covers 子目錄
- **全域媒體鍵 / 托盤**：系統播放/暫停、上一首、下一首媒體鍵，Control Center 顯示曲目資訊，選單列托盤控制播放；關閉視窗預設隱藏到托盤繼續播放
- **波形視覺化**：播放時即時顯示波形（示波器 + 頻譜柱）或熱力頻譜瀑布圖（Spectrogram）
- **沉浸模式**：全螢幕無干擾播放介面，帶卡拉 OK 歌詞與字型縮放

## 建置（macOS 13+，需要 Xcode 命令列工具 / Swift 6）

```bash
cd macos
make            # release 建置 + 打包 FreePlayer.app
make run        # 直接執行除錯建置
make run-app    # 開啟打包好的 FreePlayer.app
make test       # 執行單元測試
```

## 資料庫

SQLite，位於 ~/Library/Application Support/FreePlayer/library.db：

- tracks — 曲目（含 replaygain、play_count、last_played_at、lrc_path 等）
- play_history — 播放記錄
- playlists / playlist_tracks — 播放清單與曲目
- settings — 鍵值對設定

## 授權

GPL v3，詳見 LICENSE 檔案。

---

## Language / 语言

[English](README.en.md) · [简体中文](README.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Italiano](README.it.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)
