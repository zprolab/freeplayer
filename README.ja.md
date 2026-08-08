# FreePlayer (macOS)

ローカル音楽プレイヤー。ネットワーク接続なし、ログインなし、データ収集なし。あなたの音楽はあなたのハードディスクに、あなた自身のフォルダ構造で。

ネイティブ macOS（SwiftUI + AppKit）実装。サードパーティ製ランタイム依存なし（システムフレームワーク + SQLite のみ）。

## 対応形式

MP3, FLAC, WAV, OGG, M4A, AAC, AIFF（AVFoundation がデコード可能な形式）

## 主な機能

- **インポートとライブラリ管理**：インポート時にメタデータを自動取得（タイトル、アーティスト、アルバム、年、ジャンル、トラック番号、ビットレート、サンプルレート、チャンネル数）。アーティスト/アルバム構造でコピーまたはシンボリックリンク（設定で選択可）
- **再生統計**：再生セッションを SQLite に記録（開始/終了、再生時間、再生割合）。合計時間、再生回数、Top10 曲/アーティスト、直近30日の日別統計
- **プレイリスト**：作成/リネーム/削除、単曲/一括追加、曲目編集
- **LRC 歌詞**：.lrc 自動検出または手動関連付け。文字コードフォールバック UTF-8 → GB18030 → Shift_JIS
- **ReplayGain**：ファイルの ReplayGain タグで音量を自動調整
- **ジャケット**：インポート時に埋め込みアートワークを抽出し、アルバムの .covers フォルダに保存
- **メディアキー / トレイ**：システムの再生/一時停止・前へ・次へキー、Control Center の曲情報、メニューバートレイで再生操作。ウィンドウを閉じるとトレイに格納して再生継続
- **ビジュアライザー**：リアルタイム波形（オシロスコープ + スペクトラム）またはスペクトログラム・ウォーターフォール
- **イマーシブモード**：全画面で邪魔のない再生。カラオケ歌詞とフォントスケーリング対応

## ビルド（macOS 13+、Xcode CLT / Swift 6 が必要）

```bash
cd macos
make            # release ビルド + FreePlayer.app パッケージ
make run        # デバッグビルドを直接実行
make run-app    # パッケージ化したアプリを開く
make test       # ユニットテストを実行
```

## データベース

SQLite、~/Library/Application Support/FreePlayer/library.db：

- tracks — 曲目（replaygain、play_count、last_played_at、lrc_path など）
- play_history — 再生履歴
- playlists / playlist_tracks — プレイリストと曲目
- settings — キー・バリュー設定

## ライセンス

GPL v3。LICENSE を参照。

---

## Language / 语言

[English](README.en.md) · [简体中文](README.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Italiano](README.it.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)
