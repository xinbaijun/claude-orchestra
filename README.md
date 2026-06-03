# claude-orchestra

> 多 worker 并行的 Claude Code 工作流方法论 — 附一份参考实现。

从一个 35 天 / 8000+ commit 的真实项目（小红猫 V3，Flutter）dogfood 迭代出来。**这个 repo 主要传递的是"使用方法"**（7 个核心 Pattern），代码是参考实现，可整套 clone 也可只拿走 1-2 个 pattern 在你自己的 repo 手动复刻。

---

## What & Why

**痛点**：单对话 Claude Code 跑久了上下文会漂、被压缩；多对话并行起 3-5 个又容易忘了哪个在干啥 / 哪个该测 / 哪个等用户回话；跨天回来更是抓瞎。

**解决思路**：

- **真相在文件里不在对话里** — 任何未登记的状态视为不存在
- **管家 vs 工作 Claude 角色分离** — 一个对话只做全局总结 + 决策，其它对话只干自己那摊活
- **append-only 事件流** — worker 完工 / 管家决策 / 通知都追加不修改，留 audit trail
- **dogfood 迭代** — 工作流自己用自己跑出来，每次改 SOP 都有真实 case 背书

读完下面 7 个 Pattern，你可以：

- **轻量借鉴**：抄 1-2 个 pattern 到自己 repo 手动复刻（不装本 repo），最低门槛是改 5 个 markdown 文件 + 1 个 CLAUDE.md
- **全套复用**：clone + `bash init.sh` 装一套（详见底部「参考实现」段）

---

## 7 个核心 Pattern

### Pattern 1: butler / worker 角色分离

**做法**：起一个固定 tmux session 当**管家 Claude**，硬约束「**只读总结 + 决策派活 + append-only 写日志**，不动业务代码不 commit」；其它任务 session 是**工作 Claude**，专注自己那一摊。管家通过读状态文件 + tmux capture-pane 拿到全局视图。

**为什么有效**：单 Claude 同时做"全局调度 + 写代码"会漂；分离后管家上下文只装"决策与状态"，工作 Claude 上下文只装"当前任务"，各自远不到压缩阈值。

**自己怎么借鉴**（不装本 repo）：
- 在你的 `CLAUDE.md` 加一段"管家 vs 工作角色"说明 + 硬约束清单
- 起一个 tmux session 命名为 `manager` / `butler`，跑 Claude Code
- 在 `manager` 对话里开头说一句"你是管家，本会话只读总结不动代码"，让 Claude 自己守约束
- 别的活全开新 session

### Pattern 2: append-only 事件流

**做法**：两个永不修改过去条目的文件 —

- `notifications.md` — worker 完工/中场状态推送给管家
- `butler_decisions.md` — 管家做决策当下立即 Edit append 自己留痕（默认 `⏳` 待验收，用户口头说"验收 14:50 那条"管家自己改 `⏳` → `✅`）

新条目永远加在「通知流」段顶部，看头 N 行就拿到最新 N 条，不需要 tail。

**为什么有效**：改写历史 = 上下文不可信。append-only 让任何时刻的 git diff 都是"新增了什么"，跨天回顾 + 老板对账 + 日报对账都靠这两个文件。

**自己怎么借鉴**：
- 新建一个 `worker_log.md` 头部写「最新在上 / 永不修改过去」schema
- 让 worker 完工时 Edit 在顶部 append 一行（不用 tpush 不用 Bash）
- 想要管家决策审计加第二个 `butler_log.md`，同 schema

### Pattern 3: 板漂自动检测 + worker 自注册

**做法**：`session_board.md` 维护一张「当前活跃对话」表（session 名 / 当前任务 / 最后活跃 / 状态 / 备注）。两个机制保持新鲜：

- **worker 自注册**（Step 0.5）：新 worker `/rename` 完**立刻**自己 upsert 一行，不等管家预登记
- **板漂检测**（`/peek` 跑 `tmux ls` vs board 一致性 diff）：3 种异常（tmux 有 board 无 / board 有 tmux 无 / 时间戳过期）自动派 chore-runner 补登记

**为什么有效**：管家预登记会触发 scope creep（管家越界改业务文件），worker 自注册 + 兜底巡检最稳定。

**自己怎么借鉴**：
- 在你的 `docs/` 加 `session_board.md` 单表
- 在 `CLAUDE.md` 加一段"开新对话 Step 0.5 必须 upsert 一行"
- 每周手动跑 `tmux ls` 对账（不必上 daemon，少 session 量级人眼足够）

