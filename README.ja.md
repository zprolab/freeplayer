# FreePlayer (Android)

ローカル音楽プレイヤー。ネットワーク接続なし、ログインなし、データ収集なし。あなたの音楽はあなたのデバイスに、あなた自身のフォルダ構造で。

> macOS（SwiftUI）実装はリポジトリの `Swift` ブランチ、旧 Web 版は `master` にあります。

## 対応形式

MP3, FLAC, WAV, OGG, M4A, AAC, OPUS, MP4（システムデコーダの対応範囲）

## 主な機能

- **インポートと共有**：システムのファイルピッカーからフォルダをインポート。他アプリ（WeChat など）から共有された音声は「FreePlayer で開く」でワンタップインポート
- **ライブラリ管理**：メタデータ自動取得（タイトル、アーティスト、アルバム、年、ジャンル、トラック番号、ビットレート、サンプルレート、チャンネル数）、アーティスト/アルバム構造で保存、埋め込みジャケット抽出
- **再生統計**：再生ごとに記録（開始/終了、再生時間、再生割合）、合計時間・再生回数・Top10 曲/アーティスト・直近30日の日別統計
- **プレイリスト**：作成/リネーム/削除、単曲/一括追加、曲目編集
- **LRC 歌詞**：.lrc 自動検出または手動関連付け、文字コードフォールバック UTF-8 → GB18030 → Shift_JIS
- **ReplayGain**：再生音量を自動調整
- **ビジュアライザー**：オシロスコープ + スペクトラム + スペクトログラム・ウォーターフォールの3モード
- **イマーシブモード**：全画面・邪魔のない再生画面
- **メディアキー/通知**：フォアグラウンドサービス通知で再生操作、ロック画面/Bluetooth ヘッドホン対応

## ビルド

Android SDK が必要です（compileSdk 37, minSdk 26）。

```bash
cd Android
./gradlew :app:assembleDebug     # デバッグ APK
./gradlew :app:assembleRelease   # リリース APK（署名設定が必要）
./gradlew :app:testDebugUnitTest # ユニットテスト
```

リリース署名：`freeplayer-release.jks` と `keystore.properties`（storeFile/storePassword/keyAlias/keyPassword）を `Android/` に配置。このファイルは git で無視され、コミットされません。

## データベース

SQLite、アプリ専用データディレクトリ内：

- tracks — 曲目（replaygain、lrc_path など）
- play_history — 再生履歴
- playlists / playlist_tracks — プレイリストと曲目
- settings — キー・バリュー設定

## ライセンス

GPL v3。LICENSE を参照。

---

## Language / 语言

[English](README.en.md) · [简体中文](README.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Italiano](README.it.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)
