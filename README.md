# FreePlayer

本地音乐播放器：macOS 原生 App + iPad 兼容层。没有登录、没有账号、没有遥测，你的音乐文件留在你自己的设备上。

- macOS 13+（Apple Silicon，M-系列芯片）
- iPadOS 17+（iPad，从模拟器或 Xcode 直接构建运行）
- 默认完全离线。只有在设置里手动打开 "Auto-Fetch Lyrics & Covers" 之后，遇到缺歌词或封面的歌曲，才会把曲目标题、艺人、专辑发到 LRCLIB（歌词）和 iTunes Search API（封面）去查。开关默认关闭。字体从写下这句话开始都是离线加载。

## 技术栈

前端 React 19 + Vite，原生外壳 Swift（Cocoa + WebKit + AVFoundation 等系统框架），数据库用系统自带的 SQLite，元数据解析也是原生实现的。无需 Electron，没有运行时 npm 依赖。非常精简的安装包。

支持格式：MP3、FLAC、WAV、OGG、M4A、AAC、WMA、Opus、AIFF、APE。

## 源码结构

所有 Swift 源码共用一棵树（`shell/Sources/`），macOS 和 iPad 各自从里面挑平台层编译：

```
shell/Sources/
├── Core/         跨平台：SQLite 数据库、AVFoundation 元数据、路径安全
├── Bridge/       跨平台：JS bridge 分发、导入管线、HTTP
├── UI/           跨平台：SchemeHandler、AppContext、PlatformBridge 协议
├── App/          跨平台：导航门
└── Platform/
    ├── macOS/    macOS 平台层（AppDelegate、窗口、托盘、插件 FS）
    └── iPad/     iPad 平台层（App 入口、WKWebView 容器、平台桥、沙盒导入）
```

- macOS：CMake + Ninja（`shell/CMakeLists.txt` 只编译 macOS 平台层）
- iPad：XcodeGen（`shell/project.yml` 引用同一源码树 + `Platform/iPad`）

## 功能

- **导入音乐库**：自动读取每首歌的 metadata（标题、艺人、专辑、年份、流派、音轨号、比特率、采样率等），按 艺人/专辑 建好目录结构，再复制或软链接进库，模式可以在设置里选。iPad 上为沙盒固定库（`Documents/FreePlayer Library`），只支持复制导入。
- **播放统计**：每次播放记到本地 SQLite（开始/结束时间、播放时长、播放进度），汇总出总播放时长、播放次数、常听曲目/艺人 Top 10、近 30 天每日统计。数据全在本地，随时可以清库重置。
- **播放列表**：创建、重命名、删除，支持单曲加入、批量加入、拖拽排序。
- **LRC 歌词**：手动关联 .lrc 文件，自动识别编码（UTF-8 失败后依次尝试 GBK、GB18030、GB2312、Shift_JIS、EUC-KR、Big5），中英日韩歌词都不会乱码。
- **ReplayGain**：读取音频文件里的 ReplayGain 标签，播放时自动调整音量。
- **封面**：导入时自动提取内嵌封面，存到专辑目录下的 `.covers` 子目录。
- **全局媒体键**：播放/暂停、上一首、下一首，窗口在后台也能响应。iPad 上同步到控制中心（Now Playing）。
- **波形可视化**：播放时实时画波形（Web Audio Analyser），自带频谱图。
- **均衡器**：10 段（31Hz~16kHz），内置几个预设，独立小窗调节，设置全局持久化。
- **沉浸模式**：全屏无干扰播放界面。
- 深色主题，标题栏隐藏，界面字体只用本机已装字体（设置里可以选等宽字体）。

## 插件

内置 MusicBrainz 插件可以补全曲目元数据（标题/艺人/专辑/流派/年份/音轨号，数据 CC0）和封面（Cover Art Archive）。

用之前先看版权：

- 请使用**自己的** API 凭证。MusicBrainz 公共 API 不需要 key；自建实例或更高级的用法自己申请/配置，不要共用别人的凭证。
- MusicBrainz 核心数据是 CC0，可以自由使用；**Cover Art Archive 的图片是 CC BY-NC-SA，只能个人使用，不能商用分发**。商用需要和 MetaBrainz 签支持者协议。
- 默认完全离线，Auto-Fetch 相关开关默认关闭。

## 数据库

| 表 | 内容 |
| --- | --- |
| `tracks` | 曲目信息（标题、艺人、专辑、时长、路径、格式、比特率、ReplayGain 等） |
| `play_history` | 播放记录（曲目 ID、开始/结束时间、时长、播放比例） |
| `playlists` | 播放列表 |
| `playlist_tracks` | 播放列表内的曲目（含排序位置） |
| `settings` | 键值对设置 |

## 安装与开发

```sh
git clone https://github.com/zprolab/FreePlayer
cd FreePlayer
pnpm install
pnpm run install:app  # 可选：构建并安装到 /Applications
pnpm run dev          # 起 Vite 开发服务器并编译运行原生外壳
```

测试：`pnpm test`（vitest，覆盖音频引擎、均衡器、metadata 持久化、播放状态机等）。

打包：

```sh
pnpm run build        # vite build → dist/
pnpm run bundle       # 打包 FreePlayer.app
pnpm run dist         # build + bundle → zip + dmg，输出到 shell/release/
```

产物命名：`FreePlayer-<version>-mac-arm64-<timestamp>.{zip,dmg}`。

### iPad / iPhone 构建

```sh
pnpm build                    # 先产出 web 资源 dist/（Xcode 构建会 rsync 进 bundle）
cd shell && xcodegen generate # 生成 FreePlayer.xcodeproj（生成物不入库）
xcodebuild -project FreePlayer.xcodeproj -scheme FreePlayer \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build
```

独立的 iPhone target 使用同一套播放器内核和 Web UI，但有自己的 bundle id、入口和设备配置：

```sh
pnpm build:iphone
```

## 许可证

GPL-3.0-or-later，© 2026 zprolab。详见 [LICENSE](LICENSE)。
