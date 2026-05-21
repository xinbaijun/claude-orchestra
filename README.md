# Claude Workflow Template

> 多 worker 并行的 Claude Code 工作流系统模板。从一个 35 天 / 8000+ commit 的真实项目（小红猫 V3）抽出来，dogfood 迭代验证过的 SOP。

**6 个 slash 命令 + 9 个状态文件 + 6 个 tmux 工具**，clone + `bash init.sh` 一键 setup。

---

## 这是什么

让你**同时跑 3-5 个 Claude Code 对话**干不同的活，不漂、不丢、不会忘，并且能跨天回顾。

核心机制：

- **真相在文件里不在对话里**：所有未完成任务 / 待答问题 / 待测项 / 活跃对话 / 完工事件 / 管家决策都物化到 `docs/ai-workflow/` 9 个文件
- **管家 Claude vs 工作 Claude 角色分离**：一个对话只读总结全局决策派活，其它对话只干自己那摊活
- **append-only 事件流**：worker 完工 / 管家决策 / 通知都追加不修改，留 audit trail
- **板漂自动检测**：tmux 实际活跃 session 跟 board 注册的对账，不一致自动派 chore-runner 补登记
- **worker 自注册**：新对话起来后自己往 board 写一行，不靠管家预登记
- **dogfood 迭代**：工作流自己用自己，跑得不顺的地方现场抽 SOP 改进

---

## 谁需要这个

✅ **适合**：

- 项目长（几周以上），需要跨天接续
- 多 worker 并行（同时 2-5+ Claude 对话）
- 用 tmux 撑住 SSH 离线 / 重连
- 经常被 cc 崩 / tmux 崩 / 误触 Kill pane 困扰，想要救活机制
- 想给老板出工作日报

❌ **不适合**：

- 单对话单任务（杀鸡用牛刀）
- 不用 tmux（很多工具依赖 tmux session）
- 不在 Linux/Mac shell 环境（Windows 原生没适配过）

---

## 工作流哲学

### 1. 真相在文件里不在对话里

任何未登记的状态视为不存在。Claude 注意力会漂，对话会被压缩，唯一可信的状态是文件。所以遇到结束信号 / 切上下文 / 阻塞 / 完工，**必须物化到对应状态文件**才算"做了"。

### 2. Append-only 事件流

`notifications.md` / `butler_decisions.md` 永远不修改过去条目，只在顶部追加。修改 = 改写历史 = 上下文不可信。看头 N 行就拿到最新 N 条，不需要 tail。

### 3. 板漂自动检测

`session_board.md` 是 tmux 活跃 session 的镜像，但镜像会漂移：worker 没自注册 / worker 已 kill 但 board 还说 active / 长时间没更新。`/巡视` Step 5 跑 `tmux ls` vs `awk` board 一致性 diff，3 种异常自动派 chore-runner 修。

### 4. Worker 自注册

新派 worker 第一件事（Step 0.5）是 `/rename <name>` + 立刻 upsert board，不等 Phase 1 摸排。管家不再预登记（旧 SOP 漂移触发 scope creep）。

### 5. Dogfood 迭代

整套工作流模板自己用自己跑出来。SOP 不顺的地方现场抽出来改进，每次迭代有 dogfood 验证 case 编号（如 5-15 SSH key 覆盖事故 / 5-20 长 idle 两步法 / 5-21 tpush race fix）。

---

## Setup

### 前置

- Linux 或 macOS（Windows 用 WSL2）
- tmux ≥ 3.0
- bash ≥ 4
- Claude Code 已安装可用（命令 `claude` 或自定义 `cc` 之类）
- git

### 安装

```bash
git clone <repo-url> claude-workflow-template
cd claude-workflow-template
bash init.sh
```

`init.sh` 会交互问 5 个问题（默认值在括号里）：

| 问题 | 默认 | 说明 |
|---|---|---|
| `PROJECT_NAME` | `my-project` | kebab-case，会写进 CLAUDE.md 顶部 |
| `PROJECT_ROOT` | 当前目录 | 项目根绝对路径 |
| `BUTLER_SESSION` | `manager` | 管家 tmux session 名 |
| `CLI_CMD` | `claude` | Claude Code CLI 命令名 |
| `GIT_WRAPPER` | `git` | git 命令名，可填 wrapper（如 `xhmgit`） |

填完会自动 sed 替换模板里的 placeholder，跑 `bash scripts/install.sh` 装 launcher 到 `/usr/local/bin/`，生成最小 `.claude/settings.local.json`。

### 验证

```bash
# 起管家
tmux new -s manager -d
tmux send-keys -t manager "$CLI_CMD" Enter
tmux attach -t manager

# 在管家对话里
/butler              # 看全局状态
/dispatch <task>     # 派新 worker（管家专用）
```

---

