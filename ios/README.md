# Folia iOS

面向 iOS 27 的原生播放器移植，基于上游 Folia，保留 AGPL-3.0 许可证及作者信息。

## 已批准规格
SwiftUI 原生音乐库和液态玻璃底栏；AVPlayer 负责本地及 Navidrome 音频；WKWebView 复用 Folia 歌词渲染器。支持后台、锁屏和耳机控制。在线商业平台后续逐个验证。

## 实施计划
1. 工程及 CI：ios/project.yml、App/FoliaApp.swift；CI 先测试 FoliaCore，再构建 iphoneos 应用并打包 Payload。
2. 本地库：Sources/FoliaCore/Track.swift、PlaybackRules.swift、App/Library/LibraryStore.swift；导入文件复制到 Documents，索引原子写入；失败显示错误，不擦除旧索引。
3. 原生播放：App/Playback/PlayerStore.swift；队列、seek、结束切歌、音频会话中断及耳机拔出处理；Now Playing 与实际 AVPlayer 状态同步。
4. 歌词：ios/web/entry.tsx、App/Lyrics/LyricsWebView.swift；复用上游 classic 渲染和 parserCore；按 track ID 隔离消息；前后台与 seek 后重同步；WebView 不播放音频。
5. UI：App/RootView.swift、App/Playback/PlayerView.swift；系统 TabView 底栏和迷你播放器；中文、深浅色、队列、歌词导入；无歌词显示明确状态。
6. Navidrome：App/Navidrome/NavidromeClient.swift、NavidromeView.swift；HTTPS、Keychain 凭据、分页曲库、鉴权流媒体和歌词；失败可重试。
7. 验证：swift test；Web 构建；iphoneos 编译；真机验证锁屏持续播放、耳机控制、歌词 seek、无网络、本地导入、Navidrome 失效凭据。
8. 交付：草稿 PR、构建日志及待签名 IPA；只有构建成功才宣称产物可用，未做的真机验证明确列出。

## 开发记录
- 2026-10-21：用户批准规格、实施顺序及本会话实现，已 Fork 到 zkjjs/folia-major。
- 环境裁定：本地执行环境不可用，使用独立远端分支和 GitHub Actions 进行构建验证。
- 第一轮：先提交核心行为测试和 CI，取得测试结果后实现核心及应用。
- 不将编译成功等同于已在 iOS 27 真机验证。