### Pattern 4: 真相在文件里不在对话里

**做法**：5 个状态文件覆盖所有"对话过程中产生但容易丢"的状态：

| 文件 | 装什么 | 何时写 | 何时清 |
|---|---|---|---|
| `resume_here.md` | 未完成任务栈 | 中止 / 收工 | 任务做完即删 |
| `pending_questions.md` | 待用户拍板的问题 | 对话里问的同时 append | 答完勾掉挪解决记录 |
| `pending_tests.md` | 改了代码当场没法测的真机/iOS/Android/长跑项 | 改代码当场 | 测过即删 |
| `session_board.md` | 当前活跃对话表 | 开头 + commit / 盘点 / 收工 upsert | 完工搬「历史活跃」 |
| `known_pitfalls.md` | 域特定坑点库 | 撞到诡异问题事后写 | 修了挪「已不再相关」段（不删） |

**为什么有效**：Claude 注意力会漂，对话会被压缩，唯一可信的状态是文件。所以遇到结束信号 / 切上下文 / 阻塞 / 完工，**必须物化到对应状态文件**才算"做了"。

**自己怎么借鉴**：
- 在你 repo 新建 `docs/ai-workflow/` 目录 + 5 个空文件 + 各自 schema header
- `CLAUDE.md` 顶部加一段"每次会话开头按顺序读这 5 个地方"
- 强制规则：任务中止前必须 append `resume_here.md`，不准只在对话里说"先这样"

### Pattern 5: service worker 长期不收工

**做法**：派 2 个**长期共生**的 service worker（跟普通 worker 一任务一 session 模型不同，service worker 长期挂着）：

- **chore-runner 小弟** — 干所有「不值得开新 worker 的小活」：一次性 SOP 文档小改 / 单文件 audit / 修 typo / 紧急救火。**不走 /收工 SOP**；接活 = 管家 tpush → 干 → append `notifications.md` → 等下一个 tpush
- **chore-monitor 监督员** — 收到 sentinel 通知撞框时按「安全清单」自动批 / push 管家

**为什么有效**：管家硬约束不能 commit / Edit 业务文件 / 派新 worker，但很多"明摆着的小活"开新 worker 太重；小弟兜住这层 → 管家保持纯粹决策角色不破戒。

**自己怎么借鉴**：
- 不上 sentinel 也行，只起一个 chore-runner 长期挂着
- 在 `scripts/.prompts-templates/chore-runner.md` 写它的硬约束（不走 /收工 / 接 tpush / 完工 append notifications）
- 管家想委托小活 → tpush 一个 prompt 文件给 chore-runner

### Pattern 6: 监督 daemon 自动批安全权限框

**做法**：单 daemon (`sentinel`) + watchlist 注册表 + keeper wrapper（15s 自动 respawn）；3 路由：worker 撞权限框 → 自动 push 到

- chore-monitor（safe 框，自动按 Yes）
- self-autobatch（read-only 自己处理）
- manager（危险/不确定，等用户）

daemon 自身 fail-fast：sshfs 健康连挂 5 次或 flock 连挂 10 次 → exit 99 自杀（keeper 抓到判定致命停 respawn 写状态文件）。

**为什么有效**：散在多处的 N 个 watchdog-light bash 进程难 debug 难重启，统一成单 daemon + 注册表后可观测可重启。`chore-monitor` 自动批掉 95% 的 Read/Glob/Grep/git status 安全框，用户只看真危险的。

**自己怎么借鉴**：
- 用户量少 / worker 少（≤3）可不上 daemon，手动批就够了
- 想要的话**只装一个 `chore-monitor`** 让它定时 `peek` 一圈，撞框场景用 `tmux capture-pane` 看末 30 行手判 — 不强制 daemon

### Pattern 7: in-place 重启 / cc --resume 救活

**做法**：两个工具兜底 cc 崩 / hot context 太大场景：

- `revive <name>` — 一行 cc --resume 救活：until-loop 120s 等 cc UI 真就绪 + 自动 sentinel register + 板自动搬
- `restart-chore [name] [--reload]` — service worker hot context 太大 / 卡 cc parser quirk / prompt 模板改了想重 load 时，一行替代手敲 11 步 tmux 序列。`--reload` 模式不 kill cc 安全

**为什么有效**：Claude Code 偶尔 parser stuck / 内存撑爆 / 用户误触 Kill pane，没救活机制只能从头开新对话丢 hot context。

