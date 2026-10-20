# Folia iOS 第一版验证记录

代码分支：codex/folia-ios；用户批准的规格与实施步骤：ios/README.md。

已实现：SwiftUI 系统液态玻璃底栏、迷你播放器、原生播放页与队列、文件导入与原子索引保存、AVPlayer 音频会话和系统控制、WKWebView 内置 Folia 流光渲染器、Navidrome HTTPS 登录及钥匙串存储、分页曲库、封面、按歌曲 ID 获取同步歌词。

审查修复：队列中的导入歌词副本同步；React 就绪握手；断开服务器清空 AVPlayer 和旧服务器队列；歌词导入目标在打开选择器时固定；换歌清空旧封面；后台卸载动画渲染器并在恢复时同步时钟。

验证：
- 8 项 FoliaCore 测试通过，包括空队列和队尾、非有限 seek、本地索引序列化、HTTPS 地址校验、歌词队列更新、远程会话失效、同步歌词毫秒时序和 offset、纯文本歌词。
- Xcode 27.2 / iOS SDK 27.2；原生设备目标曾成功编译。
- 首次 WebKit 集成测试暴露歌词页未就绪，已补充离线浏览器复现与 Vite 生产环境变量替换，最终结果见下方补充。

实施裁定：
- 无本地执行环境，代码通过远端独立分支提交，由 GitHub Actions 执行验证；代价：每轮编译依赖云端队列。
- 原生部署下限 iOS 26，使用 Xcode 27.2 编译以覆盖用户的 iOS 27；未使用未经确认的 iOS 27 专有接口。
- 第一版只包含本地和 Navidrome 音源，网易云/QQ 等商业平台后续逐个验证。
- Folia 原版 classic 不处理歌词点击跳转；第一版通过原生进度条跳转并同步歌词，未声称支持点击歌词跳转。
- 保留 AGPL-3.0 与原作者信息，未合并至 main；回滚方式是关闭草稿 PR，原 main 未改变。
- 尚需真机验证：后台长时间播放、耳机按键、文件提供商导入、用户实际 Navidrome 服务器认证与流媒体。模拟器或编译结果不替代上述真机检查。

## 当前交付（2026-10-21）
- 源代码构建提交：eba49a3ba2b6a2c5c1ca1b75b5c7973da23c2747
- 构建记录：https://github.com/zkjjs/folia-major/actions/runs/39478616324
- 测试安装包：https://github.com/zkjjs/folia-major/actions/runs/39478616324/artifacts/12290022436
- 包名：Folia-unsigned.ipa（在 GitHub 下载的 ZIP 中），未签名，需自行签名后安装。
- ZIP 大小：6,460,857 字节；GitHub 返回 SHA-256：9aeb6030f07c6db28d29f118f91bf1a4f1e591fd4f8854982362db261e1363bc。
- 本提交 8 项核心测试通过、离线浏览器启动/歌词显示/seek/恢复检查通过、iphoneos Release 编译及 IPA 打包通过。
- 修复了 Vite library 模式保留 process.env.NODE_ENV 导致独立网页启动失败的问题。
- WebKit 模拟器验证未通过验收：前一轮 39476913566 因模拟器启动超时而未开始 XCTest；当前轮有启动诊断并继续尝试。不能将浏览器通过或编译通过视为 WebKit/真机验证通过。
- 原作 classic 未实现点击歌词跳转；使用原生进度条定位。
- 不包含歌曲资源，也不承诺商业平台账号/音源可用性。
