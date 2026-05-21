---
description: 跑 work_log 脚本从 git log 拿原料，加工成给老板看的工作日志（分时段 + 合并同主题 + 翻译技术黑话 + 列阻塞项）
---

你现在进入「日报模式」。这是**只读总结**角色 —— 从 git log 提取原料，加工成 human-readable 输出，**不写任何项目文件、不 commit**。

---

## ⚠️ 硬约束

- **禁止**任何 Edit / Write / NotebookEdit
- **禁止**任何 Bash 写操作（${GIT_WRAPPER} commit / push / add / 改文件的 sed / mv / rm 等）
- **可以**Read 任何文件、Grep / Glob、跑读类 Bash（`work_log` / `${GIT_WRAPPER} log` / `${GIT_WRAPPER} show` 之类）
- 如果用户在日报对话里说"那你顺手把 xxx 改了" → 拒绝，告诉他"日报只读，去工作对话或管家"

---

## Step 1 — 跑脚本拿原料

根据用户参数（默认今天）：

| 用户输入 | 脚本调用 |
|---|---|
| `/daily` 或 `/daily today` | `work_log` |
| `/daily yesterday` | `work_log yesterday` |
| `/daily week` | `work_log week` |
| `/daily 2026-05-14` | `work_log 2026-05-14` |
| `/daily 2026-05-10 2026-05-14` | `work_log 2026-05-10 2026-05-14` |

如果脚本末尾显示"共 0 个 commit" → 告诉用户"指定日期/范围内无 commit，无可整理"，结束。

## Step 1.5 — 拉管家决策摘要

跑 `head -80 docs/ai-workflow/butler_decisions.md` 拿目标日期范围内的管家决策清单，加工到日报「📜 管家决策」段（Step 2 输出新增第 5 段）：

- 按类型分组（🎩 派单 / 💀 kill / 🛠 改 SOP / 🚨 事故 / 📜 拍板 / 🔄 救活 / 💬 教学 / 🗒 调研派单 / 🔍 巡视）
- 同主题合并（如"今日派 3 个 worker：xxx / yyy / zzz"）
- 翻译技术黑话（"audit B1 post-commit hook" → "加自动同步状态板的钩子工具"）
- 让老板能看懂今天管家替你做了什么（决策维度，不重复 git log commit 维度）

如果 butler_decisions.md 为空 / 目标日期范围内无管家决策 → "📜 管家决策" 段省略。

## Step 2 — 加工成 5 段结构化输出

```
## YYYY-MM-DD 工作日志

### 上午（00:00 - 12:00）
- 同主题 commit 合并：「xxx 模块改造：a + b + c（commit hash1 / hash2）」
- 翻译技术黑话给非技术人看
- 一行 1-2 句话

### 下午（12:00 - 18:00）
- ...

### 晚上（18:00 - 24:00）
- ...

### 📜 管家决策（如有）
- 🎩 派单 N 个：worker A（任务）/ worker B / ...
- 💀 kill M 个：worker C 完工 / worker D 长 idle 两步法挂起
- 🛠 改 SOP X 处：xxx / yyy
- 🚨 事故处理 Y 次：xxx
- ...

### 阻塞 / 进行中
- 读 docs/ai-workflow/session_board.md：列 🟡 等用户 / ⚫ blocked / 🔴 待收工 状态的对话
- 读 docs/ai-workflow/resume_here.md：列未完成任务顶部那条
- 一行一个：[模块/对话名] 卡在啥

### 数据小结
- 共 N 个 commit / 涉及 X 文件 / 涵盖几个模块
```

**加工原则**：

- **合并要保守**：同 scope 同主题同时间窗才合；不同性质（feat + fix 同一模块）不要合
- **翻译要准**：技术词 → 业务词；不要瞎扩写（commit 没说的事不要编）
- **commit hash 保留**：每个合并条目后括号里列 hash，方便用户校验/翻原文
- **不写心得 / 反思 / 抱怨**：这是工作日志原料，不是日记
- **阻塞段要短**：每条一行（卡哪 + 等谁），不要展开成段

## Step 3 — 折叠原料（可选）

如果用户参数是 today / week（量较大），把脚本原始输出贴在最后做参考给用户校验：

```
<details>
<summary>📜 git log 原料（折叠）</summary>

[work_log 输出原文]

</details>
```

单日且 commit 少（< 5）就不折叠了。

## Step 4 — 提醒

末尾加一行：

> 💡 复制到你自己的工作日志即可。本对话只读不写。如需把整理后版本写进项目某个文档，告诉我（默认不写）。
