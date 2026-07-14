<#
.SYNOPSIS
Validate, load, enumerate, and package the current LuaSkill in one command.
用一个命令校验、加载、枚举并打包当前 LuaSkill。
#>

# ErrorActionPreference stops the one-click verification at the first failed stage.
# ErrorActionPreference 让一键验证在首个失败阶段立即停止。
$ErrorActionPreference = "Stop"

# ProjectRoot is the repository and skill package root.
# ProjectRoot 是仓库与 skill 包根目录。
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
# ValidateScript is the repository structure validator.
# ValidateScript 是仓库结构校验脚本。
$ValidateScript = Join-Path $PSScriptRoot "validate_skill.py"
# PackageScript is the deterministic release package builder.
# PackageScript 是确定性的发布包构建脚本。
$PackageScript = Join-Path $PSScriptRoot "package_skill.py"
# DebugScript is the repository wrapper around the official debug launcher.
# DebugScript 是官方调试启动器的仓库封装脚本。
$DebugScript = Join-Path $PSScriptRoot "debug_skill.ps1"
# StatusArgsFile contains the deterministic status-tool smoke payload.
# StatusArgsFile 包含确定性的状态工具冒烟参数。
$StatusArgsFile = Join-Path $ProjectRoot "examples\debug\demo-status.args.json"
# RgArgsFile contains the deterministic optional-tool dependency payload.
# RgArgsFile 包含确定性的可选工具依赖参数。
$RgArgsFile = Join-Path $ProjectRoot "examples\debug\rg-check.args.json"
# OverflowArgsFile contains the deterministic paging-tool smoke payload.
# OverflowArgsFile 包含确定性的分页工具冒烟参数。
$OverflowArgsFile = Join-Path $ProjectRoot "examples\debug\overflow-demo.args.json"
# NodeArgsFile contains the deterministic managed Node.js smoke payload.
# NodeArgsFile 包含确定性的受管 Node.js 冒烟参数。
$NodeArgsFile = Join-Path $ProjectRoot "examples\debug\node-runtime-demo.args.json"

Set-Location $ProjectRoot
& python -m unittest discover -s tests -v
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
& python $ValidateScript
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
& powershell -NoProfile -ExecutionPolicy Bypass -File $DebugScript -Command inspect -Output json
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
& powershell -NoProfile -ExecutionPolicy Bypass -File $DebugScript -Command list-tools -Output content
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
& powershell -NoProfile -ExecutionPolicy Bypass -File $DebugScript -Command call -Tool demo-status -ArgsFile $StatusArgsFile -Output json
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
& powershell -NoProfile -ExecutionPolicy Bypass -File $DebugScript -Command call -Tool rg-check -ArgsFile $RgArgsFile -Output json
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
& powershell -NoProfile -ExecutionPolicy Bypass -File $DebugScript -Command call -Tool overflow-demo -ArgsFile $OverflowArgsFile -Output json
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
& powershell -NoProfile -ExecutionPolicy Bypass -File $DebugScript -Command call -Tool node-runtime-demo -ArgsFile $NodeArgsFile -Output json
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
& python $PackageScript
exit $LASTEXITCODE