## 6 个 slash 命令一览

| 命令 | 中文别名 | 触发场景 | 步骤数 | 谁能用 |
|---|---|---|---|---|
| `/butler` | `/管家` | 全局只读总结 + 决策建议 | 5 段输出 | 管家 |
| `/dispatch <task>` | `/派单 <任务>` | 派新 worker 起 session 干新活 | 6 步 | 管家 |
| `/peek` | `/巡视` | 轻量看每个 worker 在干啥 | 4 步 + 板漂 check + butler_decisions batch | 管家 |
| `/catchup` | `/盘点` | worker 中场补漏（commit + 待测 + 待答） | 3 步 | worker |
| `/done` | `/收工` | worker 完工收尾（含 push 通知管家） | 10 步 | worker |
| `/daily [today\|week\|<date>]` | `/日报` | 跑 git log → 加工工作日志 | 4 步 | 任何对话 |

ASCII 是主源，中文是指针别名（sshfs 环境下中文 slash 偶发失败兜底；同时国际化友好）。

---

## 9 个状态文件 schema 速查

| 文件 | 结构 | 何时写 | 何时清 | 归档 |
|---|---|---|---|---|
| `README.md` | 目录索引 | 一次性 | — | — |
| `workflow.md` | 工作流总览地图 | 工作流变更时 | — | — |
| `resume_here.md` | 未完成任务栈 | 中止信号 / `/done` | 任务做完即删 | 不归档 |
| `pending_questions.md` | 待用户拍板问题队列 | 对话里问的同时 append | 答完勾掉挪「解决记录」 | 不归档 |
| `pending_tests.md` | 待测试队列（真机/iOS/Android/长跑） | 改代码当场没法测 | 测过即删 | 不归档（git 见证） |
| `session_board.md` | 活跃对话表格 | 开头注册 + commit/盘点/收工 upsert | 完工搬「历史活跃」段 | 不归档 |
| `notifications.md` | append-only worker 完工事件流 | `/done` Step 7.6 / `/catchup` Step 1.6 | 不修改过去 | 超 5000 行切片 |
| `butler_decisions.md` | append-only 管家决策事件流 | 管家做决策当下自己 Edit append | 不修改过去 | 超 5000 行切片 |
| `known_pitfalls.md` | 域特定坑点库 | 撞到诡异问题事后写 | 修了 → 挪「已不再相关」段（不删） | 不归档 |

---

## 6 个 tmux 工具

`scripts/install.sh` 装 launcher 到 `/usr/local/bin/`，全 PATH 直调：

| 工具 | 干什么 | 用法 |
|---|---|---|
| `tspawn` | 一键 spawn cc worker（new-session + cc + 等就绪 + rename + 注入 prompt） | `tspawn <name> .prompts/<name>.md` |
| `tpush` | 给现存 worker push prompt（权限框防呆） | `tpush <name> .prompts/<task>.md` |
| `revive` | cc --resume 救活崩了的 worker（自动 jsonl UUID 反查 + 板自动搬） | `revive <name>` |
| `jsonl-status` | 反查 cc jsonl mtime 拿真活跃度 | `jsonl-status [name1 name2 ...]` |
| `myjsonl` | 当前 cc 进程的 jsonl UUID（自查） | `myjsonl` / `myjsonl \| cut -c1-8` |
| `work_log` | 从 git log dump 工作日志原料（笨脚本，加工交给 `/daily`） | `work_log [today\|yesterday\|week\|<date>\|<from> <to>]` |

---

## 卖点（来自真实项目踩坑）

### 1. butler_decisions audit trail

管家做的决策（派单 / kill / 拍板 / 改 SOP / 事故 / 救活 / 教学）当下立即 Edit append 到 `butler_decisions.md`，**默认 `⏳` 待验收**不自动转 ✅。用户口语"验收 14:50 那条" / "驳回最近 N 条"，管家 grep + Edit `⏳` → `✅` / `❌`。跨天回顾 + 日报对账 + 老板汇报用。

### 2. 长 idle worker 两步法

worker jsonl > 72h 不动 + 用户主动判"等触发条件" → 不简单 kill，走两步：① `tmux kill-session` 释放 session（jsonl 留着 `revive` 救活 hot context） ② 派 chore-runner append `resume_here.md` 一条**必含「触发条件」段**（满足任一即续）。心理负担小 / board 不 🔴 报警 / 动力来时不忘做啥。

### 3. Bundled-Workspace-Changes-From race trailer

多 worker 并行 commit 时，stage+commit 中间有 working tree 被其它 worker 改的"幽灵字节"。脚本层检测到 stage 之外仍有 modified 文件，**自动在 commit message 末尾注入** `Bundled-Workspace-Changes-From: working-tree-dirty (other modified: ...)` trailer，让 git log 显式记录"本 commit 可能偷带了别人改动"，归属错乱时 grep 找原作者。

