# Claude Workflow Template

> 多 worker 并行的 Claude Code 工作流系统模板。从一个 35 天 / 8000+ commit 的真实项目（小红猫 V3）抽出来，dogfood 迭代验证过的 SOP。

**6 个 slash 命令 + 9 个状态文件 + 10+ tmux/服务工具 + sentinel 监督 daemon**，clone + `bash init.sh` 一键 setup。

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

`init.sh` 会交互问 5-7 个问题（默认值在括号里）：

| 问题 | 默认 | 说明 |
|---|---|---|
| `PROJECT_NAME` | `my-project` | kebab-case，会写进 CLAUDE.md 顶部 |
| `PROJECT_ROOT` | 当前目录 | 项目根绝对路径 |
| `BUTLER_SESSION` | `manager` | 管家 tmux session 名 |
| `CLI_CMD` | `claude` | Claude Code CLI 命令名 |
| `GIT_WRAPPER` | `git` | git 命令名，可填 wrapper（如 `xhmgit`） |
| 装 xhmapi？(y/N) | `N` | 装 V3 REST API curl wrapper（opt-in；非 REST API 项目可永远不开）|
| `API_HOST` / `TEST_ACCOUNT` | — | 仅装 xhmapi 时问 |

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

## 10+ tmux/服务工具

`scripts/install.sh` 装 launcher 到 `/usr/local/bin/`，全 PATH 直调：

### 基础 worker / session 管理

| 工具 | 干什么 | 用法 |
|---|---|---|
| `tspawn` | 一键 spawn cc worker（new-session + cc + 等就绪 + rename + 注入 prompt） | `tspawn <name> .prompts/<name>.md` |
| `tpush` | 给现存 worker push prompt（Step 0 权限框防呆 fail-fast） | `tpush <name> .prompts/<task>.md` |
| `revive` | cc --resume 救活崩了的 worker（120s until-loop 等 cc UI + 自动 sentinel register + 板自注册） | `revive <name>` |
| `jsonl-status` | 反查 cc jsonl mtime 拿真活跃度 | `jsonl-status [name1 name2 ...]` |
| `myjsonl` | 当前 cc 进程的 jsonl UUID（自查） | `myjsonl` / `myjsonl \| cut -c1-8` |
| `work_log` | 从 git log dump 工作日志原料（笨脚本，加工交给 `/daily`） | `work_log [today\|yesterday\|week\|<date>\|<from> <to>]` |

### 管家 bash function 套件（替代 5-跳 chore-runner 链路）

| 函数 / 工具 | 干什么 |
|---|---|
| `butler_commit` | commit `butler_decisions.md`（自检 dirty / clean 跳过） |
| `board_register <name> "<task>" [jsonl-prefix]` | 活跃段顶部插一行（race check 跳过同 session 已注册） |
| `board_move_to_history <name> "<summary>"` | active 段删 + 历史段顶部插 + commit |
| `board_refresh_timestamp <name>` | 刷活跃段该 session 第 3 列「最后活跃」时间戳 + commit |

### 监督 / 自动批 / 服务 worker 重启

| 工具 | 干什么 | 用法 |
|---|---|---|
| `sentinel` | 统一监督 daemon CLI（取代散在多处的 watchdog-light 进程）；3 路由：chore-monitor / self-autobatch / manager | `sentinel start \| register <name> <route> 5 30 \| status` |
| `restart-chore` | service worker (chore-runner / chore-monitor) in-place 重启（kill + spawn 或 --reload 不 kill cc） | `restart-chore [name] [--reload]` |
| `sshfs-check` | sshfs fail-fast 健康检测（timeout 2s ls）防 cc Bash 进死挂载点卡 D state；**inline launcher**（sshfs 死时也能跑） | `sshfs-check [path]` |
| `xhmapi` *(opt-in)* | V3 REST API curl wrapper（默认 host / 默认账号 / 自动 Bearer / jq 彩色） | `xhmapi GET /v3/user/info` |
| `xhmapi-token-load` *(opt-in)* | dio Prettier log 抽 token（多行拼接）+ JWT 校验（alg + payload + exp）→ 存 scripts/.tokens/<account>.txt | `xhmapi-token-load guest_test_001` |

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

### 8. bash function 直调替代 5-跳 chore-runner 链路

