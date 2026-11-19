---
name: macos-auto-update
description: 给直接分发的 macOS 应用接入或排查签名自动更新。适用于原生 SwiftUI/AppKit 的 Sparkle、已有 Tauri updater 的 macOS 应用、Developer ID 签名公证，以及通过 GitHub Actions 发布到 Cloudflare R2 的更新包和订阅源。App Store 或 TestFlight 独立发版使用商店更新渠道。
---

# macOS 应用自动更新

1. 查工程、构建设置和既有发布流程。记录实际 bundle ID、签名团队、应用及扩展的受限 entitlements、最低系统、支持架构、版本字段、分发渠道和 release runner。优先沿用既有签名、公证和构建配置，确认它适用于直发签名。保留既有 `.app` 路径、应用签名标识和共享数据访问能力。
2. 原生应用使用 Sparkle 2 标准检查、下载、安装和重启流程。已有 Tauri updater 则保留它的签名、清单和客户端 API。使用独立的构建配置、target 或 spec 启用直发 updater。先明确自动检查、下载、安装的默认策略和手动入口，再写客户端代码。读 [实现与验收](references/implementation.md) 获取两类更新器的接入与发布细节。
3. GitHub Actions 的 PR 检查在无签名凭据条件下验证构建。直发 workflow 复用 Developer ID Application 身份、具体 bundle 的 profiles 及公证凭据，完成 Hardened Runtime、签名检查、公证、装订和 Gatekeeper 检查。运行前检查 Actions 变量和 secret **名称**。GitHub 既有 secret 只能在授权的 workflow 中使用。证书、profiles、Sparkle/Tauri 私钥分别确认适用范围。
4. 在 R2 内独立规划每个产品和渠道的前缀。先上传不可变的签名包，经公开 HTTPS 校验最终字节后再切换稳定订阅源。发布任务串行化，并用对象级写入条件拒绝并发和版本回退。仅把 S3 写权限留给发布步骤，应用只读 HTTPS。手动演练使用测试密钥和隔离的 feed，或只保留 Actions artifacts。
5. 交付前验证旧版实际跑到新版、手动入口、自动检查及安装策略、坏签名拒绝和数据保留。记录通过的边界，例如 Actions 签名构建、真实 R2、客户端更换重启。未完成签名或真实升级时明确阻塞项。
