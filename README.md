FreePlayer

桌面端本地音乐播放器，不联网、不登录、不收集任何数据。你的音乐在你硬盘上，用你自己的文件夹结构管理。

原生 macOS（SwiftUI + AppKit）实现，无第三方运行时依赖（仅系统框架 + SQLite）。

支持格式

MP3, FLAC, WAV, OGG, M4A, AAC, AIFF（AVFoundation 可解码格式）

主要功能

导入和管理本地音乐库
  导入时自动读取每首歌的 metadata（标题、艺人、专辑、年份、流派、音轨号、比特率、采样率、声道数等），并按 艺人/专辑 目录结构复制或软链接到库文件夹。导入模式（复制/软链接）可在设置里选。

播放统计
  每次播放记录到 SQLite（开始时间、结束时间、播放时长、播放比例），汇总出总播放时长、播放次数、常听曲目 Top 10、常听艺人 Top 10、最近 30 天每日统计。数据全在本地，随时可清库重置。

播放列表
  创建、重命名、删除播放列表，支持单首/批量加入、编辑曲目。

LRC 歌词
  为每首歌曲自动检测或手动关联 .lrc 歌词文件。读取时自动检测编码，UTF-8 失败后依次尝试 GB18030、Shift_JIS，不用担心中文日文歌词乱码。

ReplayGain
  音频文件的 ReplayGain 标签会自动调整播放音量。

封面
  导入时自动提取内嵌封面，存到专辑目录的 .covers 子目录。

全局媒体键 / 托盘
  注册系统播放/暂停、上一首、下一首媒体键，Control Center 显示曲目信息，菜单栏托盘可控制播放。关闭窗口默认隐藏到托盘继续播放。

波形可视化
  播放时实时显示波形（示波器 + 频谱柱），或热力频谱瀑布图（Spectrogram）。

沉浸模式
  全屏无干扰播放界面，带卡拉 OK 歌词与字体缩放。

深色主题
  背景色 #1f1f23，全暗色。

数据库

  SQLite，位于 ~/Library/Application Support/FreePlayer/library.db
  tracks — 曲目（含 replaygain、play_count、last_played_at、lrc_path 等）
  play_history — 播放记录
  playlists / playlist_tracks — 播放列表与曲目（支持排序位置）
  settings — 键值对设置

构建（macOS 13+，需要 Xcode 命令行工具 / Swift 6）

  cd macos
  make            # swift build -c release + 打包 FreePlayer.app
  make run        # 直接运行调试构建
  make run-app    # 打开打包好的 FreePlayer.app
  make test       # 运行单元测试（swift test）

旧架构说明

  shell/ 目录保留旧的 ObjC++ + WKWebView 外壳，src/ 目录保留旧的 React 网页 UI，
  均已不再使用，仅作历史参考。

许可证

  GPL v3，详见 LICENSE 文件。
