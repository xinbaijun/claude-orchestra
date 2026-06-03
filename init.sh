#!/bin/bash
# init.sh — claude-workflow-template 一次性配置
#
# 交互式问 5-7 项 → sed 替换模板 placeholder → 装 launcher → 生成最小 settings.local.json
#
# 用法：
#   bash init.sh
#
# 可重入：替换后 placeholder 没了，重跑会无脑覆盖（如果你想换配置，重新填即可）。
# 不会动 .git。

set -euo pipefail

# ANSI
B='\033[1m' GREEN='\033[32m' YELLOW='\033[33m' BLUE='\033[34m' R='\033[0m'

echo -e "${B}${BLUE}=== Claude Workflow Template — init ===${R}"
echo ""

# 1. 交互式收集配置
ask() {
  local var="$1" prompt="$2" default="$3"
  read -p "$(echo -e "${B}$prompt${R} [${YELLOW}$default${R}]: ")" val
  echo "${val:-$default}"
}

PROJECT_NAME=$(ask PROJECT_NAME "项目名（kebab-case）" "my-project")
PROJECT_ROOT=$(ask PROJECT_ROOT "项目根绝对路径" "$(pwd)")
BUTLER_SESSION=$(ask BUTLER_SESSION "管家 tmux session 名" "manager")
CLI_CMD=$(ask CLI_CMD "Claude Code CLI 命令名" "claude")
GIT_WRAPPER=$(ask GIT_WRAPPER "git 命令名（可填 wrapper）" "git")

# JSONL_DIR 自动探测（Claude Code 约定：~/.claude/projects/-<dir-with-slashes-as-dashes>）
JSONL_DIR_GUESS="$HOME/.claude/projects/-$(echo "$PROJECT_ROOT" | sed 's|^/||; s|/|-|g')"
JSONL_DIR=$(ask JSONL_DIR "cc jsonl 目录（默认探测值）" "$JSONL_DIR_GUESS")

# xhmapi opt-in（仅做 REST API 项目时才用）
echo ""
read -p "$(echo -e "${B}是否启用 xhmapi REST API curl wrapper？${R} [${YELLOW}n${R}]: ")" enable_xhmapi
enable_xhmapi="${enable_xhmapi:-n}"
if [[ "$enable_xhmapi" =~ ^[Yy]$ ]]; then
  INSTALL_XHMAPI=1
  API_HOST=$(ask API_HOST "API host（如 https://api.example.com）" "https://api.example.com")
  TEST_ACCOUNT=$(ask TEST_ACCOUNT "默认测试账号短名（token 文件 scripts/.tokens/<acct>.txt）" "test_user")
else
  INSTALL_XHMAPI=0
  API_HOST="https://api.example.com"
  TEST_ACCOUNT="test_user"
fi

echo ""
echo -e "${B}${GREEN}配置确认：${R}"
cat <<EOF
  PROJECT_NAME     = $PROJECT_NAME
  PROJECT_ROOT     = $PROJECT_ROOT
  BUTLER_SESSION   = $BUTLER_SESSION
  CLI_CMD          = $CLI_CMD
  GIT_WRAPPER      = $GIT_WRAPPER
  JSONL_DIR        = $JSONL_DIR
  INSTALL_XHMAPI   = $INSTALL_XHMAPI
  API_HOST         = $API_HOST
  TEST_ACCOUNT     = $TEST_ACCOUNT
EOF
read -p "继续？[Y/n]: " confirm
[[ "${confirm:-Y}" =~ ^[Yy]$ ]] || { echo "已取消"; exit 0; }

# 2. sed 替换 placeholder（限定 *.md / scripts/*；不动 .git）
echo ""
echo -e "${B}${BLUE}[1/3] 替换模板 placeholder...${R}"

# 收集所有要处理的文件（避开 .git / node_modules / venv / 已生成 settings.local）
FILES=$(find . -type f \( \
    -name "*.md" -o \
    -name "*.md.template" -o \
    -name "*.sh" -o \
    -name "tspawn" -o \
    -name "tpush" -o \
    -name "revive" -o \
    -name "jsonl-status" -o \
    -name "myjsonl" -o \
    -name "work_log" -o \
    -name "butler_commit" -o \
    -name "board_register" -o \
    -name "board_refresh_timestamp" -o \
    -name "board_move_to_history" -o \
    -name "sshfs-check" -o \
    -name "xhmapi" -o \
    -name "xhmapi-token-load" -o \
    -name "settings.json" \
  \) \
  -not -path "./.git/*" \
  -not -path "./node_modules/*" \
  -not -name ".gitignore" \
  -not -name "init.sh" \
  -not -name "LICENSE")

