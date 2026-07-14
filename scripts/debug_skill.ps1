<#
.SYNOPSIS
Run the official LuaSkills debug launcher against the repository-root skill.
使用官方 LuaSkills 调试启动器运行仓库根目录中的 skill。
#>
param(
    # Debug command forwarded to the official launcher.
    # 转发给官方启动器的调试命令。
    [ValidateSet("sync", "inspect", "list-tools", "call")]
    [string]$Command = "inspect",
    # Tool name required by the call command.
    # call 命令需要的工具名称。
    [string]$Tool = "",
    # Inline JSON invocation payload.
    # 内联 JSON 调用参数。
    [string]$ArgsJson = "",
    # JSON file containing the invocation payload.
    # 包含调用参数的 JSON 文件。
    [string]$ArgsFile = "",
    # Debug output rendering mode.
    # 调试输出渲染模式。
    [ValidateSet("pretty", "json", "content")]
    [string]$Output = "pretty",
    # Whether to enable the host_result bridge.
    # 是否启用 host_result 桥接。
    [switch]$EnableHostResult
)

# ErrorActionPreference makes staging and debugger failures explicit and terminating.
# ErrorActionPreference 让暂存与调试器错误显式终止执行。
$ErrorActionPreference = "Stop"

<#
.SYNOPSIS
Acquire one process-owned mutex for the repository debugger critical section.
为仓库调试器临界区获取一个由进程持有的互斥锁。

.PARAMETER ProjectRoot
Absolute repository root used to derive a collision-resistant mutex name.
用于派生抗冲突互斥锁名称的仓库绝对根目录。

.OUTPUTS
System.Threading.Mutex acquired by the current process.
当前进程已获取的 System.Threading.Mutex。
#>
function Enter-RepositoryDebugMutex {
    param(
        # ProjectRoot is the canonical repository identity protected by the mutex.
        # ProjectRoot 是互斥锁保护的规范仓库标识。
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    # NormalizedRoot prevents path-casing differences from creating distinct mutexes.
    # NormalizedRoot 防止路径大小写差异生成不同互斥锁。
    $NormalizedRoot = [System.IO.Path]::GetFullPath($ProjectRoot).ToLowerInvariant()
    # HashAlgorithm derives a fixed-size mutex suffix without exposing the repository path.
    # HashAlgorithm 派生固定长度的互斥锁后缀，同时不暴露仓库路径。
    $HashAlgorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        # RootBytes is the UTF-8 representation used by the stable repository digest.
        # RootBytes 是稳定仓库摘要使用的 UTF-8 表示。
        $RootBytes = [System.Text.Encoding]::UTF8.GetBytes($NormalizedRoot)
        # RootHash is the lowercase hexadecimal repository identity.
        # RootHash 是小写十六进制仓库标识。
        $RootHash = -join ($HashAlgorithm.ComputeHash($RootBytes) | ForEach-Object { $_.ToString("x2") })
    }
    finally {
        $HashAlgorithm.Dispose()
    }

    # MutexName is local to the current Windows session and unique per repository.
    # MutexName 在当前 Windows 会话内有效，并且每个仓库唯一。
    $MutexName = "Local\LuaSkillsDebug-$RootHash"
    # DebugMutex is automatically released by the operating system if this process exits.
    # DebugMutex 会在当前进程退出时由操作系统自动释放。
    $DebugMutex = [System.Threading.Mutex]::new($false, $MutexName)
    # LockAcquired records whether the two-minute bounded wait obtained ownership.
    # LockAcquired 记录两分钟有界等待是否取得所有权。
    $LockAcquired = $false
    try {
        $LockAcquired = $DebugMutex.WaitOne([TimeSpan]::FromMinutes(2))
    }
    catch [System.Threading.AbandonedMutexException] {
        # An abandoned mutex is owned by this process when the exception is raised.
        # 抛出遗弃互斥锁异常时，当前进程已经取得该互斥锁。
        $LockAcquired = $true
    }
    if (-not $LockAcquired) {
        $DebugMutex.Dispose()
        throw "Timed out waiting for another LuaSkills debugger command in this repository."
    }
    return $DebugMutex
}

# ProjectRoot is the repository that owns the source skill files.
# ProjectRoot 是保存源 skill 文件的仓库。
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
# DebugRoot is the ignored standalone debug workspace.
# DebugRoot 是被忽略的独立调试工作区。
$DebugRoot = Join-Path $ProjectRoot ".luaskills-debug"
# LauncherPath is the official debug package PowerShell launcher.
# LauncherPath 是官方调试包的 PowerShell 启动器。
$LauncherPath = Join-Path $DebugRoot "debug.ps1"
# DebugMutex serializes setup, staging, synchronization, and invocation for this repository.
# DebugMutex 串行化当前仓库的初始化、暂存、同步与调用。
$DebugMutex = Enter-RepositoryDebugMutex -ProjectRoot $ProjectRoot
# ExitCode preserves the official launcher process result until after mutex release.
# ExitCode 保留官方启动器进程结果，直到互斥锁释放后再退出。
$ExitCode = 1

try {
    # SetupPath is the idempotent bootstrap executed inside the repository mutex.
    # SetupPath 是在仓库互斥锁内执行的幂等初始化脚本。
    $SetupPath = Join-Path $PSScriptRoot "setup_debug.ps1"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $SetupPath
    if ($LASTEXITCODE -ne 0) {
        throw "LuaSkills debug workspace setup failed with exit code $LASTEXITCODE."
    }

    # StageScript copies only formal release-package files into the ignored workspace.
    # StageScript 仅把正式发布包文件复制到被忽略的工作区。
    $StageScript = Join-Path $PSScriptRoot "stage_debug_skill.py"
    # StagedSkillPath is the clean source directory synchronized by the official debugger.
    # StagedSkillPath 是由官方调试器同步的干净源目录。
    $StagedSkillPath = (& python $StageScript | Select-Object -Last 1).Trim()
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $StagedSkillPath -PathType Container)) {
        throw "Failed to stage the current LuaSkill for debugging."
    }

    # ForwardedParameters contains only arguments explicitly supported by the official launcher.
    # ForwardedParameters 只包含官方启动器明确支持的参数。
    $ForwardedParameters = @{
        Command = $Command
        SkillPath = $StagedSkillPath
        Output = $Output
    }
    if (-not [string]::IsNullOrWhiteSpace($Tool)) {
        $ForwardedParameters.Tool = $Tool
    }
    if (-not [string]::IsNullOrWhiteSpace($ArgsJson)) {
        $ForwardedParameters.ArgsJson = $ArgsJson
    }
    if (-not [string]::IsNullOrWhiteSpace($ArgsFile)) {
        $ForwardedParameters.ArgsFile = (Resolve-Path -LiteralPath $ArgsFile).Path
    }
    if ($EnableHostResult) {
        $ForwardedParameters.EnableHostResult = $true
    }

    & $LauncherPath @ForwardedParameters
    $ExitCode = $LASTEXITCODE
}
finally {
    $DebugMutex.ReleaseMutex()
    $DebugMutex.Dispose()
}

exit $ExitCode
