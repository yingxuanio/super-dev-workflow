---
name: apple-cicd-workflow
description: 为 Apple (macOS/iOS) 应用配置 GitHub Actions 线上完整构建与发布流水线：快速 PR 门禁 + 完整发布管线（签名→公证→装订→Gatekeeper 校验→发布），含演练模式、tag 溯源校验、临时钥匙串与凭据清理。当用户要求搭建/修复/审计 Apple 应用的 GitHub CI/CD、xcodebuild 构建工作流、Developer ID 签名公证流水线时使用。源自 lumina-labs-agent 的发布管线标准。
---

# Apple 应用 GitHub CI/CD 完整构建流水线

双工作流架构：**PR 门禁**回答"这个分支能不能编译、便宜的检查过不过"，**发布管线**回答"这个 tag 能不能变成用户手里公证过的 DMG/IPA"。两条路径严格分离。

## 架构原则（每一条都对应真实事故模式）

1. **PR 路径零签名材料**。`CODE_SIGNING_ALLOWED=NO` 编译门禁；丢失/轮换的证书不能阻断合码。签名+公证只属于发布管线。
2. **PR 并发取消**：`concurrency.group: pr-checks-<PR号>` + `cancel-in-progress: true`，新推送杀掉同 PR 的旧运行。
3. **变更检测跳过**：`git diff --name-only origin/<base>...HEAD` 判定重 job 是否运行；PR 门禁权限只给 `contents: read`；每个 job 显式 `timeout-minutes`（self-hosted runner 上卡死的 job 否则无限占机）。
4. **演练模式**：发布工作流必须同时支持 `workflow_dispatch`。手动运行走生产同一条路径，但产物只作为 run artifact（隔离命名），绝不触碰正式发布渠道。凭据/基础设施变更先演练再发版。
5. **溯源校验在花构建分钟之前**：setup job 里 `git merge-base --is-ancestor <tag commit> origin/main`，未合并的 tag 拒绝构建；tag 版本必须与工程 `MARKETING_VERSION` 一致。
6. **临时钥匙串 + if:always 清理**：签名凭据导入 job 内创建的临时 keychain，`security delete-keychain` 放在 `if: always()` 步骤——失败的 job 不许把私钥留在共享 runner 上。
7. **签名链分步化**：build → `codesign --verify --deep --strict` → DMG → `notarytool submit --wait` → `stapler staple`（重试3次）→ `stapler validate` → `spctl --assess`。每步独立，失败即知道死在哪一环。
8. **发布 job 独占写权限**（`contents: write` 只给 publish）；concurrency `cancel-in-progress: false`（发布中途绝不被取消）；cleanup job `if: always()` 等待全部 job。
9. **公证优先 API Key**（`APPLE_API_KEY_ID/ISSUER/P8`），app-specific password（`APPLE_ID/PASSWORD/TEAM_ID`）为兼容回退。
10. **产物跨 job 传递走机器本地 `/tmp/<app>-release-<run_id>`**：GITHUB_ENV 不跨 job，workflow/job 级 env 又没有 runner 上下文，而 `$RUNNER_TEMP` 每个 runner 进程独立——多 runner 共享一台机器时 setup 建的目录 build 看不见（舰队分裂）。/tmp 同机共享 + build job 首步 fail-fast 检测分裂；run_id 保证路径跨重试稳定，失败的 publish job 重跑可复用构建产物。

## 安装

```bash
# 1. 渲染模板（填 __APP_NAME__ __SCHEME__ __XCODEPROJ__ __CHANGE_PATHS__ 等 token）
ruby ~/.agents/skills/apple-cicd-workflow/templates/render.rb \
  --app-name SayIt --scheme SayIt --xcodeproj SayIt.xcodeproj \
  --change-paths "^(SayIt/|SayIt\.xcodeproj/|\.github/workflows/)" \
  --out <project>/.github/workflows

# 2. 配置 secrets（仓库 Settings → Actions → secrets）
# 3. 审计
~/.agents/skills/apple-cicd-workflow/scripts/audit-cicd.sh <project>
```

## Secrets 清单

| Secret | 用途 | 必需 |
|---|---|---|
| `APPLE_CERTIFICATE` | Developer ID Application 证书 p12（base64） | 是 |
| `APPLE_CERTIFICATE_PASSWORD` | p12 导出密码 | 是 |
| `KEYCHAIN_PASSWORD` | 临时钥匙串密码（任意随机串即可，runner 本地） | 是 |
| `APPLE_API_KEY_ID` + `APPLE_API_ISSUER` + `APPLE_API_KEY_P8` | App Store Connect API（公证首选） | 推荐 |
| `APPLE_ID` + `APPLE_ID_PASSWORD` + `APPLE_TEAM_ID` | app-specific password 公证回退 | 回退 |

