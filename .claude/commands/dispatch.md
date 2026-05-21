---
description: 标准化派单流程 —— 项目背景摸排 + 反问澄清（可智能跳过）+ 生成 prompt + tspawn 一键起 worker（new-session + cc + 等就绪 + rename + 注入 prompt；worker 自注册 session_board）
---

你现在进入「派单模式」。把"开新工作对话"系统化成一条命令。

---

## ⚠️ 硬约束（不可违反）

- **本命令仅在 /butler 对话里有效**。如果当前对话**不是**管家模式 → **拒绝执行**，告诉用户：
  > /dispatch 仅在管家对话里调用。请先 /butler 进入管家模式再 /dispatch <任务>。
- 派单本身**不写业务代码、不 commit、不 push、不编辑任何 git tracked 文件**（行为跟管家一致）
- **可以写**的：`.prompts/<name>.md`（项目根 `${PROJECT_ROOT}/.prompts/`，已 .gitignore 排除）
- **必须读**的：Step 2 列的项目状态文件
- **可以跑**的 Bash：`tmux *` 系列（派活载体）、`${GIT_WRAPPER} log/status/show` 这类只读
- **禁止跑**的 Bash：`${GIT_WRAPPER} add/commit/push/reset`、改文件的 `sed/mv/rm` 等

## 用法

- `/dispatch <任务描述>` —— 直接派单（推荐）
- `/dispatch` —— 没参数 → Step 1 反问

---

## Step 1 — 任务接收

用户参数即任务描述。

- 没参数 → 反问："你想派啥任务？一句话描述即可，背景我自己摸排"
- 有参数 → 直接进 Step 2

## Step 2 — 项目背景摸排（read-only）

**按需**读以下文件（不全读，根据任务关键词挑相关的）：

| 文件 | 何时读 |
|---|---|
| CLAUDE.md | 任务涉及全局规则 / Git / 接口 / 状态管理时读对应段 |
| `docs/ai-workflow/resume_here.md` | **必读** —— 看任务跟已有未完成任务是否重叠 |
| `docs/ai-workflow/pending_tests.md` | 任务涉及已改但未测的模块时读 |
| `docs/ai-workflow/pending_questions.md` | 任务可能涉及待答问题时读 |
| `docs/ai-workflow/session_board.md` | **必读** —— 看有没有并行对话动同一文件，避免 race / 冲突 |
| `docs/ai-workflow/known_pitfalls.md` | 管家 /butler 启动时已**全量读缓存**到 context；Step 4 时按当前任务关键词从 context 摘录 1-3 条注入 worker prompt 的「已知坑」段 |
| 项目代码（Grep / Glob） | 按任务关键词找相关文件 |

**重叠检测**：如果摸排发现任务跟 `resume_here.md` 已有条目重叠 → **建议用户接老任务**（找回老 session / 在老会话续）而不是新派。说明重叠位置 + 等用户决定（若用户坚持新派，继续 Step 3）。

**跨 repo 检测**：任务描述含 `跨项目` / `外部 repo` / 后端服务调研 等关键词 → 标记为**跨 repo 任务** → Step 4 prompt 生成时**注入「⚠️ 跨 repo 特别约束」段**（约束 worker milestone 时手动 upsert board，因为本 repo 无 commit 触发不了自动 hook）。

## Step 3 — 反问澄清（智能跳过）

**触发反问**（任一命中即问）：
- 任务描述太空（"优化 xxx UI" / "做下 yyy"）→ 问具体啥不喜欢 / 想要啥
- 摸排到现有相关代码但任务没说要不要复用
- 涉及边界条件（iOS only / Android only / 真机 / 离线 / 特殊账号）但任务没说
- 涉及新视觉但没说有 Figma 还是创作型任务
- 涉及多个 worker 并行的文件 → 列出并行对话 + 协调注意事项

**跳过反问**（同时满足）：
- 任务描述已经具体
- 摸排到的上下文足够
- 没有需要并行协调的隐患

跳过时**明示**给用户："摸排完上下文齐全，没反问，直接出 prompt 你看下"。

**反问最多 3 个问题**，列清楚 + 给候选答案（A/B/C 这种）方便用户秒回。

## Step 4 — 起 session 名 + 生成 prompt 文件

### Session 名规则

- ASCII（小写英文 + 短横线），**2-4 词**
- 跟任务核心对齐
- 中文 / 大写不行（tmux 命令行对非 ASCII 容忍度差）
- `tmux ls` 检查不重名，重名后缀 `-2`

### prompt 文件结构

写到 `.prompts/<session-name>.md`（项目根 `${PROJECT_ROOT}/.prompts/`），必须含：

