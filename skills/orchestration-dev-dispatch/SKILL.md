---
name: orchestration-dev-dispatch
description: Dispatch Linear/product coding work to local-project sessions. Default for 安排修复任务, 处理 Linear Issue, 修 bug, 推进某张卡, 安排开发, Code Review, spawn orchestration. Session title must include a requirement summary, not IDs only. Match an existing project first; never create CrossMind Tasks, never edit the product repo here, never mkdir workspace repos/ unless founder asked or no Computer is connected. Do not use for 建卡/Draft triage, or for recurring automations.
---

# Orchestration Dev Dispatch

「安排修复」「处理 Linear Issue」「修这张卡」默认走本 skill：**编排出去**。不要在本会话改产品仓，不要 `task_create`。

**权责：** 本会话只分诊、派活、对照验收、并在无风险时合入。**不要手改 Linear 状态**（In Progress / In Review / Done / Released）——GitHub↔Linear workflow 会随 PR 关联自动走。产品仓的 commit / rebase / push / 开 PR 一律由编排出来的实现会话做。漏开 draft PR 时，给该实现会话发「先开 draft PR」，或另开一条编排会话去开；**不要**在本会话对产品仓跑 `git` / `gh pr create`。合入见下方「合入」。

Issue 怎么分组仍可由 `linear-issue-triage` 准备；一旦措辞是安排/处理/修复，或问「接下去安排/编排什么」，就进入编排计划，而不是建 CrossMind Task。

## 工作模式（会话内事前确认）

一次编排先定**工作模式**，定下后本次会话沿用，除非创始人主动切换。模式跟随会话，不是跨会话规则。

- **交互式（默认）**：编排计划先用呈现工具（`orchestration_present_plan`）给创始人过目，他确认后才派；派出的实现会话走 **Plan 模式**，计划通过后再继续。不确认不派。
- **持续交付**：只在创始人明确说「持续滚动推进 / 持续交付」时启用。不出计划确认卡，按已确认方向直接派；派出的实现会话用 **Full access**，不套 `plan` / `acceptEdits`。

模式切换只在当前会话内记着，不写进 learnings。

**确认是编排层的关卡，不是实现会话的。** 经编排派出的实现会话不要再出计划确认卡——派发确认已在编排计划卡上完成。实现会话读到本 skill 时只执行派发目标（内部再弹确认卡等于让创始人批两次，会被直接拒掉，零产出）；只有派发目标本身缺失或矛盾时才停下来问。2026-10-24 实例：CM-574 实现会话自我套用「交互式先确认」，弹出第二张卡被拒，整个会话空转结束。

## 开工门禁

缺一不可才 spawn：

1. 创始人说了安排/处理/修复，点名了卡，或问「接下去安排/编排什么工作」。问下一批时**当场给出下一份编排计划**，不要只说「要不要排」。未点名具体卡时，只从 **Todo** 分诊下一批；已派未合入的卡（即使仍显示 Todo）不要写进新计划。**Backlog / Draft 原则上不进编排**，即使标题看起来可做；需求不清先改回 Backlog，不要排进实现会话。点名的卡若仍是 Backlog，先确认是否升 Todo，未升则不派。对**已落地批次**做浏览器测试 / 验证 / 补 e2e / 再跑测试：不要 spawn，给对应实现会话发消息（见「结果回来之后」）。**Residual / 升档续做**能定位原实现会话时，同样不要新 spawn，直接安排到该会话（见「Residual 续做」）。
2. **按当前工作模式行事。** 交互式：先陈述编排计划、等明确确认后再 spawn，确认前禁止 `orchestration_new_session`，也禁止给实现会话发开工消息。持续交付：按已确认方向直接派。无论哪种模式，一轮最多 **5 组**会话（一组 = 一场 `orchestration_new_session`），计划写清：每组哪些卡、Runtime + 模型、会话模式（见 Spawn 规则）、Residual 走原会话还是升档新开。确认来自当场对话，或该工作所属 Task 事先约定的渠道。
3. 可先只读核对项目 / Runtime / 模型，用来把计划写准确；只读发现不算开工。
4. 每组按 **模块相近、处理逻辑相近、或思路类似** 尽量多卡，不要因为张数多而把一组拆成多场。组与组之间才按模块切开。开发类且 worktree / 开 PR 的偏好未知时，先问再派（见「偏好」）。
5. 已匹配到已注册本地项目（见「项目」）。没有匹配就停，不要在本会话修代码，也不要建 `repos/` 目录凑合。
6. 一张卡若仍是父卡/史诗，改派子卡。
7. 卡片必须是 **Todo**（且尚无未合并 PR），或续做已在跑的 In Progress。已有 open/draft PR 的卡不要当新 Todo 再派，续做该 PR / 原实现会话。**Backlog 不派。**

