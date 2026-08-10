# FreePlayer

桌面端本地音乐播放器，无登录、无账号、无遥测，你的音乐留在你自己的硬盘上。**默认完全离线**；仅当你手动开启设置里的"Auto-Fetch Lyrics & Covers"后，播放缺歌词/封面的歌曲时才会上传曲目标题、艺人、专辑到 LRCLIB（歌词）与 iTunes Search API（封面），且默认关闭、可随时关闭。

仅支持 **macOS 13.0+（Apple Silicon，arm64）**。

## 技术栈

- 前端：React 19 + Vite
- 原生外壳：Objective-C++（Cocoa + WebKit + AVFoundation + CoreMedia + AudioToolbox + MediaPlayer）
- 数据库：SQLite（系统自带 `libsqlite3`，无第三方依赖）
- 元数据解析：原生实现（`shell/src/metadata.mm`），不依赖 music-metadata
- 构建：`make`（shell）+ Vite（web），无 Electron、无运行时 npm 依赖

## 支持格式

MP3, FLAC, WAV, OGG, M4A, AAC, WMA, Opus, AIFF, APE

## 主要功能

- **导入和管理本地音乐库** — 导入时自动读取每首歌的 metadata（标题、艺人、专辑、年份、流派、音轨号、比特率、采样率、声道数等），并按 艺人/专辑 的目录结构复制或软链接到库文件夹。导入模式（复制/软链接）可在设置里选。
- **播放统计** — 每次播放记录到 SQLite（开始时间、结束时间、播放时长、播放进度百分比），汇总出总播放时长、播放次数、常听曲目 Top 10、常听艺人 Top 10、最近 30 天每日统计。数据全部留在本地数据库，可随时清库重置。
- **播放列表** — 创建、重命名、删除播放列表，支持单首加入、批量加入、拖拽排序。
- **LRC 歌词** — 为每首歌手动关联 .lrc 文件。自动检测编码：UTF-8 解码失败后依次尝试 GBK、GB18030、GB2312、Shift_JIS、EUC-KR、Big5，中英日韩歌词均不乱码。
- **ReplayGain** — 读取音频文件里的 ReplayGain 标签并存储，播放时自动调整音量。
- **封面** — 导入时自动提取内嵌封面，存到专辑目录下的 `.covers` 子目录。
- **全局媒体键** — 注册系统播放/暂停、上一首、下一首快捷键，窗口在后台也能响应。
- **波形可视化** — 播放时实时显示音频波形（Web Audio Analyser）。
- **均衡器** — 10 段图形均衡器（31Hz~16kHz），内置 6 个预设（平坦/低音增强/人声清晰/古典/摇滚/流行），独立小窗调节，设置全局持久化。
- **沉浸模式** — 全屏无干扰播放界面。
- **自定义 `media://` 协议** — 加载本地音频文件，支持 Range 请求（拖动进度条），并做路径穿越保护，只能访问库目录内的文件。
- **深色主题** — 背景色 #1f1f23，暗色设计。
- **标题栏隐藏** — macOS 下使用 hiddenInset 标题栏，红绿灯按钮嵌入窗口角落。

## 数据库结构

| 表 | 内容 |
| --- | --- |
| `tracks` | 曲目信息（标题、艺人、专辑、时长、路径、格式、比特率、ReplayGain 等，`lrc_path` 字段存歌词文件路径） |
| `play_history` | 播放记录（曲目 ID、开始时间、结束时间、时长、播放比例） |
| `playlists` | 播放列表 |
| `playlist_tracks` | 播放列表内曲目（支持排序位置） |
| `settings` | 键值对设置项 |

## 安装

```sh
git clone https://github.com/zprolab/FreePlayer
cd FreePlayer
npm install
```

## 开发

```sh
npm run dev
```

自动启动 Vite 开发服务器（localhost:5173）并编译运行原生外壳 `shell/build/FreePlayerShell`。

## 测试

```sh
npm test
```

用 vitest 跑前端逻辑单测（音频引擎、均衡器、metadata 持久化、播放状态机等）。

## 打包

```sh
npm run build        # vite build → dist/
npm run shell:bundle # 打包 FreePlayer.app
npm run shell:dist   # vite build + app bundle → zip + dmg，输出到 shell/release/
```

产物命名：`FreePlayer-<version>-mac-arm64-<timestamp>.{zip,dmg}`

## 许可证

GPL-3.0-or-later，版权所有 © 2026 zprolab。详见 [LICENSE](LICENSE) 文件。
