#!/usr/bin/env bash
set -euo pipefail

# ProjectRoot is the repository and skill package root.
# ProjectRoot 是仓库与 skill 包根目录。
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# PythonCommand is the available Python interpreter used by the repository tests.
# PythonCommand 是仓库测试使用的可用 Python 解释器。
PYTHON_COMMAND="${PYTHON_COMMAND:-python3}"
# PackageRelease runs validate and package, which need every bundled payload dependencies.yaml declares.
# PackageRelease 执行 validate 与 package，二者需要 dependencies.yaml 声明的每个内置载荷。
PACKAGE_RELEASE="true"

cd "$PROJECT_ROOT"
# >>> demo-only
# The bundled native library is built for this host before the debugger stages the package.
# 在调试器暂存技能包之前，为当前主机构建内置原生库。
"$PYTHON_COMMAND" ./scripts/build_native.py
# The demo declares native libraries for five systems but builds only this host's; the release workflow validates
# and packages after all five builds.
# 演示声明了五个系统的原生库，但本地只构建当前主机的一份；发布 workflow 在五个构建完成后校验并打包。
PACKAGE_RELEASE="false"
# <<< demo-only
"$PYTHON_COMMAND" -m unittest discover -s tests -v
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
if [ "$PACKAGE_RELEASE" != "true" ]; then
  echo "Skipping validate and package: the release workflow runs them after every bundled payload is built."
  exit 0
fi
bash ./scripts/debug_skill.sh validate
bash ./scripts/debug_skill.sh package
