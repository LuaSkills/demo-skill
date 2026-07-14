<#
.SYNOPSIS
Validate, package, create, and push the manifest-matching annotated release tag.
校验、打包、创建并推送与清单匹配的带注释发布标签。

.PARAMETER Version
Exact semantic version declared by skill.yaml, with an optional leading v.
skill.yaml 声明的精确语义化版本，可带前导 v。
#>
param(
    # Version is the requested release version validated before any Git mutation.
    # Version 是在任何 Git 变更前接受校验的请求发布版本。
    [Parameter(Mandatory = $true)]
    [string]$Version
)

# ErrorActionPreference turns validation and process failures into terminating errors.
# ErrorActionPreference 将校验与进程失败转换为终止错误。
$ErrorActionPreference = "Stop"
# ProjectRoot is the clean repository state that will be referenced by the tag.
# ProjectRoot 是标签将引用的干净仓库状态。
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
# VerifyScript runs the complete debugger, invocation, and packaging flow.
# VerifyScript 执行完整调试器、调用与打包流程。
$VerifyScript = Join-Path $PSScriptRoot "verify_skill.ps1"
# ResolveVersionModule enforces the single manifest-derived release tag.
# ResolveVersionModule 强制使用由清单派生的唯一发布标签。
$ResolveVersionModule = "scripts.release_version"

Set-Location $ProjectRoot
# WorktreeEntries lists tracked and untracked changes that would be absent from the tag.
# WorktreeEntries 列出不会进入标签的已跟踪与未跟踪变更。
$WorktreeEntries = @(& git status --porcelain=v1)
if ($LASTEXITCODE -ne 0) {
    throw "Unable to inspect the Git working tree before release."
}
if ($WorktreeEntries.Count -gt 0) {
    throw "Release requires a clean Git working tree. Commit or remove all changes first."
}

# ReleaseTag is the exact validated v-prefixed tag printed by the shared resolver.
# ReleaseTag 是共享解析器输出的精确已校验 v 前缀标签。
$ReleaseTag = (& python -m $ResolveVersionModule $Version).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($ReleaseTag)) {
    throw "Release version validation failed."
}

& powershell -NoProfile -ExecutionPolicy Bypass -File $VerifyScript
if ($LASTEXITCODE -ne 0) {
    throw "Release verification failed with exit code $LASTEXITCODE."
}

Write-Host "Creating annotated tag: $ReleaseTag"
& git tag -a $ReleaseTag -m "发布 $ReleaseTag"
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host "Pushing tag to origin: $ReleaseTag"
& git push origin $ReleaseTag
exit $LASTEXITCODE