制作 `APPLE_CERTIFICATE`：钥匙串访问导出证书+私钥为 .p12 → `base64 -i cert.p12 | pbcopy`。

## 发布操作流程

```bash
# 1. 在主分支上把工程版本号 bump 到本次版本（MARKETING_VERSION / Info.plist）
# 2. 合并 PR（溯源校验要求 tag 指向已合入 main 的提交）
# 3. 打 tag 触发完整管线
git tag v1.2.3 && git push origin v1.2.3
# 4. 平时想验证发布路径：Actions → Release build → Run workflow（演练模式）
```

## iOS / TestFlight 扩展

iOS 管线在发布模板之上增加：Apple Distribution 证书 + mobileprovision（安装到 `~/Library/MobileDevice/Provisioning Profiles`，按 Name 去重旧 profile）、`xcodebuild archive -archivePath` + `xcodebuild -exportArchive -exportOptionsPlist`（method=app-store-connect）、`altool --validate-app` 后 `--upload-app`、App Store 提交对 409 STATE_ERROR 做指数退避重试。iOS 构建作为独立 job 与 macOS 分发路径并行、独立报告成败，互不阻塞。

## 审计标准

`scripts/audit-cicd.sh <project>` 逐项检查：YAML 可解析、PR 门禁有并发取消/最小权限/超时/变更检测/无公证、发布管线有演练入口/不可取消并发/溯源校验/完整签名链（codesign+notarytool+stapler+spctl）/if:always 凭据清理。全绿才算达标。

## 常见事故与对策（2026-10 sayit 首次全链演练实战沉淀）

- **runner 上下文只有 step 级**：workflow/job 级 `env:` 引用 `runner.temp` 直接解析失败（Unrecognized named-value）。需要路径时在每个 step 声明，`github.run_id` 保证跨重试稳定。
- **多 runner 进程共享一台机器 = 舰队分裂**：每个 runner 进程的 `RUNNER_TEMP` 互相不可见，setup 建的产物目录 build 看不见。跨 job 产物一律放机器本地 `/tmp/<app>-release-<run_id>`，build 首步 fail-fast 检测。
- **SPM 包 framework 要求 DEVELOPMENT_TEAM**：即使 CODE_SIGN_STYLE=Manual + 指定 identity，swift-crypto 等包的 framework 签名仍要 team。从 `security find-identity` 的身份名 `(TEAMID)` 提取后传入 xcodebuild，不新增 secret。
- **Manual 签名默认无时间戳**：公证报 "The signature does not include a secure timestamp"。xcodebuild 显式传 `OTHER_CODE_SIGN_FLAGS="--timestamp"`。
- **spctl 不评磁盘镜像**：对 DMG 文件 `spctl --assess` 按设计返回 `rejected: Insufficient Context`。正确做法：挂载 DMG，对内部 .app 做 `codesign --verify --deep --strict`（离线确定性）。
- **校验和必须在装订之后生成**：`stapler staple` 会把票据写进 DMG 改变内容，装订前算的 .sha256 与最终产物不符；且用相对文件名写入，否则下载方 `shasum -c` 依赖构建机路径。
- **`gh secret set --body -` 不读 stdin**：会把字面 `-` 存进 secret（公证报 invalidPEMDocument）。用 `gh secret set NAME < 文件` 重定向。
- **workflow_dispatch 可作解析器**：dispatch 时 GitHub 服务端先解析 workflow，比本地 YAML lint 抓得多（上下文可用性、重复键都会 422）。

## 常见事故与对策（继承）

- **公证卡 Accepted 判定**：`notarytool --wait` 的输出用宽松 sed 提取 status，解析不到一律按失败退出并抓 `notarytool log <submission-id>`，绝不静默通过。
- **裸 Mach-O 过不了 spctl**：spctl 只评 bundle/DMG；裸可执行文件用 `codesign --verify --strict` + 公证 Accepted 作为门禁（Gatekeeper 首次运行时在线查公证记录）。
- **DMG 忘记签**：DMG 也要 `codesign --timestamp`，否则 stapler 拒装订。
- **tag 打错分支**：溯源校验（merge-base ancestor）直接拒绝，不烧构建分钟。
- **自托管 runner 上凭据残留**：一切凭据步骤成对出现——准备（创建 keychain/import）与 `if: always()` 清理。
