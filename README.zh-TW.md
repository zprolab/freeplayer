# FreePlayer (Android)

本機音樂播放器，不連網、不登入、不收集任何資料。你的音樂在你硬碟上，用你自己的資料夾結構管理。

> 另有 macOS（SwiftUI）實作，見倉庫 `Swift` 分支；歷史 Web 版本見 `master`。

## 支援格式

MP3, FLAC, WAV, OGG, M4A, AAC, OPUS, MP4（系統解碼器支援範圍）

## 主要功能

- **匯入與分享**：從系統檔案選擇器匯入資料夾；其他應用（微信/檔案管理員等）分享的音訊可直接「用 FreePlayer 開啟」一鍵匯入
- **媒體庫管理**：自動讀取 metadata（標題、藝人、專輯、年份、類型、音軌號、位元率、取樣率、聲道數），按 藝人/專輯 目錄結構儲存，提取內嵌封面
- **播放統計**：每次播放記錄（開始/結束、時長、播放比例），彙總總時長、播放次數、Top10 曲目/藝人、近 30 天每日統計
- **播放清單**：建立/重新命名/刪除、單首/批次加入、編輯曲目
- **LRC 歌詞**：自動偵測或手動關聯 .lrc；編碼回退鏈 UTF-8 → GB18030 → Shift_JIS
- **ReplayGain**：自動調節播放音量
- **波形視覺化**：示波器 + 頻譜 + 熱力頻譜瀑布圖三種模式
- **沉浸模式**：全螢幕無干擾播放介面
- **媒體鍵/通知**：前景服務通知控制播放，鎖定畫面/藍牙耳機可用

## 建置

需要 Android SDK（compileSdk 37，minSdk 26）。

```bash
cd Android
./gradlew :app:assembleDebug     # 除錯包
./gradlew :app:assembleRelease   # 發布包（需簽名設定）
./gradlew :app:testDebugUnitTest # 單元測試
```

發布簽名：將 `freeplayer-release.jks` 與 `keystore.properties`（storeFile/storePassword/keyAlias/keyPassword）放在 `Android/` 下；該檔案已被 git 忽略，不會入庫。

## 資料庫

SQLite，位於應用程式私有資料目錄：

- tracks — 曲目（含 replaygain、lrc_path 等）
- play_history — 播放記錄
- playlists / playlist_tracks — 播放清單與曲目
- settings — 鍵值對設定

## 授權

GPL v3，詳見 LICENSE 檔案。

---

## Language / 语言

[English](README.en.md) · [简体中文](README.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Italiano](README.it.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)