实现会话完成后由本会话判断合入（见「合入」）。发版 ≠ 合入，必须另作确认，每窗口最多一次。

排程/TaskRun 要按天闭环时，读 `references/autonomous-loop.md`，不要把那套流程写进一对一对话。

## 建卡自检（成卡时第一道门）

从创始人一句话成卡（或把现成卡排进批次）时，先过一遍这三个问题再派。这类风险 CI 和单元测试都测不出来：成卡那一刻发现成本最低，合入之后发现成本最高。founder 2026-10-19 指令：**风险小的纯前端 / 文案卡也不豁免。**

建卡动作遵守 `linear-issue-triage` 的「建卡与改写」规则（现象式描述、Todo 默认、duplicate/blockedBy）。**其中的硬性字段规则在这里重申：每张卡必须带 Project 和 Label（能归属就不留空）**——2026-10-19 连续 7 张卡漏带，founder 要求复盘；派发会话内建卡最容易跳过 triage skill，漏的就是这条。

1. **组件一致性**：这个需求会不会重复造轮子？仓库里有没有该复用的现成组件 / 工具函数？有疑点就写进卡（验收里写明「优先复用 XX」或「确认不存在可复用组件」），让实现会话优先复用而不是新造。
2. **设计规范冲突**：改动会不会和既有页面的 token、间距、交互模式打架？涉及 UI 时，验收里加一条「与现有 XX 页面/组件保持一致」。
3. **遗漏**：验收点本身有没有漏（边界、空态、旧入口、i18n、移动端宽度）？卡片只写现象时，把验收补到「合入者能逐条核对」的粒度。

自检发现的问题直接改进**卡片**再派；prompt 仍只给卡上已有内容，不在 prompt 里另加私货。「Code Review」门禁（二度门禁）会带着这些疑点做独立复核。

## 选目标

顺序：**创始人点名 > 台式机优先 > Runtime harness > 模型成本/智能档**。

1. 先 `orchestration_list_projects`，按仓库名/路径/团队匹配已有 `project_id`（Agent 工程通常是 `lumina-labs-agent`）。
2. `orchestration_list_runtimes` + `orchestration_list_models` 核对在线目标和 **当场模型 id**。
3. 产品仓库开发一律 `execution_host=local`，带该项目 `daemon_id`。不要用 Cloud Runtime 改本地产品仓。
4. 未点名时按下面路由选，回复里只说 Runtime + 模型。不要汇报哪台机器、是否在线、是否降级。

## 项目

优先匹配，不要新建。

- 已有项目能对上 → 用那个 `project_id`。
- 多个都像 → 停下来问创始人。
- 一个都没有 → **先确认**再 `orchestration_create_project`。未确认不要创建。
- **不要**在本 Agent 工作区建 `repos/` 子目录来放产品代码。例外只有：创始人明确要求在这边建独立站/应用，或当前没有任何已连接 Computer。

## 机器

有台式机就用台式机（用 `host_label` 判断 desktop/studio，不要写死某一台名字）。没有台式机再用其它在线 Computer。