**自己怎么借鉴**：
- 最低门槛：记住 `cc --resume <jsonl-uuid>` 这条命令 + `~/.claude/projects/-<repo>/` 路径，崩了手动 resume
- 进阶：`myjsonl <name>` 一行反查当前 session 的 jsonl UUID，写到 board 备注里崩了好查

---

## 速查表

### 6 个 slash 命令

| 命令 | 中文别名 | 触发场景 | 谁用 |
|---|---|---|---|
| `/butler` | `/管家` | 全局只读总结 + 决策建议 | 管家 |
| `/dispatch <task>` | `/派单` | 派新 worker 起 session 干新活 | 管家 |
| `/peek` | `/巡视` | 轻量看每个 worker 在干啥 + 板漂 check | 管家 |
| `/catchup` | `/盘点` | worker 中场补漏（commit + 待测 + 待答） | worker |
| `/done` | `/收工` | worker 完工收尾（含 push 通知管家） | worker |
| `/daily` | `/日报` | 跑 git log → 加工工作日志 | 任何对话 |

### 9 个状态文件

| 文件 | 类型 |
|---|---|
| `workflow.md` | 工作流总览地图 |
| `resume_here.md` | 未完成任务栈 |
| `pending_questions.md` | 待用户拍板问题 |
| `pending_tests.md` | 待测试队列 |
| `session_board.md` | 活跃对话表 |
| `notifications.md` | append-only worker 完工事件流 |
| `butler_decisions.md` | append-only 管家决策事件流 |
| `known_pitfalls.md` | 域特定坑点库 |
| `README.md` | 目录索引 |

### 10+ 工具

`scripts/install.sh` 装 launcher 到 `/usr/local/bin/`，全 PATH 直调：

**基础 worker / session 管理**：`tspawn` / `tpush` / `revive` / `jsonl-status` / `myjsonl` / `work_log`

**管家 bash function 套件**：`butler_commit` / `board_register` / `board_move_to_history` / `board_refresh_timestamp`

**监督 / 自动批 / 服务 worker 重启**：`sentinel` / `restart-chore` / `sshfs-check`

**REST API 测试**（opt-in）：`xhmapi` / `xhmapi-token-load`

详细用法见 `scripts/<name>` 头注释（每个工具自带 usage 段）。

---

## 想直接试

```bash
git clone git@github.com:xinbaijun/claude-orchestra.git
cd claude-orchestra
bash init.sh        # 交互填 5-7 个参数
bash scripts/install.sh
```

跑完起管家 `tmux new -s manager -d` → `claude` → 在管家对话里打 `/butler` 看全局。

完整 setup / 参数解释 / 自定义路径 / Bell 配置见下一段「参考实现详细文档」。

---

## 参考实现详细文档

### 前置

- Linux 或 macOS（Windows 用 WSL2）
- tmux ≥ 3.0
- bash ≥ 4
- Claude Code 已安装（命令 `claude` 或自定义 `cc`）
- git

### init.sh 5-7 个参数

| 问题 | 默认 | 说明 |
|---|---|---|
| `PROJECT_NAME` | `my-project` | kebab-case，写进 CLAUDE.md 顶部 |
| `PROJECT_ROOT` | 当前目录 | 项目根绝对路径 |
| `BUTLER_SESSION` | `manager` | 管家 tmux session 名 |
| `CLI_CMD` | `claude` | Claude Code CLI 命令名 |
| `GIT_WRAPPER` | `git` | git 命令名，可填 wrapper |
| 装 xhmapi？(y/N) | `N` | V3 REST API curl wrapper（opt-in） |
| `API_HOST` / `TEST_ACCOUNT` | — | 仅装 xhmapi 时问 |

填完会自动 sed 替换模板里的 placeholder，跑 `scripts/install.sh` 装 launcher 到 `/usr/local/bin/`，生成最小 `.claude/settings.local.json`。

### 工作流生命周期

```
阶段 1 — 开新工作对话
路径 A（管家帮你开门）：/butler 看现状 → /dispatch <task>
路径 B（直接开）：tmux new -s <name> -d → claude → /rename <name> → 读 5 个状态文件

阶段 2 — 干活中
- 任何 Edit/Write → 必须 commit + upsert session_board
- 遇到问题 → 对话里问 + 同步 append pending_questions.md
- 改代码没法测 → 登记 pending_tests.md
- commit 时顺手做会话名偏离检查

阶段 3 — 中场补漏（可选）/catchup
- 执行 commit + upsert board + append notifications + 列候选待测 / 待答

阶段 4 — 收工 /done
10 步走完含 push 完工通知给管家
```

