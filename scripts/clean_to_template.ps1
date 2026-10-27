<#
.SYNOPSIS
Turn the demo repository into a minimal LuaSkill template with one hello tool.
将演示仓库转换为只保留一个 hello 工具的最小 LuaSkill 模板。

.PARAMETER Yes
Confirm that demo files may be deleted and rewritten; without it the cleaner only lists the planned changes.
确认可以删除并改写演示文件；未传入时清理脚本只列出计划中的变更。

.PARAMETER Force
Run even when the Git working tree has uncommitted or untracked changes.
即使 Git 工作区存在未提交或未跟踪的变更也继续执行。
#>
param(
    # Yes forwards --yes to the shared Python cleaner.
    # Yes 将 --yes 转发给共享 Python 清理脚本。
    [switch]$Yes,
    # Force forwards --force to the shared Python cleaner.
    # Force 将 --force 转发给共享 Python 清理脚本。
    [switch]$Force
)

# ErrorActionPreference turns process launch failures into terminating errors.
# ErrorActionPreference 将进程启动失败转换为终止错误。
$ErrorActionPreference = "Stop"
# CleanerScript is the shared implementation used by both wrappers.
# CleanerScript 是两个封装脚本共用的实现。
$CleanerScript = Join-Path $PSScriptRoot "clean_to_template.py"
# ForwardedArgs contains only the switches explicitly selected by the caller.
# ForwardedArgs 只包含调用方显式选择的开关。
$ForwardedArgs = @()
if ($Yes) {
    $ForwardedArgs += "--yes"
}
if ($Force) {
    $ForwardedArgs += "--force"
}

& python $CleanerScript @ForwardedArgs
exit $LASTEXITCODE
