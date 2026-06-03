#!/bin/bash
# sshfs_healthy.sh — 共享 sshfs 健康检测库（5-28 落地）
#
# 由其它脚本 source 后调函数，避免每个脚本手写一份（去重 sentinel-daemon line 44-50 +
# chore-monitor.md Step 0 等多处手写实现）。
#
# 用法（source 后）：
#   sshfs_healthy [path]           检测，返 0=健康 / 1=挂了；默认 ${PROJECT_ROOT}
#   sshfs_check_abort [path]       不健康 stderr 报错 + 返 1（脚本前置，配合调用方 exit）
#   sshfs_check_warn  [path]       不健康 stderr 警告 + 返 1，不 exit（chore-monitor 用）
#
# 核心检测：timeout 2 ls $path/. > /dev/null
# - timeout 2s 防 hang（sshfs stale 时 ls 会无限阻塞）
# - 用 ls 而不是 stat（stat 在 sshfs stale 时表现不一致）
# - $path/. 加点强制 dentry revalidate，命中真实 FUSE 调用（普通 ls $path 可能命中缓存）
# - mountpoint -q 先快速过一道（没 mount 直接返 1，省 2s timeout）

sshfs_healthy() {
  local path="${1:-${PROJECT_ROOT}}"
  mountpoint -q "$path" 2>/dev/null || return 1
  timeout 2 ls "${path}/." > /dev/null 2>&1
}

sshfs_check_abort() {
  local path="${1:-${PROJECT_ROOT}}"
  if ! sshfs_healthy "$path"; then
    echo "❌ sshfs ${path} unhealthy（timeout 2s 没回应）— 反向隧道可能挂了" >&2
    echo "   修：检查反向隧道，详见你的 server-ops/ 文档" >&2
    return 1
  fi
  return 0
}

sshfs_check_warn() {
  local path="${1:-${PROJECT_ROOT}}"
  if ! sshfs_healthy "$path"; then
    echo "⚠️  sshfs ${path} unhealthy（continuing without abort）" >&2
    return 1
  fi
  return 0
}
