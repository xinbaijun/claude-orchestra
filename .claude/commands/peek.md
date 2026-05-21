---
description: 进入"巡视模式"——轻量看每个 worker 在干啥，不读 state 文件不做决策建议。
---

你现在进入「巡视模式」。**只看 worker 真实状态**，不做全局决策（那是 /butler 的活）。

---

## ⚠️ 边界（区分 /butler）

- ❌ **不读** session_board.md / notifications.md / resume_here.md / pending_*.md / claude_changes.md 等任何 state 文件
- ❌ **不提**下一步建议 / 风险冲突 / 待答问题
- ❌ **不做** tspawn / kill 任何 worker 干预动作
- ❌ **不做** 业务 tpush（用户决策 / 派活 / heads-up 等）
- ✅ **允许** Step 5 板漂自动派 chore-runner（修板态一致性）
- ✅ **允许** Step 6 butler_decisions batch commit 派 chore-runner（管家 batch Edit append 后顺手 commit dirty）
- ✅ **只跑** tmux ls + tmux capture-pane + jsonl-status 三类只读命令（主体）
- ✅ **只输出** 每 worker 1-3 行状态摘要 + Step 5/6 自动维护输出

频率建议：每 5-10 分钟想 quick check 时用；想全局决策用 /butler。

---

## Step 1 — tmux ls 拿 sessions

```bash
tmux ls
```

排除管家自己（如 `${BUTLER_SESSION}` session 不列）。

## Step 2 — 对每个非管家 session 拿信号

并行跑（每个 session 都做这两件事）：

**信号 A：capture-pane 末尾 30 行（必须 30 行，不能简化）**

```bash
tmux capture-pane -t <session> -p -S -30
```

⚠️ **不要为省 context 简化成 6 行**：完工证据字样（`Baked for` / `Cooked for` / `commit XXX 已落地` / `✅` / `🟢 待命` 等）通常**不在末 5-6 行**（末几行是 prompt input 框 + 状态栏），需要 20-30 行才看得到。

**信号 B：jsonl mtime 真活跃度（封装 jsonl-status 脚本）**

跑：

```bash
jsonl-status                    # 默认：全部非管家 tmux session
jsonl-status chore-runner       # 单 session 查
jsonl-status sess1 sess2 ...    # 多 session 查
```

输出表格 `<session>  <Xm 前活跃>`，列出所有指定 session 的 jsonl mtime。脚本内部封装 Path A + Path B 反查 + 兜底，不依赖 board uuid，每次 /peek 实时拿当前 sessionId。

⚠️ **不要读 `session_board.md` 备注里的 `jsonl=<前 8 位>`**！cc `/clear` / 长 session 滚动会换 uuid，board 里的字段会 drift。`jsonl-status` 内部实时反查规避此 drift。

⚠️ **/clear 后的已知盲点**：worker `/clear` 后 cc 起新 jsonl，sessions/<pid>.json 的 sessionId 字段**冻结**在 cc 启动时（不跟着 /clear 更新），Path A 拿到的会是 /clear 前的旧 jsonl mtime → 仍可能误判 🔴。**遇到这种 case 优先信 capture-pane 信号 A**（worker 真在干活 capture-pane 一目了然），jsonl mtime 仅作辅助。

## Step 3 — 末尾 pattern 识别（在 capture-pane 末尾 30 行 grep）

按下面规则给状态标签：

| 末尾出现 | 标签 |
|---|---|
| `Do you want to proceed?` / `❯ 1.` / `2. Yes` | 🔴 卡权限框待批 |
| `Error` / `Exception` / `Permission denied` / `Connection closed` | 🔴 报错 |
| `Worked for Xm Ys` 且 X > 15 | 🟡 长 thinking 可能卡 |
| `Worked for Xm Ys` 且 X < 5 | 🟢 正常工作 |
| 末尾纯 `❯ ` 无字 + 无 thinking 字样 + 30 行内有 `✅` / `落地` / `已完成` 类完工短语 | 🟡 完工待命 |
| 末尾 `❯ <字符>` 有字 + 无 thinking | 🟡 等用户输入 / cc auto-suggest |
| **capture-pane 末尾 30 行内有 `Baked for` / `Cooked for` / `Crunched for` / `完工` / `commit XXX 已落地` / `✅` / `落地` / `待命` 等完工证据** | 🟡 **完工待命**（覆盖 🔴 久未动判定）|
| jsonl mtime > 30 min 且**无完工证据** | 🔴 久未动（可能死了）覆盖任何 thinking 假象 |

