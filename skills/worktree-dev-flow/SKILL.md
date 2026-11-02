---
name: worktree-dev-flow
description: Use for code changes that need worktree-based delivery. Reuse the current non-main worktree; create a new one only from main after user confirmation. The current session implements directly — never creates ZCode projects or delegated sessions. Then verify, commit, push, open a PR, and confirm mergeability.
---

# Worktree 开发流程

## 预检与触发

先确认当前上下文，再决定是否需要 worktree：

```bash
git rev-parse --show-toplevel
git branch --show-current
git worktree list --porcelain
git status --short --branch
```

- 当前目录已经是非 `main` worktree：记录路径并复用，后续回合继续使用同一路径。
- 当前目录在 `main`：说明路径、分支和工作区状态，请用户确认“复用当前目录”或“创建独立 worktree”。确认前不创建。
- 当前目录是 detached HEAD：说明现状，请用户选择已有 worktree 或目标分支。
- 当前目录不是 Git 仓库：说明路径，请用户确认项目目录后再继续。
- 在创建前检查注册表；同一任务已有 worktree 时直接复用。

完成 worktree 选择后，由当前会话直接在已选 worktree 内实现。**不再创建 ZCode 项目，也不编排/委派子会话**（2026-09-28 定规）；历史委派脚本 `create-zcode-session.mjs` 已删除，勿重建该流程。

路径和分支一旦选定，记录在任务上下文中，后续测试、提交和修复都沿用它。

## 创建独立 worktree

仅在当前分支为 `main` 且用户确认后执行：

```bash
mkdir -p ~/.crossmind/worktrees
git fetch origin main
git worktree add ~/.crossmind/worktrees/<topic> -b <type>/<topic> origin/main
cd ~/.crossmind/worktrees/<topic>
```

目录使用短 topic，分支使用 `feat/`、`fix/`、`ci/`、`perf/` 或 `docs/` 前缀。注册表使用绝对路径。

## 环境初始化

新 worktree 按顺序执行：

```bash
make hooks-install
make wt-init
uv sync
cd dashboard && pnpm install && cd ..
make wt-preflight
make dev
```

已有 worktree 先运行 `make wt-status`；只有资源未初始化时才补跑 `make wt-init`。端口、数据库和服务状态以 `make wt-status` 为准。`make wt-preflight` 在开工前确认依赖、缓存、数据库和测试入口就绪，失败时会指出阻塞阶段（exit 3）。

## 开发与验证

- 在选定 worktree 中实现需求，保留用户已有改动。
- 前端改动完成后运行 `cd dashboard && pnpm run build:check`。
- 提交前运行受影响测试；交付前运行项目要求的完整测试和 `git diff --check`。
- 提交信息使用 Conventional Commits。`.zcode/` 仅作本地计划，不加入提交。
- 提交/推送被 `[wt-guard]` 拦截时按其输出恢复（分支归属或跨卡发布文件冲突）；怀疑分支被外部流程更新时先运行 `make wt-verify`（exit 2 = 漂移，附恢复步骤）。

## 提交与 PR

```bash
git push -u origin <branch>
gh pr create --base main --title "<type>: <summary>" --body "..."
gh pr checks <PR> --watch --interval 15
gh pr view <PR> --json mergeable,mergeStateStatus
```

PR 正文包含背景、改动和验证。网络命令失败时等待 10 秒后最多重试 3 次。`MERGEABLE/CLEAN` 后向用户报告；用户明确要求合入时再执行合并。

## 冲突与回收

发现冲突时先同步 main，再按双方语义解决，重新运行受影响测试并使用 `git push --force-with-lease` 更新 PR。

PR 合入后先运行：

```bash
DRY=1 make wt-prune
make wt-prune
```

`wt-prune` removes non-primary worktrees with no actual changes (a root
`uv.lock`-only diff is treated as lockfile noise) or whose last use is older
than 30 days. It preserves Git branches and databases. Use
`DRY=1 make wt-prune-merged` / `make wt-prune-merged` when cleanup must be
limited to merged PRs.

手动清理当前 worktree 使用：

```bash
./scripts/worktree-manager.sh clean --current --delete-db --force
```

删除独立数据库前确认 PR 已合入；主 worktree 和共享数据库保留。