机器不在线、换 host **一律不告诉创始人**。

## 智能高低（编排用，不是报价单）

同一名字在不同 Runtime 里不是同一回事：harness 也算智能。大致从低到高：

**Claude Code**  
Haiku 4.5 < Sonnet 5 < Opus 5。Opus 适合基座/跨层；Haiku 只适合极小改动。

**Codex**  
`gpt-5.5` < `gpt-5.6-luna` < `gpt-5.6-terra` < `gpt-5.6-sol` < `gpt-6-luna` < `gpt-6-sol`;`gpt-6.1-sol`、`gpt-6-astra` 更高档(未逐档验证,不要跳到顶)。默认用 **`gpt-6-luna`**(2026-10-18 Ivan 指令,`gpt-5.6-luna` 已过时);升档用 `gpt-6-sol`。

**ZCode**  
`GLM-5.3-Flash` < `GLM-5-Turbo` < `GLM-5.3`。Flash 日常；满血 5.3 才升档。

**Cursor**  
`auto` 最省，由平台路由，智能不固定。家族大约：Composer / Flash / Mini < Grok / Sonnet < Codex 5.3 / Luna < Terra / Sol < Opus 5 Thinking。同一家族里 effort 是 none < low < medium < high < xhigh < max；`Fast` 后缀更快更便宜、略降智。Auto 失败再指定更高档，不要一上来锁死 Opus。Fable 智高但不走 ZDR，不当默认。

**Hermes**  
智能等于所选底层模型，但编码 harness 弱于 Claude/Codex/Cursor，同等模型有效能力更低。仅点名使用。

**Cloud CrossMind**  
Fast/Lite（Flash 档）< Pro（Sonnet 档）。只用于云端 Agent 任务。

默认停在低档：Codex Luna、ZCode Flash、Cursor Auto。升档沿着上表往上走一档，不要跳到顶。

## 成本档：默认便宜，升档要有理由

**默认用 Flash 或 Luna。** 主要工作不允许一上来 Opus / Sol / GLM-5.3 满血。

| 档 | 何时 | 模型 |
|---|---|---|
| 默认 | 绝大多数 Bug、UI、补测试、边界清楚的小 Feature | Codex `gpt-6-luna`；ZCode `GLM-5.3-Flash`；Cursor `auto` |
| 升档 | 基座 Feature；跨层协议/daemon/额度口径；**Residual**（验收不通过或反复出现）；同一卡用默认档已失败或返工仍不合格 | Claude `claude-opus-5`；Codex `gpt-6-sol`；ZCode `GLM-5.3`；Cursor 离开 Auto 的指定高档 |

**额度均衡（2026-10-18 Ivan）：** 同批默认档任务在 Codex `gpt-6-luna` 与 ZCode `GLM-5.3-Flash` 之间按各账号额度余量分配，适当用 Flash 分流，不要全压单一账号。派发前看 `orchestration_list_runtimes` 的 usage，耗尽的账号不派。

**模型新鲜度（2026-10-25 Ivan 追问后立规）：** 梯子表是基线不是天花板。每次编排先看当场 `orchestration_list_models`：同一家族出现更高代次或浮动别名（`sonnet`/`default` 这类跟随最新的 id）时，默认用新版，不要惯性沿用表里的旧 id——校验「id 有效」不等于校验「菜单有更新」。只有需要可复现性时才钉死具体版本 id。发现菜单与表格不符，当轮以菜单为准并回填表格。

**额度轮动的数据边界：** usage 只在部分 runtime 暴露（当前实测：zcode、cursor）。有 usage 的按余量分配（上条额度均衡规则）；没有 usage 字段的（codex、claude）无法按额度轮动，不要假装做了额度判断——用家族/代次轮动替代，并在选型理由里如实说「无额度数据」。

