# Claude 协作工作流总览

> 本文件是工作流的**地图**，不是规则本体。规则本体在 `CLAUDE.md`。
>
> **谁需要读：**
> - `/butler` 启动时必读（Step 1），确保管家清楚整个机制
> - 新加入项目的 Claude 对话可以读这里快速理解整体设计
> - 用户随时翻阅，快速回忆整个流程
>
> **更新原则：** 如果工作流真的变了，更新本文件 + 同步更新 `CLAUDE.md` 中的规则段。两者不一致时，**以 `CLAUDE.md` 为准**。

---

## 🎭 两种对话角色

```
默认（不打任何命令）  →  工作 Claude    实操：写代码 / 调试 / 接 API
打 /butler            →  管家 Claude    彻底只读：汇总状态 / 给建议 / 派活
                                       + 帮你开新工作对话（起 tmux session / 启 cc / rename）
                                       绝不动任何 git tracked 文件
                                       任何文件编辑都派 chore-runner 或专门 worker
                                       例外：.prompts/*.md 派单 prompt + plan mode 下的 plans/*.md
                                       例外：docs/ai-workflow/butler_decisions.md（管家自己 append 决策）
```

**不可就地切换。** 在管家里想干活 → 让管家先生成交接 prompt + 帮你开新工作对话。

---

## 🖥️ 终端架构：tmux + 一任务一 session

**为什么用 tmux**：服务器侧 session 持久化。本地 SSH 断 ≠ Claude 死；明天 `tmux attach -t <name>` 一切回来。

**一任务一 session**：每开一个新任务就 `tmux new -s <task-name> -d` 起一个 detached session。**不要**在已有 session 里 `tmux new-window`（同一 session 多 client attach 时窗口光标和输入会同步，多窗口工作时互相打扰）。

**从本地 attach**：`tmux ls` 看任务清单，`tmux attach -t <task-name>` 进想要的那个。多终端窗口可同时挂不同 session，互不干扰。

**关键约定：**

- **CC 命令是 `${CLI_CMD}`**（init.sh 配置）。所有自动化脚本和交接 prompt 里都用 `${CLI_CMD}`
- **tmux session 名 ≡ CC `/rename` 名**：ASCII 限定（小写英文 + 短横线 2-4 词，如 `login-thirdparty-bottom`）。tmux 对中文 session 名容忍度差
- **总览靠 session_board.md**：`tmux ls` 只看到 session 名，要看每个对话在干啥/卡哪去 `docs/ai-workflow/session_board.md`
- **关机不收摊**：晚上 `Ctrl+b d` detach 即可

---

## 🔔 等用户输入时的标签页红点提示（BEL 链路）

**痛点**：4-5 个工作对话同时跑，Claude 等权限弹框 / 等用户回复时**没外部提示**，用户切到别的 tab 干别的就漏了。

**链路**：

```
Claude 等输入（权限 / 闲置）
  └── Notification hook（.claude/settings.json）触发
        └── printf '\a' > /dev/tty （兜底 >&2）
              └── tmux 收到 bell（bell-action any）
                    └── 外层终端（Tabby / iTerm / WT）标签页红点 / 系统通知
```

**服务器侧已配好**（`scripts/install.sh` 跑过即生效，重装幂等恢复）：

- `.claude/settings.json` 配 Notification hook，matcher `permission_prompt|idle_prompt`
- `~/.tmux.conf` 加 `set -g bell-action any` + `set -g visual-bell off`

**外层终端配法**：

- **Tabby**：Preferences → Terminal → Terminal bell → 选 **Audible**（推荐多 worker 场景）或 **Visual**（容易错过 1 秒蓝点）
- **iTerm2**：Preferences → Profiles → Terminal → 取消 **Silence bell** + 勾 **Show bell icon in tabs**
- **Windows Terminal**：settings.json 加 `"bellStyle": "window"` 或 `"taskbar"`

---

## 🔄 工作流生命周期（4 阶段）

### 阶段 1 — 开新工作对话

**两种路径**：

**路径 A（推荐）：管家帮你开门**

