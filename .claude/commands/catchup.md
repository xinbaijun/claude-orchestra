---
description: 中场补漏 —— 执行 commit / 登记待测项 / 登记待答问题三件最容易忘的事，比 /done 轻
---

你现在进入「盘点模式」。这是**中场补漏**，不是收工。比 `/done` 轻，只追 4 件最容易忘的：

- ✅ 执行 commit（动了代码就该 commit 但忘了）
- ✅ Upsert session_board.md（让管家随时看到 worker 真实状态）
- ✅ 待测项登记（改完代码当场没法测但漏登 `pending_tests.md`）
- ✅ 待答问题登记（对话里问过用户但漏登 `pending_questions.md`）

**不做**：resume_here.md 更新、变更日志写日志、主动问"还有没忘的吗" —— 这些是 `/done` 才做的事。

如果本次会话**什么代码都没改**（纯讨论 / 纯阅读 / 纯改流程文档），直接告诉用户「本会话无代码改动，无需盘点」即可，跳过下面流程。

> ⚠️ 流程文档（如 `docs/ai-workflow/`、`CLAUDE.md`、`.claude/commands/` 等）的改动也算代码改动，需要 commit。"纯改流程文档无需盘点"的判断条件是**完全没动文件**（只是问答 / 讨论）。

---

## Step 1 — 执行 commit

回顾本会话所有 Edit / Write / NotebookEdit 调用，**先输出计划**：

```
💾 计划 commit：
<type>: <简短描述>

待 stage 文件（白名单）：
- path/to/file1
- path/to/file2

（type: feat / fix / refactor / docs / chore / style / test）
```

**然后执行**：

1. `${GIT_WRAPPER} status` 确认现状
2. `${GIT_WRAPPER} add <白名单文件>` —— **永远不要 `-A` / `.`**
3. message 走 stdin：
   ```bash
   cat <<'EOF' | ${GIT_WRAPPER} commit -F -
   <type>: <简短描述>
   EOF
   ```
4. 输出 `✅ commit <hash> 已落地（N 文件 / +X / -Y），push 留给你跑`

**防呆**：

- **opt-out**：用户本会话说过"先别 commit / 我等会儿合并 commit / 我自己 commit"任一种 → 本步只给计划不执行
- **失败不重试**：commit 报错 → 停下来给用户看错误原样，**不要自动 amend / 不要换姿势重试**
- **多次归类**：一组同主题改动 → 一条合并 commit；几个完全无关的改动 → 分次 add + commit
- **增量场景**：已经在本会话之前 commit 过的，本次只 commit "上次 commit 之后又改了什么"

**会话名偏离检查（顺手做）**：

读 prompt 历史里最近一次 `Session renamed to: xxx` 拿当前会话名。若本次 commit 主题跟会话名明显偏离（不是范围扩大，是切到另一件事），在 commit 落地报告下追加：

> 💡 主题已偏离会话名 `<xxx>`，建议 `/rename <新名建议>`；如属另起任务，建议 `/done` 后新开。

宽松判断：宁可不提；任务范围自然扩大不算偏离。

## Step 1.5 — Upsert `docs/ai-workflow/session_board.md`（worker 状态显式同步）

**触发条件**：本会话有 `/rename` 过（prompt 历史能找到 `Session renamed to: xxx`）。没 rename 过 → 跳过这步并提醒用户起名。

从 prompt 历史拿本 session 名（主键），打开 `docs/ai-workflow/session_board.md`「活跃对话」表，**upsert** 本会话那行（4 列：当前任务 / 最后活跃 / 状态 / 备注）：

- **存在** → Edit 4 列
- **不存在** → 追加新行到表头下面（最新在上）

**字段填写**：

- **当前任务**：本会话目前在干啥，一句话
- **最后活跃**：跑 `date '+%Y-%m-%d %H:%M'` 拿真时间，**禁止脑补**
- **状态**：
  - 本会话刚改完代码还在干 → 🟢 active
  - 等用户确认 / 等 pending → 🟡 等用户
  - 改完代码但还没 /done，用户已走神 → 🔴 待收工
  - 卡外部依赖（后端 / 真机 / 设计稿）→ ⚫ blocked