**Residual 标签开局即升档**，不要再用 Luna / Flash / Auto。验收不通过或反复出现本身就是理由，不必再等默认档失败一次。仍沿上表升一档，不要跳到 Astra / Opus max。能定位原实现会话时，优先续做该会话（见「Residual 续做」），不要为了换模型而丢掉原会话上下文。

升档必须同时满足：说得出为什么默认档不够（Residual 卡已满足）。一次升档失败再汇报，不要连续烧高档。

审美只在 UI 批次且已升档时考虑。Cursor 日常用 Auto（最省）。不要用 Fable（NO ZDR）当默认。

## Runtime harness

Claude / Codex / ZCode 可传 `thinking_level`（默认档用 `medium`，升档用 `high`）。Cursor / Hermes 不要传 thinking。

| 需求 | Runtime | 默认模型 | 升档模型 |
|---|---|---|---|
| 边界清楚的 Bug / 脚本 / 测试 | `codex` | `gpt-6-luna` | `gpt-6-sol` |
| 小卡吞吐 | `zcode` | `GLM-5.3-Flash` | `GLM-5.3` |
| 布局、列表、头部、Settings 交互 | `cursor` | `auto` | 离开 Auto 的指定高档 |
| 基座 Feature、会话协议、daemon、上下文口径 | `claude` | 仍先 Luna 不可用时才上 Claude；Claude 侧默认不要 Opus，升档才 `claude-opus-5` | `claude-opus-5` |
| 特定模型家族 | `hermes` | 仅创始人点名 | — |
| 云端 Agent 任务 | `crossmind` | `tier-lite` / Fast | `tier-pro` |

不要默认：`hermes`、Cloud 改本地仓。ZCode 若 `session/send: context canceled`，改 Codex Luna，不要连着重试 ZCode。

## 偏好

开发类任务，偏好未知时先问，本会话已有答案就别再问。可以一次问两件：

1. **Worktree：** 开（可并行多组）还是关（同一仓库一次一组）。
2. **开 PR：** 是否开 PR。合入按「合入」节（无风险 squash，不必再问）。发版仍要点头。未回答或直接说编排/开工时，**默认开 PR**。不要把「没回答」当成不开 PR。本会话已有 worktree / PR 答案就别再问。

- **Worktree 开**：一批一个 worktree，不要在 `main` 检出上改。功能 / UI / Review 可同时编排。
- **Worktree 关**：同一仓库一次只派一组。不要并行多组抢同一工作区。
- **开 PR 开（默认）**：prompt 写清「PR 关联」节的正确写法：一开始就开 draft PR；正文先写完整说明（问题、根因、改动、验证），**末尾**一行一个 `Fixes CM-xxx`；禁止逗号列表，也禁止正文只剩 Fixes。做完后把 draft 标为 ready。不要代写分支名、base、标题。不要让实现会话去改 Linear 状态。
- **开 PR 关**：只有创始人明确说不要开 PR 时才省略。不要在 prompt 里提 PR。

Code Review 只读时不必为 worktree / PR 再问。

## Spawn 规则