```
用户   →  打 /butler 进管家对话
管家   →  Step 1-3 输出全局摘要，告诉用户应该接什么任务 / 阻塞在哪
用户   →  「就接 X 任务」或「开新任务 Y」
管家   →  /dispatch <任务>，由派单 SOP 接管：
          ① 摸排 → 反问 → 写 prompt → tspawn 起 worker
          ② worker 起来后自己 /rename + upsert session_board（Step 0.5）
用户   →  attach 过去看进度：tmux attach -t <name>
```

**路径 B：直接开新对话**

```
用户   →  tmux new -s <name> -d → ${CLI_CMD} → /rename <name>
工作 Claude →  读 4 个状态文件 + upsert session_board.md（开头注册）
用户   →  贴 prompt 或直接开始描述任务
```

**工作 Claude 开头读的 4 个文件**（按顺序）：

| 顺序 | 文件 | 干什么 |
|---|---|---|
| 1 | `CLAUDE.md` | 规则真相 |
| 2 | `docs/ai-workflow/pending_tests.md` | 该测但还没测的 |
| 3 | `docs/ai-workflow/resume_here.md` | 上次没干完的，最上面那条 |
| 4 | `docs/ai-workflow/pending_questions.md` | 还没答的问题 |

→ 简短告诉用户：上次做到哪、有没有待答、有没有该测的、想接哪个任务。

---

### 阶段 2 — 干活中

| 情境 | 工作 Claude 该做的 |
|---|---|
| 写代码前 | 看 common/ 组件复用 → 列计划等用户确认 |
| 遇到要用户拍板的问题 | 对话里问 **同时** 写到 `pending_questions.md` |
| 改了代码但当场没法测 | 写到 `docs/ai-workflow/pending_tests.md` |
| **每次改完代码（任何 Edit/Write 调用）** | **必须执行 commit** + 顺手 upsert `session_board.md` 自己那行 |
| 执行 commit 时 | 顺手做一次"会话名偏离检查" |

---

### 阶段 3 — 中场补漏（可选） `/catchup`

工作对话改完代码后**容易忘 commit / 待测 / 待答**，用户随时打 `/catchup`：

```
Step 1   执行 commit（动了代码就 commit 落地，不只给建议）
Step 1.5 upsert session_board.md 自己那行
Step 1.6 append notifications.md（commit 真有落地才推；让管家及时收到 worker 进展）
Step 2   列候选的待测项（让用户决定要不要登 pending_tests.md）
Step 3   列候选的待答问题（让用户决定要不要登 pending_questions.md）
```

不动 resume_here / 变更日志 —— 那些是 `/done` 才碰。

---

### 阶段 4 — 收工 `/done`

**触发方式（任一）：**

- 用户主动打 **`/done`**
- 用户说结束信号（CLAUDE.md 顶部「⚠️ 最高优先级」段列了所有触发短语）
- Claude 自己识别一个功能完工

**强制走 10 步**（详见 `.claude/commands/done.md`）：

```
1. 盘点本次改动
2. 写变更日志（功能/Bug，有改才写，如项目有此文件）
3. 更新 pending_tests.md（新增待测 / 删完成的）
4. 检查 resume_here.md（没干完进栈 / 干完出栈）
5. 检查 pending_questions.md（新问题入队 / 答完出队）
6. 业务侧附加（如适用）
7. 工作日志 + 执行 commit
7.5. upsert session_board.md：完工→搬历史活跃 / 没干完→留 board 上更新状态
7.6. append notifications.md（仅完工分支，push 完工事件给管家）
8. 主动问"还有没忘的吗"
8.5. tmux send-keys 给管家 push 完工通知
```

---

## 📂 文档地图