管家做的简单 commit / board 增删（butler_commit / board_register / board_move_to_history / board_refresh_timestamp）原来要 → 写 prompt 文件 → tpush chore-runner → chore-runner 解析 → chore-runner Edit + commit → 回报。5 跳。现在 `scripts/butler-helpers.sh` 4 个 bash function 通过 launcher 暴露成命令，管家 Bash tool 直调一行搞定。chore-runner 解放出来真干小活。

### 9. sentinel 监督 daemon（统一 watchdog）

取代散在多处的 N 个 watchdog-light bash 进程。单 daemon + watchlist 注册表 + keeper wrapper（15s 自动 respawn）；3 路由：worker 撞权限框 → 自动 push 到 chore-monitor（safe 框）/ self-autobatch（read-only）/ manager（危险/不确定）。daemon 自身 fail-fast：sshfs 健康连挂 5 次或 flock 连挂 10 次 → exit 99 自杀（keeper 抓到判定为致命错误，停止 respawn，写状态文件给用户排查）。

### 10. chore-monitor 自动批安全权限框

`chore-monitor` 是长期共生 service worker：收到 sentinel 推的撞框通知 → tmux capture-pane 拿现场末 30 行 → 按「安全清单」判定（Read/Glob/Grep/git status/git log/echo 等 ✅ 自动批；rm -rf / git reset --hard / git push 等 ❌ push 管家；不确定 ⚠️ push 管家）→ ✅ 一行 `tmux send-keys -t <name>:0 Enter`。**永不 commit**（观察者职责），working tree dirty 是预期常态。

### 11. chore-runner 小弟服务 worker

长期共生 service worker，干所有「不值得开新 worker 的小活」：一次性 SOP 文档小改 / 单文件 audit / 修 typo / 紧急救火。**不走 /done SOP**（service worker 长期不收工）；接活流程 = 管家 tpush → 干 → append 一行到 `notifications.md` → 等下一个 tpush。可执行 `${GIT_WRAPPER}` commit（管家不能 commit，所以小修委托他）。

### 12. restart-chore in-place 重启

service worker hot context 太大 / 卡 cc parser quirk / prompt 模板改了想重 load 时，一行 `restart-chore` 替代手敲 11 步 tmux 序列。`--reload` 模式不 kill cc 安全（chore-runner 自己可 reload 自己）；spawn 模式自杀防御（chore-runner 跑 `restart-chore chore-runner` 会 exit 1 拒绝）。

### 13. inline_launcher（sshfs 死时也能跑）

普通 `install_launcher` 写 `exec bash $target`，依赖 sshfs 挂载活着。**救活类工具**（如 `sshfs-check` 本身）需要 sshfs 死时仍能跑 → `inline_launcher` 把 $target 全文 inline 进 launcher，对 `source ${PROJECT_ROOT}/scripts/<lib>.sh` 行 sed 替换为库内容。哲学："源代码仍在 repo，install.sh 当 build step 生成部署副本"。

### 14. xhmapi REST API curl wrapper（opt-in）

业务相关，**不强装**（init.sh 问 INSTALL_XHMAPI）。worker 一行 `xhmapi GET /v3/user/info` 测后端 REST API，自动加 Bearer token + Content-Type + jq 彩色。配套 `xhmapi-token-load` 从 dio Prettier log 抽 token（多行拼接）+ JWT 校验（alg / payload / exp）→ 存 `scripts/.tokens/<account>.txt`。多账号切：`-u <account>`。

---

## 番外：跨主机源切换（小红猫 V3 特化，未抽进模板）

源项目通过 sshfs 挂载 Windows / Mac 端的 git 工作树到 Linux 服务器（开发机分散），衍生出 `xhmount-win` / `xhmount-mac` 切源工具 + `xhmgit` git dispatcher（路由到 xhmgit-win 走 Windows 端 git / xhmgit-mac 走 Mac 端 git）。**模板未集成**：太特化（多数项目 git 在本地），但 pattern 可借鉴：

- **sshfs 挂主代码 + git 本机直跑**：sshfs 跑 git status 慢 100-200x，分离即可
- **dispatcher 模式**：`/tmp/<project>-current-source` state 文件 + wrapper 读 state 选 backend
- **占用检测拒切**：`lsof` 列 fd 占用，--force 强切

详见小红猫 V3 项目 `docs/server-ops/mac-win-parallel-dev-options-*.md` 设计文档。

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
