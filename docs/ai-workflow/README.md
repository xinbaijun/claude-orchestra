# AI Workflow — Claude 协作基础设施

> 这个目录放的是**纯 AI 协作流程文件**，不是项目交付物。
>
> 跟 `CHANGELOG.md` / `README.md` 那类「AI 写、人也看、可能要给别人看」的项目日志不同——这里的文件**主要给 Claude 读写**，是流程状态的物化。
>
> 真相在文件里，不在对话里。任何未登记的状态都视为不存在。

---

## 文件清单

| 文件 | 干什么用 | 谁写 | 何时写/读 |
|---|---|---|---|
| [`workflow.md`](workflow.md) | 整套工作流的总览地图（阶段 / 角色 / 触发方式 / 文档分工） | 用户 + Claude 共同维护 | `/butler` 启动时必读；用户随时翻阅 |
| [`resume_here.md`](resume_here.md) | 未完成任务索引，下次会话从最上面那条接手 | Claude | 用户发出**中止信号**时，或主动打 `/done` |
| [`pending_questions.md`](pending_questions.md) | 集中收所有"需要用户拍板"的问题 | Claude | 对话里问的同时**必须同步追加**到这里，不要只在对话里问完算 |
| [`pending_tests.md`](pending_tests.md) | 待测试队列（代码已改但当场没法测：真机 / iOS / Android / 长跑） | Claude | 改完代码当场没法测时立即追加；测过即删 |
| [`session_board.md`](session_board.md) | 当前活跃对话面板（一张表看清谁在干啥/卡哪/最后什么时候动） | Claude | 每次 commit 建议 / `/catchup` / `/done` 时 upsert 本会话那行；管家启动必读 |
| [`notifications.md`](notifications.md) | worker `/done` push 给管家的事件流（append-only） | worker | `/done` Step 7.6（仅完工分支）/ `/catchup` Step 1.6（仅 commit 落地） |
| [`butler_decisions.md`](butler_decisions.md) | 管家决策 audit trail（append-only） | 管家自己 | 管家做决策当下立即 Edit append |
| [`known_pitfalls.md`](known_pitfalls.md) | 域特定坑点库（splash / 原生 / SDK / 构建等） | Claude | 撞到诡异问题事后写 |

---

## 配套机制（在别处）

| 位置 | 作用 |
|---|---|
| `/CLAUDE.md` 顶部「⚠️ 最高优先级」段 | 列了所有结束信号短语，触发收尾流程 |
| `/.claude/commands/done.md` | `/done` 命令的 10 步 SOP |
| `/.claude/commands/butler.md` | `/butler` 命令的 5 段 SOP |
| `/.claude/commands/dispatch.md` | `/dispatch` 命令的 6 步派单 SOP |
| `/.claude/commands/peek.md` | `/peek` 命令的 4 步巡视 SOP |
| `/.claude/commands/catchup.md` | `/catchup` 命令的 3 步中场补漏 SOP |
| `/.claude/commands/daily.md` | `/daily` 命令的 4 步日报 SOP |

---

## 给未来 Claude / 接手者的备忘

- **看路径前先看这个 README**：这几个文件名简短，容易跟项目其它日志混
- **不要新增文件不沟通**：未来如果要加 `session_handoff.md` / `agent_chat_history/` 这类新基础设施，先跟用户讨论再加，避免重复发明
- **8 个文件 8 种生命周期**：
  - `workflow.md`：工作流变更时更新（地图，不是规则本体；规则在 CLAUDE.md）
  - `resume_here.md`：未完成任务**栈**，做完即删
  - `pending_questions.md`：问题**队列**，答完勾掉挪「解决记录」，定期清理
  - `pending_tests.md`：待测**队列**，测完即删，不归档（被测过的事实由 git/commit 见证）
  - `session_board.md`：活跃对话**面板**（实时灰盒），完工即从表里删，简短搬到「历史活跃」段
  - `notifications.md`：append-only worker 完工事件流，超 5000 行切片归档
  - `butler_decisions.md`：append-only 管家决策事件流，超 5000 行切片归档
  - `known_pitfalls.md`：坑点库，修了挪「已不再相关」段（不删，保留历史价值）