**优先级**：jsonl mtime > 30 min + capture-pane 无 thinking spinner 时**强制覆盖**任何"看起来在干活"的标签 —— jsonl 是 cc 每次响应写盘的可信信号，30 min 不动 = 真挂了。**但若 capture-pane 显示 worker 实际活跃**（如刚回话 / spinner 转）→ /clear 盲点 → **以 capture-pane 为准**，不强制覆盖。

**完工待命兜底**：capture-pane 末尾 30 行内有完工证据字样 → **强制 🟡 完工待命**，**不进 🔴 久未动判定**。完工待命跟"挂了"语义不同：worker idle 等下一活是**正常状态**，不是异常。

### ⚠️ 输入框内容不可信（cc auto-suggest 已知盲点）

capture-pane 末尾的 `❯ <字符>` 输入框内容**不代表用户当前真输入** —— cc 会自动从历史输入 / 上下文塞 auto-suggest 建议文本到输入框（哪怕用户没敲键盘 / 没按回车）。

**判断 worker 状态优先看**（按可信度降序）：

1. **`* / · / ✻ <spinner> Xm Ys`** —— cc 当前在 thinking（最强信号）
2. **`Baked for / Cooked for / Crunched for Xm Ys`** —— 刚完工字样
3. **jsonl mtime**（实时反查，不依赖 board uuid）
4. **完工证据字样**（`✅` / `commit XXX 已落地` / `🟢 待命` 等）
5. **`Do you want to proceed?` / `❯ 1.` / `❯ 1. Yes`** —— 卡权限框（高优先级 🔴）

**不可信信号**：

- ❌ `❯ <一句话内容>` 输入框文本 —— **可能 cc auto-suggest 不是用户输入**
- ❌ 凭输入框内容推断"用户已经回话 X" / "worker 已经接力 Y"

派单 Step 6.7 同款原则：tpush 不查输入框内容；/peek 也不该信。

## Step 4 — 输出格式

按下面格式输出，**每 worker 1 行**（或可选第 2 行加备注）：

```
🔍 巡视报告（HH:MM）

- 🟢/🟡/🔴 `<session>` — <最近活动一句话推断> — jsonl <Xm 前活跃>
  - <可选：异常需立即关注的备注，正常状态省略此行>

总计 N session：🟢 X / 🟡 Y / 🔴 Z
```

**输出≤30 行**（每 worker 1-2 行 × 最多 10-15 个 worker），保持轻。

**hint**：如果输出含 N 个 🔴 久未动 worker（jsonl > 72h + 无 thinking + 非完工待命）→ 报告末尾加 1 行：

> 🟥 N 个 🔴 久未动 worker → 用 `/butler` 决策（CLAUDE.md「长 idle worker 处理（两步法）」段）

**不要在 /peek 输出里展开两步法细节**（违反 /peek SOP 顶部"不提建议"原则），只 1 行 hint 指引去 /butler 看细节。

## Step 5 — 一致性 diff（自动检测板漂）

Step 4 输出后**自动**跑一致性 check：