### 4. cc auto-suggest 输入框不可信

capture-pane 末尾的 `❯ <字符>` 输入框可能是 cc 自动塞历史输入拼出的 auto-suggest，不是用户真输入。`/peek` Step 3 状态判断优先级：spinner > Baked/Cooked > jsonl mtime > 完工证据 > 权限框，**不信输入框文本**。管家报告口径"capture 显示 'XXX'（可能 auto-suggest 不一定真输入）"。

### 5. jsonl 实时反查（不读 board uuid drift）

`/peek` 信号 B 不读 board 备注里的 `jsonl=<前8位>`（cc `/clear` 会换 uuid，board 字段会漂移），改成**实时反查**：tmux pane_pid → cc_pid → `~/.claude/sessions/<pid>.json` sessionId → 拿 jsonl mtime。封装成 `jsonl-status` 脚本，零弹框。Path B 兜底 grep `Session renamed to: <name>` 反查最新 jsonl。

### 6. Step 0.5 worker 自注册

派单 prompt 模板**第一段 Step 0.5** 强制 worker `/rename` 完立即 upsert board（不等 Phase 1 摸排）。理由：旧 SOP "管家预登记" 5-15 触发 scope creep，废弃；改为 worker 自己注册 + chore-runner 兜底 check。管家硬约束不能 Edit board → 派 chore-runner 代登记一行。

### 7. xhmgit add-commit 原子动词（可选）

如果你的项目 git 操作多 worker 并行，用 `git_add_commit_atomic()` bash 函数（README 有示例 / 模板没强制集成）。`/tmp/<repo>.lock` mkdir 锁罩着 stage+commit；开始前检查 stage 区干净拒绝混入别人的 staged；commit message 走 stdin 绕开 shell 转义。模板默认不带这个 wrapper，README 说明用户自己接。

---

## 工作流生命周期

```
阶段 1 — 开新工作对话
路径 A（管家帮你开门）：/butler 看现状 → /dispatch <task>
路径 B（直接开）：tmux new -s <name> -d → cc → /rename <name> → 读 5 个状态文件

阶段 2 — 干活中
- 任何 Edit/Write → 必须执行 commit + upsert session_board
- 遇到问题 → 对话里问 + 同步登记 pending_questions.md
- 改代码没法测 → 登记 pending_tests.md
- 执行 commit 时顺手做会话名偏离检查

阶段 3 — 中场补漏（可选）/catchup
- Step 1   执行 commit
- Step 1.5 upsert session_board
- Step 1.6 append notifications（仅 commit 真落地）
- Step 2   列候选待测项
- Step 3   列候选待答问题

阶段 4 — 收工 /done
10 步走完含 push 完工通知给管家
```

---

## 自由定制

- **git wrapper**：默认直接用 `git`；如有 wrapper（如 `xhmgit` / `gh` / 自己写的）→ init.sh 填 `GIT_WRAPPER`，模板替换所有 `git status` 等命令
- **cli 命令**：默认 `claude`；项目自定义 alias（如 `cc`）→ init.sh 填 `CLI_CMD`
- **管家 session 名**：默认 `manager`；偏好 `butler` / `boss` / `xhm` 之类 → init.sh 填 `BUTLER_SESSION`
- **中英文 slash**：英文是主源；中文别名指针自动复制，sshfs 环境兜底用
- **更多状态文件**：照搬 `docs/ai-workflow/` schema pattern 加 `xxx.md`，建议 schema header + append-only 单文件
- **bell 通知**：`.claude/settings.json` 已配 Notification hook + tmux `bell-action any`，外层 Tabby / iTerm / Windows Terminal 标签页红点（README §卖点 后续补 Tabby 配置）

---

## Tabby / iTerm / Windows Terminal Bell 配置

### Tabby

Preferences → Terminal → **Terminal bell** 三选一：

| 选项 | 行为 |
|---|---|
| **Off** | 忽略 BEL |
| **Visual** | 后台 tab 闪 1 秒蓝点（容易错过）|
| **Audible** | 播 bell.ogg 声音（推荐多 worker 场景）|

可选加 manager tab 右键 → **Notify on activity**（系统通知）。

### iTerm2

Preferences → Profiles → Terminal → **Silence bell** 取消勾选 + **Show bell icon in tabs**

### Windows Terminal

settings.json 加 `"bellStyle": "window"` 或 `"taskbar"`

---

## 致谢

源于小红猫 V3（Flutter 项目，宠物 AI 守护平台）35 天 / 8000+ commit 实战 dogfood 迭代。SOP 改造每次都有 case 编号，模板里 case 编号已脱敏成"5-14 / 5-15 / 5-20" 等日期短码（年份省略，不影响阅读）。

---

## License

MIT