- **备注**：极简，可空；末尾追加 `; jsonl=<前 8 位>` 方便 tmux 崩后救活

**执行 commit**（单独一条，跟 Step 1 主 commit 分开 —— 主题更清晰）：

```bash
${GIT_WRAPPER} add docs/ai-workflow/session_board.md
${GIT_WRAPPER} commit -m "chore(board): <session> 中场进度 upsert"
```

**理由**：

- 管家随时打开 board 能看到 worker 最新状态，不用每次 capture-pane
- 时间戳真实让 `/butler` / `/peek` 判断 worker 活跃度准确
- /catchup 是 worker 中场补漏，board 更新最该在这一步做

## Step 1.6 — Append `docs/ai-workflow/notifications.md`（worker → 管家 push 渠道）

**触发条件**：Step 1 真有 commit 落地（拿到了 hash）。Step 1 走的是 opt-out 不执行分支、或本会话无代码改动跳过 commit → 本步也跳过。

格式（顶部追加，最新在上）：

```
- YYYY-MM-DD HH:MM | `<session>` | `<commit-hash>` | <一句话结果>
```

字段：

- **时间戳**：**必须**跑 `date '+%Y-%m-%d %H:%M'` 拿真时间，**禁止脑补**
- **session**：本会话 `/rename` 名；没 rename 过填 `未命名`
- **commit-hash**：Step 1 主 commit 的 7 位短 hash（反引号包）；本会话之前 commit 过、本次 Step 1 又叠一刀就填**本次**那个 hash
- **一句话结果**：≤ 80 字，突出**这次盘点带来的进展**

**写入姿势**：用 `Edit` 工具在 `docs/ai-workflow/notifications.md` 的「通知流」段顶部插入这一行（紧贴 `<!-- 真实通知从下面这条横线下追加，最新在上 -->` 注释下方）。

**单独再做一次 add + commit**（**不要**合进 Step 1 的主 commit）：

```bash
${GIT_WRAPPER} add docs/ai-workflow/notifications.md
cat <<'EOF' | ${GIT_WRAPPER} commit -F -
chore(notify): <session> 中场进度
EOF
```

**为啥重要**：管家 `/butler` Step 1 必读 notifications.md 最后 20 条，Step 2 输出「📢 最近完工通知」段。/dispatch SOP 已改成走 `/catchup` 而非 `/done`（保留 hot context），如果本步不 append，管家就收不到 push 通知。

> 跟 `/done` Step 7.6 等价但**触发条件不同**：/done 仅完工（⚪）才推；/catchup 只要有 commit 就推（中场进度也算 push 一次，让管家及时看到 worker 在动）。

## Step 2 — 检查待测项

本次有没有"代码改了但当场没法在 Claude 这边测"的内容？判断标准：

- ✅ 需要登记：交互行为 / 接口联通 / 后端字段 / 推送 / 支付 / 平台分支（iOS vs Android）/ 设备能力（摄像头、相册）/ 真机性能
- ❌ 不用登记：纯静态样式（间距 / 颜色 / 字号 / 文案）—— 这种改完读代码就能验对错

**有需要登记的 → 不要自动写**，列给用户决定：

```
🧪 检测到本会话可能需要登记的待测项：

1. [模块] — [测试内容] (条件: 真机 / iOS / Android / 长跑)
2. ……

要登记到 docs/ai-workflow/pending_tests.md 吗？要的话我按模板写进去。
```

没有就明确说"无新增待测项"。

## Step 3 — 检查待答问题

回顾本会话有没有"需要用户拍板才能继续"的问题？混在对话里问过但漏登 `pending_questions.md` 的就要补登。

有 → 列给用户：

```
❓ 检测到本会话可能漏登的待答问题：

1. [模块] — [问题摘要]
   - 建议选项：A. … / B. …
2. ……

要登记到 docs/ai-workflow/pending_questions.md 吗？
```

没有就明确说"无新增待答问题"。

---

**重要：**

- 不要把 3 步并行汇总进一个长 message。**每一步明确说"Step X：…"并给结果**（即使是"跳过"或"无变更"），用户好核对
- 盘点完不要自动调 `/done`；让用户决定是否继续干活还是真收工
