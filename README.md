# FreePlayer (macOS)

本地音乐播放器，不联网、不登录、不收集任何数据。你的音乐在你硬盘上，用你自己的文件夹结构管理。

原生 macOS（SwiftUI + AppKit）实现，无第三方运行时依赖（仅系统框架 + SQLite）。

> 另有 Android（Kotlin + Compose）实现，见仓库 `Android` 分支；历史 Web 版本见 `master`。

## 支持格式

MP3, FLAC, WAV, OGG, M4A, AAC, AIFF（AVFoundation 可解码格式）

## 主要功能

- **导入与库管理**：导入时自动读取 metadata（标题、艺人、专辑、年份、流派、音轨号、比特率、采样率、声道数），按 艺人/专辑 目录结构复制或软链接到库文件夹（复制/软链接模式可在设置里选）
- **播放统计**：每次播放记录到 SQLite（开始/结束、播放时长、播放比例），汇总总播放时长、播放次数、常听曲目 Top 10、常听艺人 Top 10、最近 30 天每日统计
- **播放列表**：创建、重命名、删除播放列表，支持单首/批量加入、编辑曲目
- **LRC 歌词**：自动检测或手动关联 .lrc 歌词文件；编码回退链 UTF-8 → GB18030 → Shift_JIS
- **ReplayGain**：音频文件的 ReplayGain 标签自动调整播放音量
- **封面**：导入时自动提取内嵌封面，存到专辑目录的 .covers 子目录
- **全局媒体键 / 托盘**：系统播放/暂停、上一首、下一首媒体键，Control Center 显示曲目信息，菜单栏托盘控制播放；关闭窗口默认隐藏到托盘继续播放
- **波形可视化**：播放时实时显示波形（示波器 + 频谱柱）或热力频谱瀑布图（Spectrogram）
- **沉浸模式**：全屏无干扰播放界面，带卡拉 OK 歌词与字体缩放

## 构建（macOS 13+，需要 Xcode 命令行工具 / Swift 6）

```bash
cd macos
make            # swift build -c release + 打包 FreePlayer.app
make run        # 直接运行调试构建
make run-app    # 打开打包好的 FreePlayer.app
make test       # 运行单元测试
```

## 数据库

SQLite，位于 `~/Library/Application Support/FreePlayer/library.db`：
- tracks — 曲目（含 replaygain、play_count、last_played_at、lrc_path 等）
- play_history — 播放记录
- playlists / playlist_tracks — 播放列表与曲目
- settings — 键值对设置

## 许可证

GPL v3，详见 LICENSE 文件。

---

## Language / 语言

[English](README.en.md) · [简体中文](README.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Italiano](README.it.md) · [العربية](README.ar.md) · [हिन्दी](README.hi.md)