- 仅在当前模式允许时才 `orchestration_new_session`（`subscribe=true`）：交互式必须先经计划卡确认；持续交付按已确认方向直接派。
- **会话模式：** 交互式 → `permission_mode: "plan"`，prompt 写「计划通过后继续」；持续交付 → `permission_mode: "bypassPermissions"`（Full access）。排程 / TaskRun / 其它 Agent 及一切编排派发**默认 `bypassPermissions`（Full access）**——founder 2026-10-01 指令：除非计划里存在需确认的重大风险或方向决策，否则不要依赖创始人逐条审批（acceptEdits 下命令审批会在创始人离线时段把会话整夜卡死，2026-09-30 三组全部如此）。重大风险/方向决策在**计划层**确认，不落到命令审批。
- **本地 Cursor：** 计划模式目前会被跳过、直接开干（CM-268）。未修好前别拿 Cursor + `plan` 当审批闸，改 ZCode / Claude / Codex。
- **本地 Codex：** 计划模式目前是磁盘只读沙箱，模型只报「权限只读」（CM-269）。未修好前，需要读生产日志、给改造建议的排查不要指望 Codex 的 Plan 回合完成。
- **会话名称 `title`**：只写 issue 编号 + 一句话（`CM-278 Cloud 仍拿不到编排装的 Linear MCP`），多卡用短概要并列。禁止只写 `CM-150/141/132`。worktree / 开 PR / 权限模式只是编排参数，不要写进标题，也不要写进 `goal`。
- 项目目录、`project_id`、Runtime、模型、daemon、thinking 只放编排参数，**不要写进 prompt**。
- prompt 只给卡上已有内容：issue ID、标题、描述/验收。不要补推测性需求、实现路径、额外边界、项目目标、目录或「用某某模型」。
- Worktree 已确认、开 PR 默认或已确认时，各加一句行为指令即可，不要夹带路径。**Worktree 行为指令必须预答 checkout 问题**（2026-10-18 CM-515/CM-520 教训）：仓库 `worktree-dev-flow` 规则会让实现会话开跑前先问「复用某 worktree 还是新建」，AskUserQuestion 停在审批面板、会话空转结束。prompt 里直接写明：「从最新 main 创建本卡独立 worktree 与分支，不要复用其他卡的 worktree；此选择已在派发时确认，不要再就此提问」。
- **续做半成品**：上一次实现已留下独立 worktree / 未提交 diff 时，先定位那棵树（目录名或分支名即可），新会话 prompt 写明「在该检出继续，禁止 `git worktree add` 新树」。不要再开一套从零实现。绝对路径不必写给创始人。
- **分组：** 模块相近、处理逻辑相近、或思路类似的卡尽量进同一会话，能装多少装多少。一份编排计划最多 5 组会话；不要把相近的卡拆成第 6 组，宁可靠后一轮。每张卡仍按原文分开验收。无关模块不要硬塞。容器隔离、桌面内存、iOS 上架、Skill 生命周期、父卡本身仍单独开。
- 功能 vs UI 不再作为硬拆分。同一模块里既有行为又有展示、且思路类似，可以同组。
- 批次里只要有 **Residual** 卡，整场会话用升档模型（见「成本档」）。不要和普通卡混进仍走 Luna/Flash/Auto 的会话。**例外：** Residual 已定位到可写的原实现会话时，续做该会话，不另开升档会话。

## Residual 续做

升档 / 残留任务先找**原本做那张卡的实现会话**（Linear 附件与评论里的 PR/会话、编排 session 引用、标题含原卡号）。

- **找得到且仍可写：** 不要 `orchestration_new_session`。确认计划后直接给该会话发开工消息。
- **消息必须写明：** 新残留卡 ID 与当前现象；原卡若已是 **Released**，写清「之前的修复 PR 已合入，但验收未过」；原卡还不是 Released 则只写验收未过、不要谎称已合入。
- **找不到、写不进去、或属于系统故障：** 再按升档模型新开会话。系统故障仍不要往坏会话里追（见「结果回来之后」）。

Prompt 里写清：不要扩大范围到未点名的卡，不要顺手重构。

## 结果回来之后

先读结果，再决定要不要动那条会话。

