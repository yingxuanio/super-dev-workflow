# 选择更新器并验收发布

## 原生 Sparkle 2

- 使用一个进程级、主线程上的 `SPUStandardUpdaterController`。SwiftUI 菜单把 `canCheckForUpdates` 的 KVO 变化桥接到可观察状态。用 `checkForUpdates(nil)` 走标准 UI。`SUEnableAutomaticChecks` 打开后台检查，`SUAutomaticallyUpdate` 打开自动下载及安装（通常退出时）。保留需要授权或重启时的标准 UI。只在产品明确需要更新进度、延后或自定义安装 UX 时实现自己的代理。
- 每个应用及独立试验渠道使用自己的 EdDSA 密钥。用 `generate_keys --account <bundle-id>` 生成并保留可恢复的钥匙串备份。`SUPublicEDKey` 可公开，`generate_keys -x` 的导出内容进入 Actions Secret。`SUFeedURL` 和 enclosure 使用 HTTPS。支持签名 feed 的 Sparkle 版本可启用 `SUVerifyUpdateBeforeExtraction` 和 `SURequireSignedFeed`，并明确选定签名失败的回退策略。严格拒绝设 `SUSignedFeedFailureExpirationInterval=0`，需要可恢复的私钥和经过验证的换钥方案。
- 沙盒构建保留现有 entitlements。`SUEnableInstallerLauncherService=true` 并允许 `<bundle-id>-spks` 和 `<bundle-id>-spki` Mach lookup。已有网络客户端权限时使用应用进程下载。Xcode Archive + Developer ID Export 后检查整个 bundle，尤其 Sparkle.framework、Autoupdate、Updater.app 和 XPC helper 的签名团队、时间戳和 Hardened Runtime。用 `otool -l` 检查最终应用可通过 `@executable_path/../Frameworks` 找到内嵌 framework，并实际启动导出后的应用。使用 `codesign --verify --deep --strict` 做签名验证。签名保留嵌套代码自己的 entitlements。
- 核对每个使用受限能力的 app/appex 都有自己的 Developer ID profile 和实际嵌入结果，尤其 iCloud、APNs、App Groups。ZIP 走 `ditto -c -k --sequesterRsrc --keepParent`，先提交公证，取得 `Accepted` 后把票据装订到 `.app`，验证后重建最终 ZIP。DMG 则针对最终分发格式检查公证、装订及实际安装路径。Sparkle 签名必须覆盖下载到的最终字节。
- 固定 framework 和工具版本，工具包核对上游 SHA-256。在只含候选包的目录运行 `generate_appcast --ed-key-file - --maximum-deltas 0 --download-url-prefix <https-prefix>/ <dir>`；从 stdin 喂私钥。检查 app 的 `CFBundleVersion`、`CFBundleShortVersionString`、最低系统、`length`、`edSignature`、URL 并验证 feed 和包签名。用错误密钥时工具可能仍生成缺少 enclosure 签名的 XML。签名后的 XML 按字节发布。单条目适用于一套兼容范围和通用二进制的完整更新。有不同架构、系统最低版本或渠道时，按需保留对应条目或拆分 feed。

## Tauri 2

- 沿用 `tauri-plugin-updater`、`updater:default`、`plugins.updater.pubkey/endpoints`，用 `check()`、`downloadAndInstall()`、应用重启 API。需要用户可控安装时沿用项目现有设置界面。使用 Tauri 对应格式的私钥和 `.sig`，以及经过签名和公证的 updater `.app.tar.gz`。初始下载可另提供 DMG。最终文件布局确定后再计算签名。
- `latest.json` 对到实际 updater artifacts 的 `darwin-aarch64` / `darwin-x86_64`（或该项目已验证的通用 target 映射），每项的 URL 绑定对应文件的签名。版本筛选沿用项目语义。对旧版真实客户端验收架构选择和重启行为。

## Actions 与 R2

- 稳定发布触发源沿用项目的可追溯 tag 或正式 GitHub Release。预检提交与发布分支的关系及 tag 和 marketing version。Apple Feed 的版本排序由 `CFBundleVersion` 决定；确保连续发布严格递增，单次运行重试保留相同版本身份。签名环境凭据验证用手动演练。
- 临时钥匙串隔离证书，`always()` 清理钥匙串、解码后的私钥和临时 profiles。多 job 用 Actions artifact 交接文件，除非确认使用同一可信 runner。只需要上传 R2 时 `contents: read` 即可。构建环境的 Xcode 与 SDK 版本须实测。
- R2 S3 端点是 CI 写入入口，自定义域名是客户端公开读取入口。用对象写入 token 并尽量限制到专用 bucket。版本包写入时用 `If-None-Match: *`，同一 key 保持内容不变。可以用版本 + build + SHA-256 做 key，避免重新公证产生不同字节时撞上原先的不可变包。Feed 读自 R2 源站，核对有效签名和现行版本，再用 `If-Match: <ETag>` 或首次创建条件提交。HTTPS 回读验证传输内容。稳定 feed 设缓存旁路或短重验证，版本包缓存可长期使用。失败若只写过包，保留当前 feed。已提交的同版本重试验证已有 feed 和包。回滚通过发布递增 build 的修复包，并考虑数据库兼容性。

## 验收

- 构建直发版、商店版、同工程涉及的平台。检查实际产物的 feed、公钥、框架和签名、profiles、最低系统及架构。
- 真实 R2 演练使用单独路径、单独密钥和两个版本。验证上传后先能下载包、feed 正常前进、同版本重跑不覆盖、错误签名或错误字节无法推进。只清理由本次演练创建的对象。
- 在干净的测试用户或虚拟机，从 HTTPS 安装有隔离 feed 的旧版。验证自动发现与下载、安装和重启后版本号、既有数据及组件正常。手动触发、损坏签名、断网、无更新、应用不可写或需提权时分别检查反馈。任何未执行的验收只记为待验证。

## 实作参考

- BatteryMe 的 `BatteryMe/UpdateManager.swift`、`BatteryMe/Info.plist` 和 `.github/workflows/build-release.yml` 展示相同 Sparkle controller、可选自定义状态、Developer ID 公证及 R2 appcast。合并历史 feed 时应先区分确实不存在与读取失败。
- Lumina 的 `docs/release-publishing.md`、`scripts/publish_r2_release.py`、`dashboard/src/services/desktopUpdates.ts` 展示 Tauri 客户端、分架构、profile 嵌入、发布顺序及隔离演练。
- Sorthings 的 `apple-native/Sorted4/project-macos-direct.yml`、`.github/workflows/apple-macos-release.yml` 和 `apple-native/Sorted4/MACOS-RELEASE.md` 展示沙盒原生直发、多扩展、签名 feed 和带条件的 R2 实现。
- [Sparkle programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/) · [Sandboxing](https://sparkle-project.org/documentation/sandboxing/) · [Publishing](https://sparkle-project.org/documentation/publishing/) · [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) · [R2 conditional writes](https://developers.cloudflare.com/r2/api/s3/conditional-operations/)
