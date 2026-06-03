---
description: spawn / 救活 / 重启 chore-monitor 服务员对话（长期共生 service worker，自动批安全权限框 + 收集事件 push 管家）
---

把 chore-monitor 服务员 worker 起起来。

---

## 子命令

```
/chore-monitor              # spawn 新的 chore-monitor session（已存在则提示 attach）
/chore-monitor revive       # cc --resume 救活崩了的 chore-monitor
/chore-monitor restart      # 重启（kill + spawn，丢 hot context；只有要换 prompt 时用）
```

---

## spawn 流程（默认）

```bash
# 1. 检测是否已存在
if tmux has-session -t chore-monitor 2>/dev/null; then
  echo "✅ chore-monitor session 已存在，attach 验证活着没"
  echo "   tmux attach -t chore-monitor"
  exit 0
fi

# 2. tspawn — 起 session + 起 ${CLI_CMD} + paste prompt + Enter
tspawn chore-monitor ${PROJECT_ROOT}/scripts/.prompts-templates/chore-monitor.md

# 3. 起 sentinel daemon（如果还没起）
sentinel start

# 4. 把 chore-monitor 自己也 register（特殊：chore-monitor 监督自己路由到 manager，避免自己挂了没人救）
sentinel register chore-monitor:0 manager 8 60

# 5. 自动 board_register
board_register chore-monitor "service worker — 安全权限框自动批 + 例外事件 push 管家" "$(myjsonl chore-monitor | cut -c1-8)"
```

---

## revive 流程

参数 `revive` → 调用 `revive chore-monitor`（脚本自动 cc --resume + sentinel register + board 搬板）

---

## restart 流程

参数 `restart` → 慎用，丢 hot context：

```bash
tmux kill-session -t chore-monitor 2>/dev/null
# 然后走默认 spawn 流程
```

---

## 配套：chore-runner（小弟）

chore-monitor 是**监督者**（自动批 + 报告管家）。如果还想要个**干活的小弟**做杂活，用同样模式起 chore-runner：

```bash
tspawn chore-runner ${PROJECT_ROOT}/scripts/.prompts-templates/chore-runner.md
sentinel register chore-runner:0 chore-monitor 8 60
board_register chore-runner "service worker — 接 tpush 干杂活" "$(myjsonl chore-runner | cut -c1-8)"
```

两个 service worker 并存：

- **chore-monitor** = 监督员 + 自动批（不改业务）
- **chore-runner** = 杂工（管家派活 → 落地，可改文档可 commit）