```
${PROJECT_ROOT}/
├── CLAUDE.md                              ⭐ 规则入口（工作流真相在这）
├── .claude/
│   ├── settings.json                      Notification hook + 通用 allow rules
│   ├── settings.local.json                项目个人配置（.gitignore，init.sh 生成）
│   └── commands/
│       ├── done.md / 收工.md              /done 命令的 10 步收尾 SOP
│       ├── butler.md / 管家.md            /butler 命令的 5 段摘要
│       ├── dispatch.md / 派单.md          /dispatch 命令的 6 步派单 SOP（仅管家）
│       ├── peek.md / 巡视.md              /peek 命令的 4 步巡视 SOP（仅管家）
│       ├── catchup.md / 盘点.md           /catchup 命令的 3 步中场补漏
│       └── daily.md / 日报.md             /daily 命令的 4 步日报
│
├── scripts/                               工具链源码（重装 → `bash scripts/install.sh` 一键恢复）
│   ├── install.sh                         往 /usr/local/bin/ 装薄壳 launcher
│   ├── tspawn                             一键 spawn worker
│   ├── tpush                              push prompt 到现存 worker（权限框防呆）
│   ├── revive                             cc --resume 救活 + 自动搬板
│   ├── jsonl-status                       反查 cc jsonl mtime 拿活跃度
│   ├── myjsonl                            当前 cc 进程 jsonl UUID
│   └── work_log                           git log dump 工作日志原料
│
└── docs/
    └── ai-workflow/                       AI 协作基础设施（流程状态物化）
        ├── README.md                      目录索引
        ├── workflow.md                    本文件（工作流总览）
        ├── resume_here.md                 未完成任务索引（栈，新在上）
        ├── pending_questions.md           待用户拍板的问题（队列）
        ├── pending_tests.md               待测试队列（真机/iOS/Android/长跑）
        ├── session_board.md               活跃对话面板（5-10 分钟粒度灰盒）
        ├── notifications.md               worker /done → 管家 push 渠道（append-only）
        ├── butler_decisions.md            管家决策 audit trail（append-only）
        └── known_pitfalls.md              域特定坑点库
```

**8 个状态文件的生命周期对比：**

| 文件 | 结构 | 何时写 | 何时清 | 归档 |
|---|---|---|---|---|
| `workflow.md` | 文档 | 工作流变更时 | — | — |
| `resume_here.md` | 栈 | 任务中止时 | 任务完成时 | 不归档 |
| `pending_questions.md` | 队列 | 对话里遇到时 | 答完勾掉，定期清 | 不归档 |
| `pending_tests.md` | 队列 | 改完代码当场没法测 | 测过即删 | 不归档（事实由 git 见证）|
| `session_board.md` | 表格 | 开头注册 + commit/catchup/done upsert | 完工搬历史活跃段 | 不归档 |
| `notifications.md` | append-only 事件流（栈，新在上） | /done Step 7.6（仅完工）/ /catchup Step 1.6（仅 commit 落地） | 不修改过去条目 | 超 5000 行归档 |
| `butler_decisions.md` | append-only 事件流（栈，新在上） | 管家决策当下自己 Edit append（白名单例外） | 不修改过去条目 | 超 5000 行归档 |
| `known_pitfalls.md` | 知识库 | 撞到坑事后写 | 修了挪「已不再相关」段（不删） | 不归档 |

---

## 📐 强制规则速查

CLAUDE.md 写死的 5 条强制行为，所有工作 Claude 都遵守：

| # | 规则 | 触发 | 后果 |
|---|---|---|---|
| 1 | **强制 /rename Step 0** | 新任务交接 prompt 必须把 `/rename <name>` 拎成独立 Step 0 | 不能塞标题行 |
| 2 | **强制执行 commit** | 任何一轮有 Edit/Write/NotebookEdit 调用 | 回复结尾必走"💾 计划 commit" + 调 `${GIT_WRAPPER} add` + `${GIT_WRAPPER} commit -F -` 真的落地（不只给文字建议）；除非用户明示稍后统一 commit |
| 3 | **会话名偏离检查** | 执行 commit 时 | 主题严重偏离 → 提议 rename 或 /done 新开 |
| 4 | **session_board.md upsert** | 开头注册 + 每次 commit/catchup/done | 不写就触发 board 落后 |
| 5 | **时间戳必须 date 取** | 任何带时间字段的写入前 | 跑 `date '+%Y-%m-%d %H:%M'`，禁止脑补 |

---

## ⌨️ Slash 命令速查