- **系统问题**（通道取消、sdk 丢失、Agent not found、会话写不进去）：汇报。**不要** `orchestration_send_message` 重试，也不要往原会话追加「再试一次 / 补充说明」。
- 需要追加工作（浏览器测试 / 验证、补 e2e、再跑测试、改验收、漏了开 draft PR、PR 没挂上本组每张卡）：**先问创始人**，同意后给**实现会话**发消息。不要当成新批次去 `orchestration_new_session`。实现会话已结束但仍可写时同样发消息；写不进去再汇报，不要默默新开验证会话。不要在本会话代做产品仓 git/PR（合入时改描述/squash 除外，见「合入」）。
- 实现不合格、要换模型/Runtime：开**新会话**，不要在原会话里追问。**Residual 例外：** 能定位原实现会话则按「Residual 续做」发消息，不要为升档再开一场。
- ZCode `session/send: context canceled` 或 `Agent not found: None`：不要重试 ZCode，也不要给原会话发消息；需要续做时另开 Codex Luna（仍算同一已确认批次）。
- ZCode 启动即崩 `unexpected error: }`（~7 秒、零消息产出）：与 `context canceled` 同类通道故障。2026-10-18 已 2/2 复现（CM-516 首派、CM-518），同日不再派 ZCode，改 Codex Luna；次日恢复使用前先拿一张小卡试跑验证通道已恢复。
- Codex resume `thread already has an active writer` / thread-store conflict：不要给原会话发消息；另开新 Codex 会话续做。

## Code Review（合入前的二度门禁）

**每个实现 PR 合入前，都要过一场独立的对抗性 review 编排会话——没有例外。** 实现会话的自验只能证明「代码按实现者的理解跑通了」；组件不一致、设计规范冲突、验收遗漏、协议/权限风险，都要第二双眼睛。founder 2026-10-19 指令：风险小的纯前端 / 文案卡同样不豁免。

- 时机：实现会话跑完、PR 已开、CI 绿之后，另开一条 review 会话，review 过关才合入。不要让实现会话自己审自己。
- review 会话是同一已确认批次的收尾门禁，不需要再走一轮计划确认。
- 避开实现会话用过的**同一个模型 id**；优先换 Runtime。实现是 Luna / Flash / Auto 时，review 用不同家族（例如 Claude Sonnet/Opus，或 Codex Sol），不要再用 Luna 审 Luna。
- **评审家族按实现家族确定性轮换（2026-10-25）**：GLM/ZCode 实现的评审走 Codex 侧（Sol 档），Codex 实现的评审走 Claude 侧——不要让连续多个评审全落在同一个模型上，同模型评审的盲区是相关的。评审模型用浮动别名或当场最新代次（见「模型新鲜度」）。
- Review 会话只读代码、把结论写上 PR：**review 结果必须评论到对应 PR 上**（founder 2026-10-19 指令）。明确的代码问题用**行级评论**（inline comment）钉到具体行；整体评估、验收对照、总裁决用普通 PR 评论。review 会话不顺手改代码，除非创始人把「改」也算进这批。
- Review prompt 给：PR 链接或 diff 范围、每张卡原文（标题+验收）、建卡自检标记过的疑点。逐卡对照验收核，不只看代码对不对。
- 检查面：实现是否覆盖全部验收点、有没有**遗漏**（边界 / 空态 / 旧入口 / i18n / 移动端宽度）、UI 卡的**组件不一致**（重复造轮子、该复用的现有组件没用）与**设计规范冲突**（token / 间距 / 交互模式和既有页面打架）、有没有引入新的协议 / 数据 / 权限风险。
- 结论无 finding → 按「合入」合。有 finding → 给**实现会话**只发一条指针消息：「你的 PR 上有 review 评论，去读并处理」——**不要把 finding 内容复述给实现会话**，它自己读 PR 评论（founder 2026-10-19 指令：评估需要调整时安排原会话自行读取 PR 评论，不经中转）。修完复核再合；实现会话写不进去时另开新会话修，review 会话本身不修代码。
- **Finding 应修尽修**（founder 2026-10-19 指令）：review 提出的问题默认全部在本 PR 内修掉，再合入；不按严重度挑着修。唯一的例外是某个 finding 的修复本身会引入**额外连锁风险**（跨层协议牵动、影响面扩散到本卡之外）——这种显式说明风险后可转后续小卡，其余没有"清理级别就不修"的豁免。
- **PR 合入前不归档实现会话**：返工循环收尾前归档会导致返工指针发不进去、被迫另开会话重读现场（2026-10-19 CM-535 踩过）。清理 10 个未归档槽位时，先归档已彻底收尾的（PR 已合、结果已消费），PR 还开着的实现/返工会话保留到最后。
- 被创始人直接点名 review / 审 diff 时同样走本节，只是对象换成他指的 PR / diff。

