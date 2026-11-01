<#
.SYNOPSIS
Load, call, validate, and package the current LuaSkill in one command.
用一个命令加载、调用、校验并打包当前 LuaSkill。
#>

# ErrorActionPreference stops the one-click verification at the first failed stage.
# ErrorActionPreference 让一键验证在首个失败阶段立即停止。
$ErrorActionPreference = "Stop"

# ProjectRoot is the repository and skill package root.
# ProjectRoot 是仓库与 skill 包根目录。
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
# DebugScript is the repository wrapper around luaskills-debug.
# DebugScript 是 luaskills-debug 的仓库封装脚本。
$DebugScript = Join-Path $PSScriptRoot "debug_skill.ps1"
# HelloArgsFile contains the deterministic minimal-tool smoke payload.
# HelloArgsFile 包含确定性的最小工具冒烟参数。
$HelloArgsFile = Join-Path $ProjectRoot "examples\debug\hello.args.json"
# PackageRelease runs validate and package, which need every bundled payload dependencies.yaml declares.
# PackageRelease 执行 validate 与 package，二者需要 dependencies.yaml 声明的每个内置载荷。
$PackageRelease = $true
# >>> demo-only
# NativeBuildScript builds the bundled native library for this host.
# NativeBuildScript 为当前主机构建内置原生库。
$NativeBuildScript = Join-Path $PSScriptRoot "build_native.py"
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
# NativeArgsFile contains the deterministic bundled native library payload.
# NativeArgsFile 包含确定性的内置原生库参数。
$NativeArgsFile = Join-Path $ProjectRoot "examples\debug\native-demo.args.json"
# The demo declares native libraries for five systems but builds only this host's; the release workflow validates
# and packages after all five builds.
# 演示声明了五个系统的原生库，但本地只构建当前主机的一份；发布 workflow 在五个构建完成后校验并打包。
$PackageRelease = $false
# <<< demo-only

Set-Location $ProjectRoot
# >>> demo-only
& python $NativeBuildScript
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
# <<< demo-only
& python -m unittest discover -s tests -v
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
& powershell -NoProfile -ExecutionPolicy Bypass -File $DebugScript -Command call -Tool hello -ArgsFile $HelloArgsFile -Output json
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
# >>> demo-only
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
& powershell -NoProfile -ExecutionPolicy Bypass -File $DebugScript -Command call -Tool native-demo -ArgsFile $NativeArgsFile -Output json
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
# <<< demo-only
if (-not $PackageRelease) {
    Write-Host "Skipping validate and package: the release workflow runs them after every bundled payload is built."
    exit 0
}
& powershell -NoProfile -ExecutionPolicy Bypass -File $DebugScript -Command validate
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
& powershell -NoProfile -ExecutionPolicy Bypass -File $DebugScript -Command package
exit $LASTEXITCODE