| 命令 | 中文别名 | 用途 | 步骤数 |
|---|---|---|---|
| `/done` | `/收工` | 收尾会话，写日志，执行 commit | 10 步 |
| `/butler` | `/管家` | 进只读模式，看全局，给建议 | 1+5+建议+5 步 |
| `/peek` | `/巡视` | **仅管家可用**。轻量看每个 worker 状态 | 4 步 + 板漂 check + butler_decisions batch commit |
| `/dispatch <任务>` | `/派单 <任务>` | **仅管家可用**。标准化派单 | 6 步 |
| `/catchup` | `/盘点` | 中场补漏，commit + 待测 + 待答 | 3 步 |
| `/daily` | `/日报` | 跑 work_log 脚本，加工成工作日志 | 4 步 |
| `/rename <name>` | — | CC 内置，改 session 名 | — |

---

## ⌨️ tmux 键位速查

| 键位 | 作用 |
|---|---|
| `tmux new -s <name>` | 起 session |
| `tmux attach -t <name>` | 接回 session |
| `tmux ls` | 列 session |
| `Ctrl+b d` | detach（保活退出）|
| `Ctrl+b &` | 杀当前 window（确认）|

---

## 🔗 会话名 ↔ 任务关联机制

为了关机重开后能找回当时的对话，**每条 resume_here 条目都带「Claude Code 会话名」字段**。

**操作约定：**

1. 开新任务 → 一开始就 `/rename <任务简称>`（小写英文 + 短横线 2-4 词）
2. Claude 写 resume / session_board 条目时把这个名字填进字段
3. 关机重开 → 看 session_board.md 知道每条任务在哪个 session 里 → `tmux attach -t <name>`

**两条恢复路径都通：**

- **要老对话上下文** → tmux attach 续上
- **不要老上下文（推荐，对话越长越漂）** → 新 session → `/butler` 帮你整理 resume 条目成 prompt → 复制喂新工作对话

**Claude 能读到自己的 session 名**：cc 把 `/rename` 结果作为消息注入对话上下文，工作 Claude 能实时看到当前会话名，所以"偏离检查" / "session_board upsert 主键" 都能工作。

---

## 🛡️ 权限闸门

`.claude/settings.json`（团队共享，进 git）+ `.claude/settings.local.json`（个人配置，不进 git）：

| 类别 | 行为 | 例 |
|---|---|---|
| **allow** | 不打扰 | `tmux ls` / `tmux capture-pane` / `tspawn` / `tpush` / `jsonl-status` / 只读类 |
| **ask** | 每次弹框确认 | `${GIT_WRAPPER} commit` / `${CLI_CMD}` 启动 / 写文件 |
| **deny** | 直接拒绝 | `rm -rf` / `${GIT_WRAPPER} push --force` / `${GIT_WRAPPER} reset --hard` |

---

## ⚠️ 几个易踩坑

| 坑 | 解 |
|---|---|
| 老对话不识别新触发短语 | 老对话加载的是老版 CLAUDE.md。手动打 `/done` 才行 |
| 旧对话不会 upsert session_board | 让它打一次 `/catchup`（或显式说「重读 CLAUDE.md」） |
| 管家对话想动任何文件 | 拒绝；派 chore-runner（小修）或新开 worker（大活）。管家彻底只读 |
| resume_here.md 全部条目灌进上下文 | 新对话先告诉 Claude 要做哪个，只取那一条作为工作上下文 |
| slash command 中文名失败 | sshfs 偶发；用 ASCII 别名 |
| workflow.md 和 CLAUDE.md 不一致 | 以 CLAUDE.md 为准；workflow.md 是地图，CLAUDE.md 是法典 |
| 多对话同时改同一个流程文件冲突 | 暂无文件锁，靠 Edit 工具"File modified since read"兜底重试 |

---

## 🚫 这套工作流不解决什么

避免错觉，列出来：

- **不解决：长对话注意力漂移**——只能靠 `/done` 和触发短语兜底
- **不解决：多对话真正并行修改同一文件**——靠管家定期检查，不靠系统层文件锁
- **不解决：工作 Claude 在管家模式偶尔主动想动手**——靠 `.claude/commands/butler.md` 顶部硬约束 + 用户警觉
- **不解决：用户彻底不写文档**——这套系统的真相在文档里，没文档就没真相
- **不解决：自动化开门礼时序故障**（cc 启动慢 / send-keys 错位）——tspawn 内置 poll 等就绪 + timeout；失败老实报，让用户切过去手动救场