## 失败处理

| 失败 | 做法 |
|---|---|
| `Selected model is at capacity` | 瞬态波峰，不是配额/通道故障，会话本身活着。**优先在原会话重试**（`orchestration_send_message` 让它继续，保留全部上下文），连续失败（2-3 次）才新建会话续做；仍满再换模型。区别于 gateway 503（账号池耗尽，换 runtime）与 workspace token budget（禁重试烧） |
| `sdk_session_id not found` / 审批中断 | 记稳定性卡；汇报。不要给原会话发消息 |
| `Agent not found: None` | 汇报；若重派，使用新的实现会话 |
| `zcode session/send: context canceled` 或 `Agent not found: None` | 通道故障 → 新开 Codex Luna，不给原会话发消息、不重试 ZCode |
| Codex resume `thread already has an active writer` | 新开 Codex 会话续做，不给原会话发消息 |
| 会话停在 AskUserQuestion/审批上，`orchestration_send_message` 显示已入站但 ~15 分钟无新回合 | 补发唤醒不可靠（2026-10-18：4 停 2 醒，CM-520/517 醒，CM-516/521 卡死）。等 15 分钟无启动就 `session_cancel` 后带预答重派新会话；停住时零产出，重派无损失。不要反复发消息 |
| 实现已接近完成但会话失败（额度、通道、被停），且 leftover worktree / 未提交 diff 还在 | 定位那棵树，新开会话续做。不要从零再开 worktree。被创始人停掉的重开会话直接放弃 |
| 默认档不合格或测试失败 | 汇报；升档先找原实现会话（「Residual 续做」）。找不到再**新开一档会话**，仍失败则停 |
| 升档后仍失败 | 不要再升；把 diff/失败点给创始人 |

## PR 关联

GitHub↔Linear 只认 PR **正文**里的 closing magic word。评论、标题、分支名都不够。

实现会话的 PR 正文必须先写完整说明（问题、根因、改动、验证）。创建时和做完时都要有这段描述，不要只留 closing word。

每张卡再写成**单独一行**，放在正文末尾：

```
Fixes CM-226
Fixes CM-229
```

**禁止**写在同一行：`Fixes CM-226, CM-229`（一个 Fixes 后面跟 ID 列表）和 `Fixes CM-226, Fixes CM-229`（同一行重复 Fixes）。创建 PR 时 Linear 通常只解析第一个 ID（或只吃分支里的第一个 `cm-N`）。官方语法是「一个 magic word 后面跟 ID 列表」，同一行第二个 `Fixes CM-232` 还可能被当成非法 ID。#566 正文已写 `Fixes CM-231, CM-232`，机器人只挂了 231，232 合入后仍是 Todo、没有 PR 附件。#568 的 203/215 同样漏挂。已验证能挂全组的是**换行、一行一个**（#576）。

也禁止 `CM-207–218` 这种区间，禁止只靠 `fix/cm-212-224-...` 分支名当全组已关联。

开出后核验 **Linear 卡片上的 GitHub PR 附件**，不是 GitHub 上 Linear 机器人的 linkback 评论（那种评论往往只出现第一张）。缺附件：再保存一次描述，把缺的 `Fixes CM-xxx` 补成单独一行。不要手改 Linear 状态。

## 合入

实现会话跑完、PR 已开之后，由**本会话**判断，不必再等创始人点头合入：

