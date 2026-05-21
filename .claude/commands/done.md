---
description: 强制走完本次会话的收尾流程，避免漏写日志/漏更新待办/忘 commit
---

你现在进入「收工模式」。**不要省略任何一步，长对话也必须按顺序走完**。

如果本次会话什么实质代码改动都没有（纯讨论 / 纯阅读），直接告诉用户「无需收尾」即可，不要走下面流程。

---

## Step 1 — 盘点本次改动

简短列一下本次会话改了哪些文件、做了哪些事（不需要长篇，3-8 条即可）。

## Step 2 — 更新变更日志（如有功能/Bug 修复）

> 这一步取决于项目是否有 `claude_changes.md` / `CHANGELOG.md` / 类似的累积日志。模板默认**不强制**写。如有就按项目约定 append 到顶部指针段下方（最新在上）。

如果只是讨论 / 调研 / 改文档，跳过这一步。

## Step 3 — 更新待测队列 `docs/ai-workflow/pending_tests.md`

本次有没有"代码改了但当场没真机/iOS/Android/长跑测过"的内容？有就 append 到 `docs/ai-workflow/pending_tests.md` 的「待测」段最上面，格式见该文件顶部模板。

也检查一下：本次有没有**完成**了之前登记的待测项？有就把对应条目从 pending_tests.md 删掉，不归档（测过的事实由 git/commit 见证）。

没有变更就明确说"无新增/完成的待测项"。

## Step 4 — 检查 `docs/ai-workflow/resume_here.md`

- 本次有没有**没干完**的任务？有就 append 到 `docs/ai-workflow/resume_here.md` 最上面（按该文件顶部模板）
- 本次有没有**完成**了 resume_here 里**之前登记的**任务？有就把对应条目从 resume_here.md 删掉
- 无变更就说"无未完成任务残留"

**会话名字段处理**（写新条目时）：

- 模板里有一行「Claude Code 会话名：」。如果你不知道本会话叫什么（用户没主动说过、也没 /rename 过），**主动提醒用户**：
  > 💡 建议给本会话起个名（`/rename <任务简称>`），写进 resume 后明天能在 Claude Code 会话列表里直接搜到。要起名告诉我，不起名我先填"未命名"。
- 用户给名字（或刚 /rename）→ 直接填进字段
- 用户不愿意起 → 填「未命名」，**不要追问**

## Step 5 — 检查 `docs/ai-workflow/pending_questions.md`

- 本次有没有新的"需要用户确认才能继续"的问题？有就 append
- 之前登记的问题有没有在本次得到答案？有就勾掉挪到「解决记录」段
- 无变更就说"无待确认问题变化"

## Step 6 — 业务侧附加（如适用）

> 项目特定。比如 API 对接进度表 / 用例校验 / 设计稿 review 等。模板默认跳过。

## Step 7 — 给用户工作日志 + 执行 commit

**先输出**工作日志 + commit 计划（必须有，即使前面几步都跳过）：

```
📋 工作日志（复制到你的文档）：
- ...
- ...

💾 计划 commit：
<type>: <简短描述>

待 stage 文件（白名单）：
- path/to/file1
- path/to/file2
```

**然后执行 commit**：

1. `${GIT_WRAPPER} status` 确认现状（看清楚现在哪些文件 modified / untracked）
2. `${GIT_WRAPPER} add <白名单文件>` —— **永远不要 `-A` / `.`**，避免误带上其它 worker / 调试脚本的产物
3. message 走 stdin 绕开 shell 转义：
   ```bash
   cat <<'EOF' | ${GIT_WRAPPER} commit -F -
   <type>: <简短描述>
   EOF
   ```
4. 输出结果：`✅ commit <hash> 已落地（N 文件 / +X / -Y），push 留给你跑`

**防呆（写死，不要绕）**：

- **opt-out**：用户本会话说过"先别 commit / 我等会儿合并 commit / 我自己 commit"任一种 → 本步只给"💾 建议 commit message"不执行
- **失败不重试**：commit 报错（pre-commit hook / 格式错 / nothing to commit 这类）→ 停下来把错误原样给用户，**不要自动 amend / 不要绕过 / 不要换姿势重试**
- **多主题分多 commit**：一组同主题改动 → 一条合并 commit；几个完全无关的改动 → 分次执行 add + commit