```markdown
**Step 0（必须先做）：** /rename <session-name>

**Step 0.5（紧跟 Step 0，不等 Phase 1 摸排）：** 立即 upsert `docs/ai-workflow/session_board.md` 自己那一行
- 看到 `Session renamed to: <name>` 后**第一件事**做这个，让管家立刻知道 worker 起来了
- 跑 `date '+%Y-%m-%d %H:%M'` 拿真时间（**禁止脑补**）
- 新行格式：`| \`<session>\` | <派单时任务一句话> | <时间> | 🟢 active | 管家派单 HH:MM；jsonl=<前 8 位> |`（jsonl 前 8 位跑 `myjsonl | cut -c1-8` 拿）
- 用 `${GIT_WRAPPER} add docs/ai-workflow/session_board.md && ${GIT_WRAPPER} commit -m "chore(board): register <session>"` 单文件原子（避免 race）

---

任务：<一句话目标>

## 背景

<用户给的任务描述 + Step 2 摸排到的相关上下文 + Step 3 用户答复（如果有）>

## 步骤

<拆解到具体 phase / 子任务>
<视觉/设计型任务必须 Phase 1 scout → Phase 2 propose → Phase 3 用户确认 → Phase 4 implement，不要让 worker 跳步实现>

## 已知坑（管家提醒）

<根据任务关键词，管家从自己 hot context 里的 known_pitfalls.md 摘录 1-3 条相关坑。
如果没命中任何 pitfall（任务跟已知坑无关），整段跳过 — 不要写「无相关坑」浪费 token>

## 约束

- <必须保留的边界 / 不能做的事>
- <跟其它 worker 协调的注意事项>
- 任何 git 操作走 `${GIT_WRAPPER}`
- author 保持项目 git config 默认值

<如果任务是跨 repo 工作（管家在 Step 2 摸排时检测到）→ 在此处注入跨 repo 约束段：>

## ⚠️ 跨 repo 特别约束（仅跨 repo 任务时注入）

本任务主要在本 repo **之外**：

- **本 repo 不会有 commit** → 触发不了自动 hook 同步 board
- **必须手动 upsert** `docs/ai-workflow/session_board.md`「活跃对话」段：
  - milestone 时（关键决策 / 阶段完成 / 卡点）**必须 upsert**
  - 长 idle（>30 min 没动作）也 upsert 一次让管家知道还活着
  - 备注列写 `跨 repo 工作中，本 repo 无 commit`
- 用 `${GIT_WRAPPER} add docs/ai-workflow/session_board.md && ${GIT_WRAPPER} commit -m "chore(board): <session> milestone"` 单文件原子

否则管家 `/peek` 看 board 会判 🔴 久未动，可能误派 chore-runner 来 check。

## 涉及文件（预估）

- read: ...
- modify: ...
- new: ...

## 收尾

走 `/catchup` 3 步：commit + 待测登记（`pending_tests.md`）+ 待答登记（`pending_questions.md`）。

**不要自动走 /done**。/done 10 步含"任务完结"语义，会触发管家反射式 kill 丢失热 context。/done 由用户拍板触发。
```

**写完 prompt 文件后，给用户列一段简短摘要 4 行**（不要贴完整 prompt 100+ 行）：

```
📋 prompt 已写到 `.prompts/<session-name>.md`，摘要：
- **task**：一句话目标
- **session**：`<session-name>`
- **关键约束**：N 条
- **文件**：modify N / new M / read K
```

然后**直接走 Step 6 tspawn**，不等用户确认。

**用户看摘要发现错方向**可立刻 tpush 修正或 kill 重派；写错方向的成本 ≈ Phase 1 scout 时 worker 自然会停下来等用户回话，那时一样能纠偏。

**escape hatch**：用户显式说"这次贴完整 prompt 给我看一眼" / "等我确认再 spawn" / "先别 spawn" → 退回老流程贴完整 prompt 等确认。

## Step 5 —（已废弃 - 依赖 worker 自注册）

旧版「管家预登记 session_board.md」已废弃。管家 / 派单 **禁止编辑** session_board.md。

新流程**依赖 worker 启动后自注册**：worker 起来 → 读 CLAUDE.md「会话开头主动注册」段 → 看到 `Session renamed to: <name>` → 立刻 upsert 自己那行。空窗期约 30s，管家显式 `tmux ls` 验证 session 在跑就够了。

## Step 6 — 执行 tmux 自动化（`tspawn` 一行搞定）

> **注意**：spawn 后 session_board 暂时看不到新 session，这是预期 —— worker 启动后会自注册。tmux ls 验证 session 存在 + capture-pane 看 cc 起来了就行。

**主路径**：用 `tspawn` 一行调起，内部 poll capture-pane 看到 `❯` prompt 才继续：

```bash
tspawn <session-name> .prompts/<session-name>.md
```

效果 = new-session（cwd=`${PROJECT_ROOT}`）+ 启 `${CLI_CMD}` + 等就绪 + /rename + load-buffer + paste-buffer + Enter 一条龙。15s timeout fail-fast，session 留着方便手动救场。

执行完告知用户：

> ✅ session `<session-name>` 已就绪 + prompt 已贴 + 对话开始跑了
> attach 方式：`tmux attach -t <session-name>`

**如果 tspawn 失败**（cc 没起 / 超时 / session 重名）→ **不要瞎兜底**，老实告诉用户失败原因 + exit code 让他切过去手动救场。

**Fallback**（`tspawn` 不在 PATH —— 还没跑过 `bash scripts/install.sh`）：手动跑这 8 行 raw tmux：

```bash
tmux new -s <session-name> -d -c ${PROJECT_ROOT}    # 1. 起 detached session
tmux send-keys -t <session-name> "${CLI_CMD}" Enter   # 2. 启 cc
sleep 5                                                # 3. 等 cc 起（死等）
tmux send-keys -t <session-name> "/rename <session-name>" Enter   # 4. rename
sleep 1
tmux load-buffer .prompts/<session-name>.md           # 5. load prompt
tmux paste-buffer -t <session-name>                   # 6. paste
tmux send-keys -t <session-name> Enter                # 7. submit
```

跑通后回头 `bash ${PROJECT_ROOT}/scripts/install.sh` 装 launcher。

## Step 6.5 — 立即派 chore-runner 兜底 check（worker 自注册失败的 fallback）

spawn 完 + `tmux capture-pane` 验证 cc 起来 + rename OK 之后，**立即**派 chore-runner 一条 check 任务：

```bash
# 把 check 写到 .prompts/check-<session>.md
cat > .prompts/check-<session-name>.md <<EOF
check + 兜底 upsert: <session-name>

