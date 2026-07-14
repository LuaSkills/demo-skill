#!/usr/bin/env bash
set -euo pipefail

# ProjectRoot is the repository that owns the source skill files.
# ProjectRoot 是保存源 skill 文件的仓库。
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# DebugRoot is the ignored standalone debug workspace.
# DebugRoot 是被忽略的独立调试工作区。
DEBUG_ROOT="$PROJECT_ROOT/.luaskills-debug"
# LockFile serializes setup, staging, synchronization, and invocation.
# LockFile 串行化初始化、暂存、同步与调用。
LOCK_FILE="$PROJECT_ROOT/.luaskills-debug.lock"
# OwnerFile is fully written before its hard link competes for the visible lock path.
# OwnerFile 在其硬链接竞争可见锁路径前完成全部写入。
OWNER_FILE="$LOCK_FILE.$$"
# LockTimeoutSeconds bounds the wait for another debugger process.
# LockTimeoutSeconds 限制等待其他调试器进程的最长时间。
LOCK_TIMEOUT_SECONDS=120
# LockAcquired prevents interruption cleanup from deleting another process's lock.
# LockAcquired 防止中断清理误删其他进程的锁。
LOCK_ACQUIRED="false"

# Release the repository debugger lock owned by the current process.
# 释放当前进程持有的仓库调试器锁。
release_debug_lock() {
  if [ "$LOCK_FILE" != "$PROJECT_ROOT/.luaskills-debug.lock" ]; then
    echo "Refusing to remove an unexpected debugger lock path: $LOCK_FILE" >&2
    return 1
  fi
  if [ "$LOCK_ACQUIRED" = "true" ] && [ -f "$LOCK_FILE" ]; then
    # VisibleOwner is checked before deletion so only this process can release the lock.
    # VisibleOwner 在删除前接受检查，确保只有当前进程能释放该锁。
    local visible_owner
    visible_owner="$(tr -d '[:space:]' < "$LOCK_FILE")"
    if [ "$visible_owner" = "$$" ]; then
      rm -f -- "$LOCK_FILE"
    fi
  fi
  rm -f -- "$OWNER_FILE"
}

# Acquire the repository debugger lock and recover only locks owned by dead processes.
# 获取仓库调试器锁，并且只回收由已退出进程持有的锁。
acquire_debug_lock() {
  printf '%s\n' "$$" > "$OWNER_FILE"
  # StartedAt is the epoch timestamp used for bounded waiting.
  # StartedAt 是有界等待使用的纪元时间戳。
  local started_at
  started_at="$(date +%s)"
  while ! ln "$OWNER_FILE" "$LOCK_FILE" 2>/dev/null; do
    # OwnerPid is the recorded lock owner when acquisition completed.
    # OwnerPid 是完成锁获取时记录的持有进程。
    local owner_pid=""
    if [ -f "$LOCK_FILE" ]; then
      owner_pid="$(tr -d '[:space:]' < "$LOCK_FILE")"
    fi
    if [[ ! "$owner_pid" =~ ^[1-9][0-9]*$ ]] || ! kill -0 "$owner_pid" 2>/dev/null; then
      # StaleFile is an atomic quarantine target unique to this recovery process.
      # StaleFile 是当前回收进程唯一使用的原子隔离目标。
      local stale_file="$LOCK_FILE.stale.$$"
      if mv "$LOCK_FILE" "$stale_file" 2>/dev/null; then
        if [ "$stale_file" != "$PROJECT_ROOT/.luaskills-debug.lock.stale.$$" ]; then
          echo "Refusing to remove an unexpected stale debugger lock path: $stale_file" >&2
          return 1
        fi
        rm -f -- "$stale_file"
        if [[ "$owner_pid" =~ ^[1-9][0-9]*$ ]]; then
          # StaleOwnerFile is the dead process's private hard-link source.
          # StaleOwnerFile 是已退出进程的私有硬链接源文件。
          local stale_owner_file="$LOCK_FILE.$owner_pid"
          if [ "$stale_owner_file" != "$PROJECT_ROOT/.luaskills-debug.lock.$owner_pid" ]; then
            echo "Refusing to remove an unexpected stale owner path: $stale_owner_file" >&2
            return 1
          fi
          rm -f -- "$stale_owner_file"
        fi
      fi
      continue
    fi
    # CurrentTime is compared with StartedAt before the next retry.
    # CurrentTime 在下次重试前与 StartedAt 比较。
    local current_time
    current_time="$(date +%s)"
    if [ $((current_time - started_at)) -ge "$LOCK_TIMEOUT_SECONDS" ]; then
      echo "Timed out waiting for another LuaSkills debugger command in this repository." >&2
      return 1
    fi
    sleep 1
  done
  LOCK_ACQUIRED="true"
}

# ExitTrap always releases the lock; signal traps convert interruptions into stable exit codes.
# ExitTrap 始终释放锁；信号陷阱把中断转换为稳定退出码。
trap release_debug_lock EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
acquire_debug_lock

# LauncherPath is the official debug package shell launcher.
# LauncherPath 是官方调试包的 Shell 启动器。
LAUNCHER_PATH="$DEBUG_ROOT/debug.sh"
# Setup runs idempotently inside the repository lock before every debug command.
# Setup 在每个调试命令前于仓库锁内幂等执行。
bash "$PROJECT_ROOT/scripts/setup_debug.sh"

# PythonCommand is the interpreter used to build a clean debugger source stage.
# PythonCommand 是用于构建干净调试源暂存区的解释器。
PYTHON_COMMAND="${PYTHON_COMMAND:-python3}"
# StagedSkillPath contains only files included by the formal release-package whitelist.
# StagedSkillPath 仅包含正式发布包白名单收集的文件。
STAGED_SKILL_PATH="$("$PYTHON_COMMAND" "$PROJECT_ROOT/scripts/stage_debug_skill.py")"

# Command is the official debugger subcommand, defaulting to inspect.
# Command 是官方调试器子命令，默认使用 inspect。
COMMAND="${1:-inspect}"
if [ "$#" -gt 0 ]; then
  shift
fi

if [ "$COMMAND" = "sync" ]; then
  # BinaryPath is the official executable used because the Unix launcher omits sync forwarding.
  # BinaryPath 是官方可执行程序；Unix 启动器未转发 sync，因此此处直接调用。
  BINARY_PATH="$DEBUG_ROOT/bin/luaskills-debug"
  # RuntimeRoot is the same package-local runtime used by all official launcher commands.
  # RuntimeRoot 是所有官方启动命令共同使用的包内 runtime。
  RUNTIME_ROOT="$DEBUG_ROOT/runtime"
  "$BINARY_PATH" sync --runtime-root "$RUNTIME_ROOT" --skill-path "$STAGED_SKILL_PATH" "$@"
  exit $?
fi

"$LAUNCHER_PATH" "$COMMAND" --skill-path "$STAGED_SKILL_PATH" "$@"
exit $?
