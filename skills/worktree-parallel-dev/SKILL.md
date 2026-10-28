---
name: worktree-parallel-dev
description: 在任意 git 项目上搭建和检查 worktree 隔离并行开发体系（registry 登记、分支守卫、baseline 校验、pre-commit/pre-push 钩子、资源隔离、合并后清理）。当用户要求支持多 agent/多任务并行开发、防止多个 worktree 互相污染、设置 git worktree 管理脚本、审计 worktree 就绪度时使用。源自 lumina-labs-agent 的成熟模式（CM-340/CM-341）。
---

# Worktree 隔离并行开发体系

让一个 clone 上并行的多个任务（人类或 agent 会话）互不污染：每个任务在自己的 linked worktree 里，登记进 registry，钩子在 commit/push 时拦截跨任务污染，baseline 校验拦截"别的会话动了我的 checkout"。

## 什么时候用 / 不用

- **用**：多个 agent 会话或多人要在同一个仓库并行开分支；曾发生过"一个任务的文件进了另一个任务的 PR"；本地服务/构建产物互相踩踏。
- **不用**：单人串行开发、不需要多分支并行的小仓库（体系本身无侵入，但维护成本不划算）。

## 安装到任意项目

```bash
~/.agents/skills/worktree-parallel-dev/scripts/setup.sh [--force] <project-dir>
```

setup 幂等，做六件事：拷贝 `worktree-lib.sh` / `worktree-manager.sh` / `worktree-guard.sh` 到 `scripts/`；装 `.githooks/{pre-commit,pre-push}`；生成 `scripts/worktree.config.sh`（自动探测主分支）；`git config core.hooksPath .githooks`；.gitignore 加 `.wt-env.sh`；Makefile 追加 `wt-*` 目标（已有 Makefile 则追加，没有则创建）。

**安装后必须人工做一步**：编辑 `scripts/worktree.config.sh`，把 `WT_SENSITIVE_RE` 改成本项目真正的"共享发布面"（所有任务共享、并发编辑即污染的文件），并按需启用资源适配器：

| 配置项 | 用途 | 示例 |
|---|---|---|
| `WT_MAIN_BRANCH` | primary 检出只允许在这个分支上登记 | `main` |
| `WT_PORTS_START/END` | 每 worktree 端口段（有本地服务的项目） | `3738 3798` |
| `WT_DERIVED_DATA=1` | Xcode 项目每 worktree 独立 DerivedData，导出 `WT_DERIVED_DATA_PATH` | `1` |
| `WT_CACHE_DIRS` | 共享并发安全的依赖缓存名（SPM/uv/cargo…），导出 `WT_CACHE_<NAME>` | `"spm"` |
| `WT_SENSITIVE_RE` | 共享面正则；暂存这些文件且兄弟 worktree 也脏时 pre-commit 阻断 | `'^(\.github/workflows/|.*\.pbxproj$)'` |
| `wt_pre_commit_extra()` | 项目自己的 pre-commit 检查（收到暂存文件列表） | 本地化检查等 |

## 日常生命周期

```bash
# 1. 开任务：linked worktree 永远放在仓库目录之外（~/.wt/<project>/<topic>）
git -C <project> worktree add ~/.wt/<project>/<topic> -b feat/topic
cd ~/.wt/<project>/<topic>
scripts/worktree-manager.sh init          # 登记 + 资源隔离 + 记录 baseline

# 2. 干活（.wt-env.sh 已生成；构建类 make 目标会自动 source 它）
source ./.wt-env.sh

# 3. commit/push：钩子自动跑守卫；手动校验用
scripts/worktree-manager.sh verify        # 0=通过 1=未登记 2=有漂移，漂移禁止 commit/push

# 4. PR 合并后清理（三项独立门：PR 已合并 / 检出干净 / 全部已推送）
scripts/worktree-manager.sh prune-merged --dry-run
scripts/worktree-manager.sh prune-merged
```

Make 目标：`make wt-init / wt-list / wt-status / wt-verify / wt-baseline / wt-clean [BUILD=1] / wt-prune [DRY=1] / wt-doctor / hooks-install`。

## 守卫体系（这套体系的核心价值）

**三条铁律**（hook 实现，全部"输入缺失即降级 no-op，检测到污染即大字报+恢复步骤"）：