1. grep '<session-name>' docs/ai-workflow/session_board.md —— 看 worker 自注册了没
2. 没找到 → tmux capture-pane -t <session-name> -p | tail -10 验证 cc 还活着
   - 活着 → upsert 一行到 session_board.md
   - 不活 → 直接告诉管家"cc spawn 失败"，不要瞎兜底
3. 找到了 → ✅ 啥都不做
4. 走 ${GIT_WRAPPER} add docs/ai-workflow/session_board.md && ${GIT_WRAPPER} commit -m "chore(board): ..."
EOF

tpush chore-runner .prompts/check-<session-name>.md
```

**为啥这么做**：
- chore-runner queue 天然带延迟：当前活干完才 check，刚好给 worker 30-60s 自注册时间
- 管家立刻可用，不被 60s 等待 block
- 真发现 worker 自注册失败 → chore-runner 当场代登记
- 真发现 cc spawn 失败 → chore-runner 不瞎补，把信息抛回管家排查

## Step 6.7 — Push 模式简化原则（无顾虑直接发）

管家给现成 worker push 任务时**靠 tpush 内置 1 个判断**：tpush Step 0 看目标是不是在权限框（1/2/3 选项选择器）→ 是 → fail-fast exit 3 告诉你先 attach 批准 / 否 → 正常 paste + Enter。其它判断（thinking 态 / 输入框有字 / 用户 attach 撞）仍然零判断。

```bash
tpush <worker> .prompts/<task-name>.md          # 默认带 Step 0 防呆
tpush <worker> .prompts/<task-name>.md --force  # 紧急 case 跳过
```

**不需要做的判断**（tpush Step 0 仅查权限框，不查这些）：
- ❌ `tmux capture-pane` 看 worker 在不在 thinking（cc queue 信得过）
- ❌ 看输入框里是不是有字（cc auto-suggest 不是用户输入）
- ❌ 看 worker 是不是 idle / has queued messages
- ❌ 顾忌用户是不是 attached 在 worker tmux 里 type

**理由**：
- cc 内部 queue 机制可信 —— 任何时刻 push 都会被正确 FIFO 处理
- worker 输入框里的内容若是 cc auto-suggest 会被新粘贴自然替换 / append
- 用户 attach 时撞了，用户自己按 ESC 中断 / 编辑

**唯一保留护栏（管家这边）**：

管家自己**记账**对每个 worker push 了多少 task，等 worker 完工自报时显式核对数量。worker 偶尔会把多个 queued task "consolidate" 成"一波活的延伸"（认知偏差，不是 queue bug），管家事后发现 commit 数 ≠ push 数 → 补发漏掉的。

---

## 跟 /butler SOP 的关系

/dispatch 是 /butler Step 4 用户选了"开新任务"分支时的执行命令。/butler Step 4 不再自己处理派单细节，直接指向 /dispatch。

## 注意

- 启动 Claude Code 用 `${CLI_CMD}` 命令（init.sh 配置时填的）
- prompt 文件先 `Write` 到 `.prompts/<name>.md`，再 load-buffer + paste-buffer 注入（多行内容不能直接 send-keys，会丢换行）
- 派单完管家不主动介入子对话；子对话自己按 CLAUDE.md 规则 upsert `session_board.md`
