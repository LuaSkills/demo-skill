#!/usr/bin/env bash
set -euo pipefail

# ProjectRoot is the repository and skill package root.
# ProjectRoot 是仓库与 skill 包根目录。
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# PythonCommand is the available Python interpreter used by validation and packaging.
# PythonCommand 是校验与打包使用的可用 Python 解释器。
PYTHON_COMMAND="${PYTHON_COMMAND:-python3}"

cd "$PROJECT_ROOT"
# >>> demo-only
# The bundled native library is built for this host before the debugger stages the package.
# 在调试器暂存技能包之前，为当前主机构建内置原生库。
"$PYTHON_COMMAND" ./scripts/build_native.py
# <<< demo-only
"$PYTHON_COMMAND" -m unittest discover -s tests -v
"$PYTHON_COMMAND" ./scripts/validate_skill.py
bash ./scripts/debug_skill.sh inspect --output json
bash ./scripts/debug_skill.sh list-tools --output content
bash ./scripts/debug_skill.sh call --tool hello --args-file ./examples/debug/hello.args.json --output json
# >>> demo-only
bash ./scripts/debug_skill.sh call --tool demo-status --args-file ./examples/debug/demo-status.args.json --output json
bash ./scripts/debug_skill.sh call --tool rg-check --args-file ./examples/debug/rg-check.args.json --output json
bash ./scripts/debug_skill.sh call --tool overflow-demo --args-file ./examples/debug/overflow-demo.args.json --output json
bash ./scripts/debug_skill.sh call --tool node-runtime-demo --args-file ./examples/debug/node-runtime-demo.args.json --output json
bash ./scripts/debug_skill.sh call --tool native-demo --args-file ./examples/debug/native-demo.args.json --output json
# <<< demo-only
"$PYTHON_COMMAND" ./scripts/package_skill.py