### 自由定制

- **git wrapper**：默认 `git`，有 wrapper（`xhmgit` / `gh` / 自写）→ init.sh 填 `GIT_WRAPPER`
- **cli 命令**：默认 `claude`，自定义 alias（如 `cc`）→ init.sh 填 `CLI_CMD`
- **管家 session 名**：默认 `manager`，偏好 `butler` / `boss` → init.sh 填 `BUTLER_SESSION`
- **中英文 slash**：英文是主源，中文别名指针自动复制（sshfs 环境 / 中文输入兜底）
- **更多状态文件**：照搬 `docs/ai-workflow/` schema pattern 加 `xxx.md`，建议 schema header + append-only
- **bell 通知**：`.claude/settings.json` 已配 Notification hook + tmux `bell-action any`，外层终端标签页红点

### 其它实战 case（深度细节）

只看 Pattern 段够用了，下面是踩过的具体坑：

- **cc auto-suggest 输入框不可信** — capture-pane 末尾的 `❯ <字符>` 可能是 cc 自动塞历史输入拼出的 auto-suggest，不是用户真输入。`/peek` Step 3 状态判断优先级：spinner > Baked/Cooked > jsonl mtime > 完工证据 > 权限框，**不信输入框文本**
- **jsonl 实时反查（不读 board uuid drift）** — `/peek` 信号 B 不读 board 备注里的 `jsonl=<前8位>`（cc `/clear` 会换 uuid，board 字段会漂），改成实时反查：tmux pane_pid → cc_pid → `~/.claude/sessions/<pid>.json` → 拿 jsonl mtime
- **Bundled-Workspace-Changes-From race trailer** — 多 worker 并行 commit 时，stage+commit 中间 working tree 被其它 worker 改的"幽灵字节"。脚本层检测到 stage 之外仍有 modified 文件，自动在 commit message 末尾注入 `Bundled-Workspace-Changes-From: ...` trailer，让 git log 显式记录归属
- **长 idle worker 两步法** — worker jsonl > 72h 不动 + 用户主动判"等触发条件" → 不简单 kill，走两步：① `tmux kill-session` 释放 session（jsonl 留着 `revive` 救活 hot context） ② 派 chore-runner append `resume_here.md` 一条**必含「触发条件」段**
- **inline_launcher** — `sshfs-check` 这种救活类工具需要 sshfs 死时仍能跑 → install.sh 把 $target 全文 inline 进 launcher，sed 替换 `source` 行为库内容
- **xhmgit add-commit 原子动词**（可选） — 多 worker 并行 commit 用 `/tmp/<repo>.lock` mkdir 锁罩着 stage+commit + 开始前 stage 区干净检查 + commit message 走 stdin

### Tabby / iTerm / Windows Terminal Bell 配置

**Tabby**：Preferences → Terminal → **Terminal bell**，多 worker 场景推荐 **Audible**（播 bell.ogg 声音）；可选加 manager tab 右键 → **Notify on activity**（系统通知）

**iTerm2**：Preferences → Profiles → Terminal → **Silence bell** 取消勾选 + **Show bell icon in tabs**

**Windows Terminal**：settings.json 加 `"bellStyle": "window"` 或 `"taskbar"`

---

## 番外：跨主机源切换（小红猫 V3 特化，未抽进模板）

源项目通过 sshfs 挂载 Windows / Mac 端 git 工作树到 Linux 服务器，衍生出 `xhmount-win` / `xhmount-mac` 切源工具 + `xhmgit` git dispatcher。**模板未集成**（多数项目 git 在本地），但 pattern 可借鉴：

- **sshfs 挂主代码 + git 本机直跑** — sshfs 跑 git status 慢 100-200x，分离即可
- **dispatcher 模式** — `/tmp/<project>-current-source` state 文件 + wrapper 读 state 选 backend
- **占用检测拒切** — `lsof` 列 fd 占用，`--force` 强切

---

## 致谢

源于小红猫 V3（Flutter 项目，宠物 AI 守护平台）35 天 / 8000+ commit 实战 dogfood 迭代。SOP 改造每次都有 case 编号，模板里 case 编号已脱敏成"5-14 / 5-15 / 5-20" 等日期短码。

---

## License

MIT
