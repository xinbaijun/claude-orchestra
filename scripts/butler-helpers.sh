#!/bin/bash
# butler-helpers.sh — 管家直调 4 个 bash function（5-28 落地）
#
# 替代「派 chore-runner 写 .prompts/*.md → tpush 触发 → chore-runner cc 解读 → Edit 落地 → commit」
# 这条 4-5 跳的链路里 4 类**纯机械**活，把它们压成管家 Bash tool 一行调用：
#
#   butler_commit                                    把 butler_decisions.md dirty 状态 commit 掉
#   board_register <session> <task> [jsonl-prefix]   activeboard 顶部追加新一行 + commit
#   board_refresh_timestamp <session>                刷该 session 的「最后活跃」时间戳 + commit
#   board_move_to_history <session> <summary>        从活跃段删 + 追加历史段顶部 + commit
#
# 智能活（capture-pane 解读 / 撞框路由 / SOP refactor / 元模式识别）**不**在范围内，
# 继续由 chore-runner / chore-monitor 当 cc 干。
#
# 每个函数都有：
#   - race 防护（grep board 看有无重复 / dirty 状态检查）
#   - 自带 commit（${GIT_WRAPPER} add-commit 单文件原子动词）
#   - 错误返回非 0，stderr 输出可读理由
#
# 设计约定：
#   - 时间戳一律 `date '+%Y-%m-%d %H:%M'` 取真时间，禁脑补
#   - board 写入用 awk + tmp + mv 原子，避免 race 半写入
#   - summary 含 backticks / 中文 / 引号 → awk -v 传字符串，不走 shell 二次解析
#
# 入口脚本（/usr/local/bin/butler_commit 等）通过 source 本文件 + 调函数实现。

BOARD=${PROJECT_ROOT}/docs/ai-workflow/session_board.md
BUTLER=docs/ai-workflow/butler_decisions.md

# ========== 1. butler_commit ==========
# 把 butler_decisions.md dirty 改动单文件 commit；clean 时跳过。
# 用法：butler_commit
butler_commit() {
  local now
  now=$(date '+%H:%M')
  if ! ${GIT_WRAPPER} status --porcelain "$BUTLER" 2>/dev/null | grep -qE '^.M|^M '; then
    echo "ℹ️  butler_decisions.md clean，跳过 commit"
    return 0
  fi
  ${GIT_WRAPPER} add-commit "$BUTLER" -m "chore(butler): batch commit 决策（$now）"
}

# ========== 2. board_register ==========
# 在活跃对话段顶部追加新一行 + commit。
# 用法：board_register <session> <task> [jsonl-prefix]
board_register() {
  local session="$1"
  local task="$2"
  local jsonl="${3:-待补}"
  if [ -z "$session" ] || [ -z "$task" ]; then
    echo "❌ 用法: board_register <session> <task> [jsonl-prefix]" >&2
    return 1
  fi
  local now hhmm row
  now=$(date '+%Y-%m-%d %H:%M')
  hhmm="${now##* }"
  row="| \`$session\` | $task | $now | 🟢 active | 管家派单 $hhmm；jsonl=$jsonl |"

  # race 防护：活跃段已有同 session → 跳过（worker 自注册过了 / 或老行没清）
  # 注：保留 grep -F session 名（而非 exact match），活跃段每次 register row 含 `now` 时间戳，
  # exact match 永远不重复 → race 防护失效。session 名匹配是正确语义。
  # 如果活跃段有"老行没清"（worker 没 /done + tmux 已 kill），调用方应先跑：
  #   board_move_to_history <session> "<old summary>"  把老行搬历史段
  # 然后再 board_register 注册新行。或者直接 board_refresh_timestamp 复用老行。
  local existing
  existing=$(awk '/^## 活跃对话/,/^## 历史活跃/' "$BOARD" 2>/dev/null | grep -m1 -F "\`$session\`" || true)
  if [ -n "$existing" ]; then
    echo "ℹ️  $session 已在活跃段，跳过 register（worker 自注册过了 / 或老行没清）"
    echo "   命中行：$existing"
    echo "   如果要复用老行 → board_refresh_timestamp $session"
    echo "   如果要替换老行 → 先 board_move_to_history $session \"<old summary>\" 再 board_register"
    return 0
  fi

  # 找「## 活跃对话」段下方表格表头分隔行（|---|...|）之后插入新行
  local tmp
  tmp=$(mktemp)
  awk -v row="$row" '
    /^## 活跃对话/ { in_active = 1 }
    /^## 历史活跃/ { in_active = 0 }
    { print }
    in_active && !inserted && /^\|---/ {
      print row
      inserted = 1
    }
  ' "$BOARD" > "$tmp" && mv "$tmp" "$BOARD"

  ${GIT_WRAPPER} add-commit "${BOARD#${PROJECT_ROOT}/}" -m "chore(board): $session 救活注册"
}

