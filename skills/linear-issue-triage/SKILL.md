---
name: linear-issue-triage
description: Triage, create, and batch Linear issues for CrossMind Agent without starting implementation. Use when the founder asks to 建卡, 整理/排查 Draft/Todo/Backlog, 推荐可推进的 issue, 标记重复, 补验收, or run Linear triage. Do not use when the founder says 安排修复任务, 处理 Linear Issue, 修 bug, or 推进某张卡 — those go to orchestration-dev-dispatch, not this skill, not CrossMind Tasks, not in-session coding.
---

# Linear Issue Triage

整理 Linear，让卡片可执行、可分批。本 skill **只做 issue 工作**：不写代码、不 `task_create`、不在本会话改产品仓。

「安排修复任务」「处理 Linear Issue」「修这张卡」= 交给 `orchestration-dev-dispatch`，不是建 CrossMind Task，也不是这里直接修。本 skill 只在需要先分诊/建卡/分组时被编排路径调用。

默认产品团队从当前 Agent 的 Linear 连接解析（取连接配置里明确归属的产品团队）；未点名团队且解析不出唯一结果时先问，不要写死某个团队 ID。Growth 卡（`GRW-*`）单独看待，不要和 Agent 工程批次混排。

## 工具约束

- 每回合最多 2–3 个并行 Linear 调用；用 `updatedAt` / `state` 缩小列表。
- 收集/triage 时只读相关卡、已实现行为和够用的源码逻辑，目的是理解用户说的需求和 Bug 实质（要达成什么、现在实际发生了什么、和已有实现差在哪）。
- 合理控制挖掘深度：能讲清现象与预期就停。不要为定位修复点、列文件或设计改法而深挖。
- 先读现有 issue 和当前产品状态，再问环境/版本/复现步骤。
- 状态流：`Draft → Backlog → Todo → In Progress → In Review → Released/Done`。这列由 GitHub↔Linear workflow 驱动，**不要手改状态**来「跟上」PR。
- 多卡共用一个 PR 时，正文**一行一个** `Fixes CM-123`，不要写成 `Fixes CM-123, CM-124`（创建时会只挂第一张）。区间、标题、分支名都不够。核验每张卡上的 GitHub PR 附件；漏挂改 PR 正文，不要手改 Linear。细则在 `orchestration-dev-dispatch` 的「PR 关联」。
- 父卡/史诗不进执行批次，只推子卡；子卡全部完成后才关父卡。

## 建卡与改写

需求明确时立刻写进 Linear，描述保持最短可执行。把理解补进描述，不要写成排障或实施计划：

- 改的是一族交互里的某一个面（同一组件、同一工具卡家族、同一打开方式）时：找出还在用旧交互的兄弟面，当场用封闭选择问要不要一并收进这次。不要自己在描述里写「X 不在这张范围」就收工。
- **Bug**：现象 + 预期。可用一两句交代实质（和哪张卡/哪次实现的关系、用户可见的因果）。
- **Feature / Improvement**：能力 + 结果。同样可补对现有行为的理解。
- 不必赘述「平台约束」和验收清单，除非桌面/移动差异本身就是需求的一部分。
- 描述里不要写代码改动方案、实施建议、改哪些文件、怎么修。
- 先填 **Project** 和 **Label**；能归属就不留空。
- 判「验收不通过」前先核**发布包含关系**：PR 已合入 `main` 但合入点晚于最近一次 release 时，生产验不到是发版缺口，不是残留；修复确在生产、验收仍不过才开残留卡（用 `gh api .../compare/<release-sha>...main` 或 PR `mergedAt` 与 release 时间对比）。
- 已 Released 的卡若修复不干净，或同一问题反复出现：保留原卡作历史，**另开残留卡**并 `relatedTo` 原卡，不要把 Released 卡重新当执行入口。新卡除 Bug/Improvement 外必须加 **Residual**。编排时先找原实现会话直接安排；找不到再升档新开。原卡 Released 时告知实现会话：修复 PR 已合入，但验收未过（见 `orchestration-dev-dispatch`）。

禁止：把「已附截图」写进描述却没挂上附件；附件挂不上就明说。截图必须嵌进 issue description，只出现在附件栏通常看不见。

## Draft / 重复 / 依赖

- **默认：反馈内容清晰且可执行时，直接建为 `Todo`。** 只有需求仍不清楚，或创始人明确要求暂存时，才使用 `Draft` / `Backlog`。不要因为尚未安排实现、优先级普通或还没进入当前批次而降到 `Draft` / `Backlog`。
- 需求不清 → 留 `Draft` 或改回 `Backlog`，**不要标 Todo 后拿去编排**。创始人明确要求先排期但暂不执行时可放 `Backlog`。
- 卡住很久但仍有价值的 Backlog/Draft：记成待澄清/待讨论，**不要为了推进而升 Todo**。怎么汇总（聊天里问、还是排程邮件）由当前工作方式决定。
- 与已有卡重复 → `duplicateOf`，不要并行维护两套验收。
- 有硬依赖 → `blockedBy`，不要口头依赖。
- 无优先级且不可执行 → 留下 Draft，只补最小澄清，不要假装可开工。

## 分批（推荐下一批时强制）

创始人问接下去安排/编排什么时，直接给出下一份编排计划（交给 `orchestration-dev-dispatch` 的格式）。一份计划最多 **5 组**会话。**只从 Todo 出计划；Backlog / Draft 一律不进编排。** 已有未合并 PR（含 draft）= Linear 卡片上已有 GitHub PR 附件。不要只看 PR 正文自称 `Fixes`（逗号列表会漏挂）。本窗口已派尚未合入的卡也不进新计划。

按 **模块相近、处理逻辑相近、或思路类似** 尽量一组多卡，不要因为张数多而拆。验收或回滚边界不同的卡保持独立卡片，但可以进同一组。

不要把这些和大项混批：容器隔离、桌面内存、iOS 上架、Skill 生命周期、父卡本身。

功能 vs UI 不再作为硬拆分；同一模块里行为+展示且思路类似，可以同组。无关模块不要硬塞。

## 沟通

- 对人说话：标题 + 用户影响；Linear ID 只作括号引用。
- 理解、分组、下一步写在 **issue comment**；不要在评论里堆问题清单。
- 只有代码和卡片都无法决定的范围/优先级，才单独问创始人。
- 本 skill 的输出止于：triage 结果、下一批编排计划（最多 5 组）、需要的决策。**不要**在这里 spawn、不要建 CrossMind Task。确认后交给 `orchestration-dev-dispatch`。
- 排程/TaskRun 按天闭环时，读 `references/autonomous-loop.md`。
