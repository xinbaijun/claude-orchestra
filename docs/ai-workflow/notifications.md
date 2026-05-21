# Notifications — Worker 完工 push 给管家的事件流

> **用途**：弥补管家的「pull 渠道滞后」—— 管家原本靠用户口头报 + session_board.md 历史活跃区两条渠道知道 worker 完工，加这条 **append-only 文件事件流** 当第三渠道。配合 `.claude/settings.json` 的 Notification hook（BEL → tmux bell-action → 外层终端标签页红点），worker `/done` 时铃响 → 用户切到管家 → 管家读本文件最后 20 条 → 立刻知道刚谁完工 + 完工摘要。

---

## 规则

- **Append-only**：worker `/done` 最后一步 append 一行到「通知流」段顶部，**永远不修改过去条目**（修改 = 改写历史 = 管家上下文不可信）
- **最新在上**：跟 `resume_here.md` / `pending_questions.md` 一致。管家 Read 头 N 行就拿到最新 N 条，不需要 tail
- **管家读取**：`/butler` Step 1 必读，取「通知流」段**最上面 20 条**，Step 2 输出新段「📢 最近完工通知」展示
- **多 worker 并发安全**：用 Edit 工具单文件原子追加；多 worker 同时 `/done` 撞了 Edit 会触发 "File modified since read"，重读重写即可
- **不归档不删 → 5000 行触发归档**：归档到 `docs/_archive/notifications/<start>_to_<end>.md`

## 单条格式

```
- YYYY-MM-DD HH:MM | `<session-name>` | `<commit-hash>` | <一句话结果>
```

字段约束：

| 字段 | 取值 | 说明 |
|---|---|---|
| 时间戳 | 当前对话时间，`YYYY-MM-DD HH:MM` 24h | `/done` 执行 commit 那一刻；`date '+%Y-%m-%d %H:%M'` 取，禁止脑补 |
| session-name | `/rename` 名（小写英文 + 短横线 ASCII） | 跟 session_board.md 主键一致；没 rename 过填 `未命名` |
| commit-hash | 7 位短 hash，反引号包 | 多 commit 就填**主**那个；没 commit 的纯文档收工填 `(no-commit)` |
| 一句话结果 | ≤ 80 字 | 突出**这次完工带来的能力**，不是改了啥文件 |

**触发条件**：

- `/done` Step 7.6（仅完工分支，资源置 ⚪）
- `/catchup` Step 1.6（仅 commit 真有落地）

`/catchup` 跟 `/done` 等价但**触发条件不同**：/done 仅完工（⚪）才推；/catchup 只要有 commit 就推（中场进度也算 push 一次，让管家及时看到 worker 在动）。

---

## 通知流

<!-- 真实通知从下面这条横线下追加，最新在上 -->