# 关键 placeholder 全文替换
for f in $FILES; do
  sed -i \
    -e "s|\${PROJECT_NAME}|$PROJECT_NAME|g" \
    -e "s|\${PROJECT_ROOT}|$PROJECT_ROOT|g" \
    -e "s|\${BUTLER_SESSION}|$BUTLER_SESSION|g" \
    -e "s|\${CLI_CMD}|$CLI_CMD|g" \
    -e "s|\${GIT_WRAPPER}|$GIT_WRAPPER|g" \
    -e "s|\${JSONL_DIR}|$JSONL_DIR|g" \
    -e "s|\${API_HOST}|$API_HOST|g" \
    -e "s|\${TEST_ACCOUNT}|$TEST_ACCOUNT|g" \
    "$f"
done
echo "  ✅ 替换完成（处理 $(echo "$FILES" | wc -w) 个文件）"

# 3. 装 launcher
echo ""
echo -e "${B}${BLUE}[2/3] 装 launcher 到 /usr/local/bin/...${R}"
if [[ -w /usr/local/bin ]]; then
  INSTALL_XHMAPI=$INSTALL_XHMAPI bash "$PROJECT_ROOT/scripts/install.sh"
else
  echo -e "  ${YELLOW}⚠️  /usr/local/bin 不可写${R}"
  echo "     要么 sudo INSTALL_XHMAPI=$INSTALL_XHMAPI bash scripts/install.sh；要么自己 PATH 加 $PROJECT_ROOT/scripts/"
fi

# 4. 生成最小 settings.local.json
echo ""
echo -e "${B}${BLUE}[3/3] 生成 .claude/settings.local.json...${R}"
mkdir -p .claude
if [[ -f .claude/settings.local.json ]]; then
  echo -e "  ${YELLOW}✓ 已存在，跳过${R}（要重置删了再跑）"
else
  cat > .claude/settings.local.json <<EOF
{
  "permissions": {
    "allow": [
      "Bash(tmux ls)",
      "Bash(tmux list-panes:*)",
      "Bash(tmux list-windows:*)",
      "Bash(tmux list-sessions:*)",
      "Bash(tmux display-message:*)",
      "Bash(tmux has-session:*)",
      "Bash(tmux capture-pane:*)",
      "Bash(tmux new-session:*)",
      "Bash(tmux new-window:*)",
      "Bash(tmux send-keys:*)",
      "Bash(tmux rename-window:*)",
      "Bash(tmux load-buffer:*)",
      "Bash(tmux paste-buffer:*)",
      "Bash(tmux show-options:*)",
      "Bash(tspawn:*)",
      "Bash(tpush:*)",
      "Bash(myjsonl)",
      "Bash(myjsonl:*)",
      "Bash(revive:*)",
      "Bash(jsonl-status)",
      "Bash(jsonl-status:*)",
      "Bash(work_log:*)",
      "Bash(butler_commit)",
      "Bash(board_register:*)",
      "Bash(board_refresh_timestamp:*)",
      "Bash(board_move_to_history:*)",
      "Bash(sshfs-check)",
      "Bash(sshfs-check:*)",
      "Bash(date:*)",
      "Bash(wc -l:*)",
      "Edit(docs/ai-workflow/session_board.md)",
      "Edit(docs/ai-workflow/notifications.md)",
      "Edit(docs/ai-workflow/butler_decisions.md)",
      "Edit(docs/ai-workflow/resume_here.md)",
      "Edit(docs/ai-workflow/pending_tests.md)",
      "Edit(docs/ai-workflow/pending_questions.md)"
    ]
  }
}
EOF
  echo "  ✅ 已生成（含 generic allow rules；自己加业务命令）"
fi

# 5. 完工
echo ""
echo -e "${B}${GREEN}=== 完成 ===${R}"
cat <<EOF

下一步：

  1. 起管家 tmux session：
       tmux new -s $BUTLER_SESSION -d
       tmux send-keys -t $BUTLER_SESSION '$CLI_CMD' Enter
       tmux attach -t $BUTLER_SESSION

  2. 在管家对话里跑 /butler 看现状（首次 board / resume / notifications 都空）

  3. 派第一个 worker：/dispatch <任务描述>

  4. 验证工具链：
       which tspawn tpush revive jsonl-status myjsonl
       which butler_commit board_register board_refresh_timestamp board_move_to_history
       which sshfs-check
       jsonl-status          # 全部 session（除管家）
       myjsonl               # 当前 cc jsonl UUID
       sshfs-check           # 检 $PROJECT_ROOT 挂载健康（若在 sshfs 环境）
EOF
if [[ "$INSTALL_XHMAPI" = "1" ]]; then
cat <<EOF
       which xhmapi xhmapi-token-load
       xhmapi-token-load --list   # 当前已存 token

  5. xhmapi 用法（REST API curl wrapper）：
       xhmapi-token-load $TEST_ACCOUNT --paste  # 粘贴 token 入库
       xhmapi GET /some/path                    # 调接口
       详见 scripts/xhmapi 头注释
EOF
fi
cat <<EOF

  $([ "$INSTALL_XHMAPI" = "1" ] && echo "6." || echo "5.") 想了解每个 slash 命令的详细 SOP：
       cat .claude/commands/butler.md
       cat .claude/commands/dispatch.md
       ...

  README.md 详细介绍工作流哲学 + 卖点 + 自由定制。
EOF