```bash
# Set A：tmux 当前活跃的 session 名（排除管家）
TMUX_SET=$(tmux ls 2>/dev/null | grep -v '^${BUTLER_SESSION}:' | cut -d: -f1 | sort)
# Set B：board.md 活跃段已注册的 session 名
BOARD_SET=$(awk '/^## 活跃对话$/,/^## 历史活跃$/' docs/ai-workflow/session_board.md \
  | grep -oP '`\K[a-z][a-z0-9-]+(?=`)' | sort -u)
```

**3 种异常 + 自动派 chore-runner**：

| 异常 | 现象 | 自动行为 |
|---|---|---|
| **A. tmux 有 + board 没有** | worker 没自注册 / Step 0.5 漏 | 写 `.prompts/check-<session>.md` 让 chore-runner tmux capture-pane 看 worker 在干啥 → 代登记 board 行 → tpush |
| **B. board 有 + tmux 没有** | worker 已 kill 但 board 仍 🟢 active | 写 `.prompts/cleanup-<session>.md` 让 chore-runner 搬该行到「历史活跃」段 → tpush |
| **C. board 时间戳 > 30 min 前** | worker 没更新（idle 太久 / 跨 repo） | 写 `.prompts/refresh-<session>.md` 让 chore-runner 看 jsonl mtime + 更新 board 时间戳 → tpush |

**节流（不要重复推）**：上一次 `/peek` 5 min 内已经推过同 session 的同类 check → 跳过。判断办法：grep `.prompts/check-<session>.md` / `cleanup-` / `refresh-` 文件 mtime，5 min 内存在则跳过。

**输出**（在 Step 4 主报告下方追加）：

```
🔄 板漂一致性 check：
- 异常 A（X 个）：[session list] → 已派 chore-runner 代登记
- 异常 B（Y 个）：[session list] → 已派 chore-runner 搬历史
- 异常 C（Z 个）：[session list] → 已派 chore-runner 刷时间戳
- 节流跳过：[session list]（5 min 内已推过）
```

无异常 → 输出"✅ 板态一致，无板漂"。

## Step 6 — butler_decisions batch commit 触发

跟 Step 5 同性质 —— 顺手检测 `docs/ai-workflow/butler_decisions.md` working tree 是否 dirty（管家 batch Edit append 决策后留着），dirty + 累积够 → 派 chore-runner 顺手 commit。

**检测**：

```bash
${GIT_WRAPPER} status --porcelain | grep -q "docs/ai-workflow/butler_decisions.md"
```

**触发判定**：

| 条件 | 判定 |
|---|---|
| butler_decisions dirty 且累积 ≥ 3 条新决策 | push（典型 case） |
| 距上次 batch commit > 2 h 且 dirty 有任意新决策 | push（频率兜底） |
| 不 dirty 或 < 1 条新决策 | skip |

「累积 N 条新决策」算法：`${GIT_WRAPPER} diff docs/ai-workflow/butler_decisions.md | grep -c '^+- 20'`（数 + 行带日期的）。

**派 chore-runner 姿势**：

```bash
# 写 .prompts/butler-commit-HHMM.md
cat > .prompts/butler-commit-HHMM.md <<EOF
chore-runner 顺手 commit butler_decisions.md（管家 batch Edit append 的 N 条决策）：
${GIT_WRAPPER} add docs/ai-workflow/butler_decisions.md && ${GIT_WRAPPER} commit -m "chore(butler): batch commit N 条决策（HH:MM-HH:MM）"
完事不用回报。
EOF

tpush chore-runner .prompts/butler-commit-HHMM.md
```

**输出**（在 Step 5 板漂 check 之后追加）：

```
📋 butler_decisions batch commit：
- 累积 N 条新决策 → 已派 chore-runner commit
```

或 skip 时：

```
📋 butler_decisions：0 条新决策 / 不 dirty → skip
```

## 触发场景

- 用户说"看看小弟" / "看看现在情况" / "现在有哪些对话" → 跑 /peek
- 管家自己每 10-15 分钟自动巡一次（可选，不是强制）
- 用户问某个 worker "XX 在干啥" → /peek 单 session 简化版（只对那个 session 跑 Step 2-4）

## 跟其它 slash 命令的关系

- /butler：全盘决策。/peek 是它的轻量补丁，**绝不替代**
- /catchup：worker 自用，跟 /peek 不相关
- /dispatch：用户决策"开新活"时调用，跟 /peek 不相关