- **squash merge 并删除远程分支**（`gh pr merge --squash --delete-branch`），当同时满足：需求理解对、实现覆盖验收、CI 绿、可合并、范围没有漂到未点名的卡、没有新的协议/数据/权限风险、**已过「Code Review」二度门禁**（独立 review 会话无未处理 finding）。
- 合入前逐张看 Linear：**每张卡都有这个 PR 的附件**，正文末尾是一行一个 `Fixes CM-xxx`，且前面有完整说明。还在用逗号列表、正文只有 Fixes、或有卡没附件时，先 `gh pr edit` 补描述并改成逐行 `Fixes`，确认附件出现后再合。不要手改 Linear 状态。
- **不要合并**，改为把相关 Issue **指派给创始人**并立刻发邮件（说明风险、PR 链接、需要他做什么），当出现：CI 红、冲突、需求理解不稳、范围漂移、跨层协议/迁移不确定、已 Done/Released 卡上的孤儿 PR、或其它说不清的新风险。
- 跨层传输形状改动（backend / daemon / frontend 之间的响应协议）在合之前还要问一句：**没更新的老客户端拿到新形状会怎样**？如果会得到假成功、静默丢结果或永久卡死，先让创始人定上线顺序（一起发版并更新客户端，或加能力协商回退），再合。
- **消息/通知形状改动必须追到可见渲染处。** 改 message_type、新增 metadata 标记、改入队契约的 PR：合入前核实「每个写入的字段都有读取方」——从一条真实消息追到前端渲染分支，或确认有覆盖渲染的回归测试。只验后端送达、去重、字段存在不算验收。2026-10-24 CM-609 实例：CM-555（#869）把每子会话结果卡改成单条文字汇总，写了 `orchestration_plan_summary` 等标记但前端零消费者，通知裸文本气泡挂了 3 天才被发现。与 10-03 评分表写入无人读是同一失败模式的复发，故升级为门禁。

日常 squash 合入 ≠ 发版。发版必须创始人点头，每窗口最多一次。怎么发（命令、模型、是否非交互）由当场指令或触发它的 Task 决定，不在本 skill 展开。

## 发版后验收（两车道，2026-10-25 首轮跑通后固化）

发版完成后对**本批已合入的每张卡**做验收，分两条车道，不要混在一场会话里：

- **车道 1（免浏览器）**：一场会话批量核本批全部可非浏览器验证的卡。证据链 = 生产 merge commit 的祖先关系（`gh api .../compare/<mergeSha>...<bumpSha>` 要求 `behind_by=0` 且 `status` 为 `ahead` 或 `identical`，即 mergeSha 是发版 SHA 的祖先，证明改动确实在生产 bundle 里；`ahead_by>0` 属正常——发版 SHA 之后还有 bump 等后续提交，不要要求 ahead/behind 均 0，那只在两个 SHA 相同时成立）+ 每卡回归测试名与 CI run 链接。不下「看起来对」的结论，每条证据可复核。
- **车道 2（浏览器）**：**一场**会话（founder 定的合并原则：浏览器会话只开一条）在真实 UI 上按卡逐条走行为验收，手机视口 + 桌面各过一遍，关键状态截图存 `artifacts/images/`。需要登录态时走既有受控浏览器路径。
- 两条车道都过 → 向创始人出汇总验收报告（每卡结论 + 截图/证据引用）。车道 2 发现问题 → 按 Residual 建卡，不悄悄修。
- 首轮实例：v0.153.0（CM-613/614/615）4/4 过，2026-10-25。

## 盯会话

- 用 `session_id` 查状态，不要空转等待。
- 结论给「已 squash 合并 / 需创始人处理（已指派+已邮件） / 需返工 / 建议升档 / 建议另开 review」，对照验收。
- 不要手改 Linear 状态。PR 正文先写完整说明，末尾一行一个 `Fixes CM-xxx` 挂本组每张卡；合入前核对 Linear 附件。漏关联或缺描述时改 PR 正文，不要在 Linear 里补链接或改列。
- 编排入口坏了当 blocker，不要在本会话改仓库。
