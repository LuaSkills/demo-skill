#!/usr/bin/env bash
set -euo pipefail

# Turn the demo repository into a minimal LuaSkill template; pass --yes to apply and --force to skip the clean-tree check.
# 将演示仓库转换为最小 LuaSkill 模板；传入 --yes 才会执行，传入 --force 可跳过干净工作区检查。

# ProjectRoot is the repository and skill package root.
# ProjectRoot 是仓库与 skill 包根目录。
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# PythonCommand is the interpreter that runs the shared cleaner.
# PythonCommand 是运行共享清理脚本的解释器。
PYTHON_COMMAND="${PYTHON_COMMAND:-python3}"

"$PYTHON_COMMAND" "$PROJECT_ROOT/scripts/clean_to_template.py" "$@"