# ========== 3. board_refresh_timestamp ==========
# 把 session 那一行的第 3 列（最后活跃）刷成当前时间 + commit。
# 用法：board_refresh_timestamp <session>
board_refresh_timestamp() {
  local session="$1"
  if [ -z "$session" ]; then
    echo "❌ 用法: board_refresh_timestamp <session>" >&2
    return 1
  fi
  local now
  now=$(date '+%Y-%m-%d %H:%M')

  # race 防护：活跃段无此 session → 错误
  local existing
  existing=$(awk '/^## 活跃对话/,/^## 历史活跃/' "$BOARD" 2>/dev/null | grep -m1 -F "\`$session\`" || true)
  if [ -z "$existing" ]; then
    echo "❌ $session 不在活跃对话段，无法刷时间戳（先用 board_register 注册）" >&2
    return 1
  fi

  # awk 分割 "| " 找该 session 那行 + 替换第 3 字段（基于 1-index FS）
  local tmp
  tmp=$(mktemp)
  awk -v session="$session" -v now="$now" '
    BEGIN { FS = " \\| "; OFS = " | " }
    $0 ~ "^\\| `" session "` \\|" {
      # 字段：1=| `name`  2=task  3=time  4=status  5=remark|
      $3 = now
      print
      next
    }
    { print }
  ' "$BOARD" > "$tmp" && mv "$tmp" "$BOARD"

  ${GIT_WRAPPER} add-commit "${BOARD#${PROJECT_ROOT}/}" -m "chore(board): $session 时间戳刷新"
}

# ========== 4. board_move_to_history ==========
# 从活跃段删 <session> 那行 + 追加 summary 到「历史活跃」段顶部 + commit。
# 用法：board_move_to_history <session> <summary>
board_move_to_history() {
  local session="$1"
  local summary="$2"
  if [ -z "$session" ] || [ -z "$summary" ]; then
    echo "❌ 用法: board_move_to_history <session> <summary line>" >&2
    return 1
  fi

  # race 防护 v2（5-28 修）：用完整 summary line 做 exact match，避免跨日同 session 误判
  # 旧版 `grep -F "$session"` 只看 session 名，跨日多次完工撞历史段老条目就跳过 → 新条目永远插不进
  # 修：grep -F -x exact-line 匹配，只防御"同一行 summary 重复调用"的真正 race（worker 自搬 + 管家又调）
  local exact_match
  exact_match=$(awk '/^## 历史活跃/,0' "$BOARD" 2>/dev/null | grep -F -x -- "$summary" || true)
  if [ -n "$exact_match" ]; then
    echo "ℹ️  完全相同的 summary 行已在「历史活跃」段（重复调用），跳过"
    echo "   命中行：$exact_match"
    return 0
  fi

  # awk：删活跃段中 | `<session>` | 行 + 追加 summary 到 ## 历史活跃 下方紧贴
  # 注意：summary 含 backticks 等特殊字符，用 -v 传字符串而非 shell substitution
  local tmp
  tmp=$(mktemp)
  awk -v session="$session" -v summary="$summary" '
    /^## 历史活跃/ && !done_insert {
      print
      # 跳过紧跟着的 quote block (`> ...`) 和空行，找首个 `- ` 条目前插入
      header_done = 1
      done_insert = 1
      print_summary = 1
      next
    }
    header_done && print_summary && /^- / {
      print summary
      print_summary = 0
      print
      next
    }
    # 活跃段中含 | `<session>` | 的行：删除
    $0 ~ "^\\| `" session "` \\|" { next }
    { print }
    END {
      # 兜底：如果历史段全空（没 - 条目），summary 还没打印 → 末尾追加
      if (print_summary) {
        print summary
      }
    }
  ' "$BOARD" > "$tmp" && mv "$tmp" "$BOARD"

  ${GIT_WRAPPER} add-commit "${BOARD#${PROJECT_ROOT}/}" -m "docs(board): $session 搬历史活跃段"
}