1. **分支归属**：检出登记在分支 X 上，却在分支 Y 上 commit/push → 阻断。这是"另一个会话在这个 checkout 里切了分支"的信号。
2. **共享面交叉污染**：暂存了匹配 `WT_SENSITIVE_RE` 的文件，且任何兄弟 worktree 对同一文件也有未提交改动 → 阻断。这是一个任务把另一个任务的并发修改扫进自己 commit 的指纹。
3. **baseline 完整性**（pre-push 跑 `verify`）：baseline HEAD 必须是当前 HEAD 的祖先；分支 ref 上有 `.lock`（兄弟操作正在进行）→ 阻断。reset/rebase 挪走历史会在这里被抓住。

**规约**：
- primary 检出只允许登记在主分支（`init` 拒绝其他分支），它是合并、版本提交的共享地面。
- 每次故意切换分支或接受漂移后跑 `wt-baseline` 重新记录；守卫提供 `WT_GUARD_ALLOW_BRANCH_SWITCH=1` / `WT_GUARD_ALLOW_SHARED_SENSITIVE=1` 逃生阀。
- 守卫判定写入 worktree 私有的 `.git/wt-guard-journal.log`（保留 200 行），事后可查"哪个钩子何时拦了什么"。

## 资源隔离原则

- **registry**：`~/.wt-registry/<project-slug>/registry.json`，键为 worktree 绝对路径；写操作全部走 mkdir 锁 + 原子 rename，读者永不看到半截文件。锁持有者死亡且超时才允许接管。
- **TMPDIR**：每 worktree 私有（cksum 路径键）；依赖缓存反其道共享（并发安全），共享根不可写时自动降级为每 worktree 一份。
- **构建产物**（Xcode）：`WT_DERIVED_DATA_PATH` 指向 registry 下的私有目录，构建命令必须显式 `-derivedDataPath`，绝不碰共享 `~/Library/Developer/Xcode/DerivedData`。
- **进程**：`stop-current` 按 registry 记录的端口定位并停止本 worktree 的进程，不误杀兄弟。

## 检查/审计一个项目

```bash
~/.agents/skills/worktree-parallel-dev/scripts/audit.sh <project-dir>          # 静态：文件、语法、hooksPath、registry
~/.agents/skills/worktree-parallel-dev/scripts/audit.sh --live <project-dir>   # + 完整生命周期实测（临时 worktree：init→verify→漂移拦截→钩子阻断→clean→移除）
```

`--live` 是验收标准：漂移必须让 `verify` 退出 2，漂移分支上的 commit 必须被钩子挡下。审计全绿才算搭建完成。

## 改造已有项目时的陷阱

- dev 脚本里硬编码的绝对路径（`/Users/me/projects/foo`）必须改成 `git rev-parse --show-toplevel`，否则在 worktree 里操作的是主 checkout —— 这是最常见的污染源。
- 按"全机器唯一名字"杀进程（`pkill -x MyApp`）会误杀兄弟 worktree 的进程；改用本 worktree 记录的 PID 文件。
- 钩子里 source 任何文件都要先 `[ -f ... ] &&`——macOS bash 3.2 下 source 不存在的文件会静默杀死整个钩子（`|| true` 都救不回来）。
- 所有脚本保持 bash 3.2 兼容（无 assoc array、无 flock、无 `${var,,}`）。
- **每 worktree 私有 TMPDIR 必须存在**：Swift 编译驱动把 TMPDIR 当工作目录，目录被删后构建报 `couldNotFindTmpDir` 神秘失败。构建入口（make 目标/dev 脚本）先 `mkdir -p "${TMPDIR:-/tmp}"` 防御；清理工具绝不许清共享 registry 的 `tmp/` 根。
- **Xcode 项目升级到私有 DerivedData 时去掉 `-clonedSourcePackagesDirPath`**：包目录默认就在 derivedDataPath 内，已随路径隔离；显式指到别处会引入多余的包解析状态。
- **guard 的 registry 路径必须能被钩子独立推导**：钩子环境里没有 manager 的上下文，guard 要按"remote URL basename → `~/.wt-registry/<slug>/`"自行解析，否则静默降级成 no-op（守卫失效是最危险的失败模式——一切正常直到事故发生）。
- **config 的赋值必须无条件**（`WT_X=1` 而非 `WT_X="${WT_X:-1}"`）：manager 预设了默认值，`:-` 形式永远覆盖不了。
- **macOS 上两个 xcodebuild 同时冷构建同一工程会互相卡死**（构建服务竞争）：并行的是"写代码"，构建错峰跑即可； DerivedData 隔离保证的是正确性，不是同时构建。
