FreePlayer

桌面端本地音乐播放器，不联网、不登录、不收集任何数据。你的音乐在你硬盘上，用你自己的文件夹结构管理。

Built with Electron + React + Vite，数据库用 SQLite（通过 better-sqlite3），元数据解析用 music-metadata。

支持格式

MP3, FLAC, WAV, OGG, M4A, AAC, WMA, Opus, AIFF, APE

主要功能

导入和管理本地音乐库
  导入时会自动读取每首歌的metadata（标题、艺人、专辑、年份、流派、音轨号、比特率、采样率、声道数等），并按照 艺人/专辑 的目录结构复制或软链接到你的库文件夹。导入模式（复制/软链接）可在设置里选。

播放统计
  每次播放都会记录到 SQLite（开始时间、结束时间、播放时长、播放进度百分比），然后汇总出总播放时长、播放次数、常听曲目 Top 10、常听艺人 Top 10、最近 30 天每日统计。这些数据都在你本地数据库里，随时可以清库重置。

播放列表
  创建、重命名、删除播放列表。支持单首加入、批量加入、拖拽排序。

LRC 歌词
  支持为每首歌手动关联 .lrc 歌词文件。读取时会自动检测文件编码，UTF-8 解码失败后依次尝试 GBK、GB18030、GB2312、Shift_JIS、EUC-KR、Big5，不用担心中文日文韩文歌词乱码。

ReplayGain
  如果音频文件里有 ReplayGain 标签，导入时会自动读取并存储，播放时用来自动调整音量。

封面
  导入时自动从音频文件里提取内嵌封面图片，存到专辑目录下的 .covers 子目录。

全局媒体键
  注册了系统的播放/暂停、下一首、上一首快捷键，即使窗口在后台也能响应。

波形可视化
  播放时实时显示音频波形。

沉浸模式
  全屏无干扰播放界面。

自定义 media:// 协议
  主进程注册了 media:// 协议来加载本地音频文件，支持 Range 请求（拖动进度条），且做了路径穿越保护，只能访问库目录内的文件。

深色主题
  背景色 #1f1f23，全是暗色，不刺眼。

标题栏隐藏
  macOS 下使用 hiddenInset 标题栏，红绿灯按钮嵌入在窗口角落。

数据库结构

  tracks — 曲目信息（标题、艺人、专辑、时长、路径、格式、比特率、ReplayGain 等）
  play_history — 播放记录（曲目 ID、开始时间、结束时间、时长、播放比例）
  playlists — 播放列表
  playlist_tracks — 播放列表内曲目（支持排序位置）
  settings — 键值对设置项
  lrc_path 字段在 tracks 表里存歌词文件路径

安装

  git clone <仓库地址>
  cd FreePlayer
  npm install

开发

  npm run dev
  这个命令会同时启动 Vite 开发服务器和 Electron 窗口。Vite 先启动，wait-on 等到 localhost:5173 可用后再启动 Electron。

测试

  npm test
  用的是 vitest。

打包

  npm run dist:mac     macOS -> dmg + zip
  npm run dist:win     Windows -> NSIS 安装包
  npm run dist:linux   Linux -> AppImage + deb

许可证

  GPL v3，详见 LICENSE 文件。
