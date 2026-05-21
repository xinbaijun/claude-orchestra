# Butler Decisions — 管家决策 audit trail

> **用途**：弥补变更日志 / notifications / session_board 缺失的"管家决策维度"。worker `/done` 写代码改动到变更日志，**管家自己**做的决策（派 worker / kill / 拍板方案 / 改 SOP / 处理事故 / 救活 / 教学 / 调研派单 等）在这里 append-only 记录，跨天回顾 + 工作日报 + 老板对账用。

---

## 规则

- **Append-only**：管家做决策当下立即 Edit append 一行；**永远不修改过去条目**
- **最新在上**：跟 `notifications.md` / `resume_here.md` 一致。读头 N 行拿最新 N 条，不需要 tail
- **管家自己 Edit append**：append-only 单文件无 scope creep 风险，管家白名单例外允许（详见 `.claude/commands/butler.md` 顶部硬约束段）
- **batch commit 由 chore-runner 触发**：管家 Edit 默认不 commit；累积 ≥ 3 条新决策（或距上次 commit > 2h） → `/peek` Step 6 自动派 chore-runner 顺手 commit；或用户口语显式触发
- **不归档不删 → 超 5000 行触发归档**到 `docs/_archive/butler_decisions/<start>_to_<end>.md`

## 单条格式

```
- YYYY-MM-DD HH:MM | <status> | <emoji 动作类型> | <一句话决策>
```

字段约束：

| 字段 | 取值 | 说明 |
|---|---|---|
| 时间戳 | 当前对话时间 `YYYY-MM-DD HH:MM` 24h | 管家做决策那一刻；`date '+%Y-%m-%d %H:%M'` 取，禁止脑补 |
| status | `⏳` 待验收 / `✅` 已验收 / `❌` 已驳回 | **默认 `⏳`**（不假装"默认通过"）；用户后续显式说"验收/驳回 X 那条" → 管家自己 Edit |
| emoji + 动作类型 | 见下表 | 一眼看清类型，方便 grep / 日报分组 |
| 一句话决策 | ≤ 80 字 | 突出**这次决策做了啥** + **为啥**（如适用） |

**动作类型表**：

| Emoji | 类型 | 含义 |
|---|---|---|
| 🎩 | 派单 | 派新 worker 起 session 干新活 |
| 🗒 | 调研派单 | 派 worker 调研出报告（无 commit 类） |
| 💀 | kill | kill worker（完工 ⚪ 自动 kill / 手动 kill） |
| 🔄 | 救活 | `revive` 把崩了的 worker 救回来 |
| 📜 | 拍板方案 | 用户给方案 menu 后管家替/帮用户拍板 |
| 🛠 | 改 SOP | 推动改 SOP 文档 / 工具链（派 chore-runner 落地） |
| 🚨 | 事故处理 | 紧急事件（SSH key 覆盖 / sshfs 卡 / tmux 崩等） |
| 💬 | 教学 | 教用户业界 pattern / 操作姿势对比 |
| 🔍 | 巡视 | /peek 跑出板漂或异常派 chore-runner 代登记 |

**举例**：

```
- 2026-05-20 14:50 | ⏳ | 🛠 改 SOP | 派 chore-runner 加 4 项 audit 改进（B1+A2+B2+A3）
- 2026-05-20 14:30 | ✅ | 🎩 派单 | health-sheet-fullscreen 上拉 sheet 全屏（用户 attach 看进展确认）
- 2026-05-20 13:14 | ⏳ | 💀 自动 kill | ui-polish-batch 完工 32 commit
- 2026-05-20 11:50 | ✅ | 🚨 事故处理 | SSH key 覆盖事故全链路修复
- 2026-05-20 01:35 | ⏳ | 🔄 救活 | new-mac-setup cc --resume 救活 hot context
```

**conversational handle**（用户口语 → 管家解析 → 自己 Edit）：

| 用户说 | 管家行为 |
|---|---|
| "验收 14:50 那条" / "验收最近 N 条" / "全验收" | 管家自己 `Edit` 指定行 `⏳` → `✅` |
| "驳回 14:50 那条" + 可选给修正理由 | 管家自己 `Edit` `⏳` → `❌`，可选 append 一条新决策"驳回 14:50 + 修正：xxx" |
| "看下管家决策待验收" / "列下待验收" | 管家 grep `⏳` 列出最近 5-10 条（read-only 不动文件） |
| "管家盘点" / "管家自评" | 同上 + 自评 "今天 X 条 ⏳ / Y 条 ✅ / Z 条 ❌" |

---

## 通知流

<!-- 真实管家决策从下面这条横线下追加，最新在上 -->
