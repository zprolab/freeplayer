# FreePlayer (Android)

FreePlayer 的 Android 客户端（Kotlin + Jetpack Compose）。本地音乐播放器，不联网、不登录、不收集任何数据。你的音乐在你硬盘上，用你自己的文件夹结构管理。

> 另有 macOS（SwiftUI）实现，见仓库 `Swift` 分支；历史 Web 版本见 `master`。

## 支持格式

MP3, FLAC, WAV, OGG, M4A, AAC, OPUS, MP4（系统解码器支持范围）

## 主要功能

- **导入与分享**：从系统文件选择器导入文件夹；其他应用（微信/文件管理器等）分享的音频可直接"用 FreePlayer 打开"一键导入
- **库管理**：自动读取 metadata（标题、艺人、专辑、年份、流派、音轨号、比特率、采样率、声道数），按 艺人/专辑 目录结构存储，提取内嵌封面
- **播放统计**：每次播放记录（开始/结束、时长、播放比例），汇总总时长、播放次数、Top10 曲目/艺人、近 30 天每日统计
- **播放列表**：创建/重命名/删除、单首/批量加入、编辑曲目
- **LRC 歌词**：自动检测或手动关联 .lrc；编码回退链 UTF-8 → GB18030 → Shift_JIS
- **ReplayGain**：自动调节播放音量
- **波形可视化**：示波器 + 频谱 + 热力频谱瀑布图三种模式
- **沉浸模式**：全屏无干扰播放界面
- **媒体键/通知**：前台服务通知控制播放，锁屏/蓝牙耳机可用

## 构建

需要 Android SDK（compileSdk 37，minSdk 26）。

```bash
cd Android
./gradlew :app:assembleDebug     # 调试包
./gradlew :app:assembleRelease   # 发布包（需签名配置）
./gradlew :app:testDebugUnitTest # 单元测试
```

发布签名：将 `freeplayer-release.jks` 与 `keystore.properties`（storeFile/storePassword/keyAlias/keyPassword）放在 `Android/` 下；该文件已被 git 忽略，不会入库。

## 数据库

SQLite，位于应用私有数据目录：
- tracks — 曲目（含 replaygain、lrc_path 等）
- play_history — 播放记录
- playlists / playlist_tracks — 播放列表与曲目
- settings — 键值对设置

## 许可证

GPL v3，详见 LICENSE 文件。