（type: feat / fix / refactor / docs / chore / style / test）

## Step 7.5 — 更新 `docs/ai-workflow/session_board.md`

从 prompt 历史里拿本 session 的 `Session renamed to: xxx` 名字，去 session_board.md 的「活跃对话」表 upsert 本会话那行。

- 如果本次任务**完工**（resume_here 没残留 + commit 已给）→ 把状态置 ⚪ 已完工，并把简短记录搬到「历史活跃」段，然后从「活跃对话」表删掉这行
- 如果本次**没干完**（resume_here 留了条目）→ 状态置 🟡 等用户 / ⚫ blocked / 🔴 待收工 中合适那个，更新最后活跃时间和备注
- 如果本会话从没 rename 过（拿不到主键）→ 跳过这步，但在 Step 8 提醒"建议起名 + 记 board"

## Step 7.6 — Append `docs/ai-workflow/notifications.md`（worker → 管家 push 渠道）

**触发条件**：本次任务**完工**（Step 7.5 把状态置成 ⚪ 已完工 那一支）。**没完工**就跳过这步，下次完工时再 append。

格式（顶部追加，最新在上）：

```
- YYYY-MM-DD HH:MM | `<session>` | `<commit-hash>` | <一句话结果>
```

字段：

- **时间戳**：**必须**跑 `date '+%Y-%m-%d %H:%M'` 拿真时间，**禁止脑补**；commit hash 时间用 `${GIT_WRAPPER} log --pretty='%h %ai' <hash>` 查
- **session**：本会话 `/rename` 名；没 rename 过填 `未命名`
- **commit-hash**：Step 7 主 commit 的 7 位短 hash（反引号包）；纯文档收工没 commit 填 `(no-commit)`
- **一句话结果**：≤ 80 字，突出**这次完工带来的能力**（不是改了啥文件）

**写入姿势**：用 `Edit` 工具在 `docs/ai-workflow/notifications.md` 的「通知流」段顶部插入这一行（紧贴 `<!-- 真实通知从下面这条横线下追加，最新在上 -->` 注释下方）。

**单独再做一次 add + commit**（**不要**合进 Step 7 的主 commit —— 主 commit 的 message 已经 finalize 了，重新 amend 风险大）：

```bash
${GIT_WRAPPER} add docs/ai-workflow/notifications.md
cat <<'EOF' | ${GIT_WRAPPER} commit -F -
chore(notify): <session> 完工
EOF
```

**并发安全**：notifications.md 多 worker 共写，靠 Edit 工具"File modified since read"兜底，撞了重读重写即可。

**为啥重要**：管家 `/butler` Step 1 必读 notifications.md 最后 20 条，Step 2 输出「📢 最近完工通知」段。这是 worker → 管家的 push 渠道。

## Step 8 — 主动问一句

最后必须问用户一句：

> 「还有什么没说的吗？比如：临时改了但没记的 mock 数据、改了但还没决定要不要保留的实验代码、聊到一半的设计想法 —— 这些容易忘的，要不要顺手记到 resume_here？」

让用户有机会补漏。

## Step 8.5 — push 完工通知给管家

走完前 8 步后，**主动 push 通知给管家 tmux session（`${BUTLER_SESSION}`）**让管家立刻知道你完工。

```bash
tmux send-keys -t ${BUTLER_SESSION} "📢 <worker-name> /done 完工：<一句话摘要>" Enter
```

摘要包含：
- 主要 commit hash 1-2 个
- 是否还在等用户（hot context 留不留）/ 是否已搬历史活跃段 / 是否可 kill
- 关键产出 / 后续 action

**为啥用 tmux push 而不是只靠 notifications.md**：
- 完工是里程碑事件，管家立刻知道才能决定下一步派活 / kill / 救活
- notifications.md 渠道仍然 append（Step 7.6 已做，双保险），但不是替代

**注意**：
- 仅 `/done` 完工时 push；**`/catchup` 不 push**（盘点频率高，会洪水打断管家）
- 如果**不在 tmux session 里**（独立 cc 进程，没父 tmux）→ skip 这一步，简短回报给当前对话即可

---

**重要：** 不要把这 10 步并行汇总进一个长 message。**每一步都要明确说"Step X：……"并给出结果**（即使是"跳过"或"无变更"），方便用户核对你真的走完了。
