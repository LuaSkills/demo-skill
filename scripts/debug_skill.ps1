<#
.SYNOPSIS
Run the official LuaSkills debugger against the repository-root skill.
使用官方 LuaSkills 调试器运行仓库根目录中的 skill。
#>
param(
    # Debug command forwarded to the official debugger.
    # 转发给官方调试器的调试命令。
    [ValidateSet("sync", "inspect", "list-tools", "call", "probe-mirrors")]
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
    [switch]$EnableHostResult,
    # Built-in mirror id or mirror URL for GitHub release downloads; probe-mirrors accepts several.
    # GitHub Release 下载使用的内置镜像标识或镜像地址；probe-mirrors 可接收多个。
    [string[]]$GithubMirror = @(),
    # Name of the environment variable that holds a GitHub token; never the token itself.
    # 保存 GitHub 令牌的环境变量名称；绝不是令牌本身。
    [string]$GithubTokenEnv = ""
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
# BinaryPath is the official debugger executable. The v0.7.2 package launchers forward only the classic flags,
# so the wrapper calls the executable directly to reach --github-mirror, --github-token-env, and probe-mirrors.
# BinaryPath 是官方调试器可执行文件。v0.7.2 包内启动器只转发传统参数，
# 因此封装脚本直接调用可执行文件，以支持 --github-mirror、--github-token-env 与 probe-mirrors。
$BinaryPath = Join-Path $DebugRoot "bin\luaskills-debug.exe"
# RuntimeRoot is the package-local runtime used by every official debugger command.
# RuntimeRoot 是所有官方调试命令共同使用的包内 runtime。
$RuntimeRoot = Join-Path $DebugRoot "runtime"
if ($Command -eq "probe-mirrors") {
    if ($Tool -or $ArgsJson -or $ArgsFile -or $EnableHostResult -or $GithubTokenEnv) {
        throw "probe-mirrors accepts only -GithubMirror and -Output."
    }
}
elseif ($GithubMirror.Count -gt 1) {
    throw "$Command accepts at most one -GithubMirror value; only probe-mirrors compares several mirrors."
}
# DebugMutex serializes setup, staging, synchronization, and invocation for this repository.
# DebugMutex 串行化当前仓库的初始化、暂存、同步与调用。
$DebugMutex = Enter-RepositoryDebugMutex -ProjectRoot $ProjectRoot
# ExitCode preserves the official debugger process result until after mutex release.
# ExitCode 保留官方调试器进程结果，直到互斥锁释放后再退出。
$ExitCode = 1

try {
    # SetupPath is the idempotent bootstrap executed inside the repository mutex.
    # SetupPath 是在仓库互斥锁内执行的幂等初始化脚本。
    $SetupPath = Join-Path $PSScriptRoot "setup_debug.ps1"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $SetupPath
    if ($LASTEXITCODE -ne 0) {
        throw "LuaSkills debug workspace setup failed with exit code $LASTEXITCODE."
    }

    if (-not (Test-Path -LiteralPath $BinaryPath -PathType Leaf)) {
        throw "luaskills-debug executable was not found: $BinaryPath"
    }

    # ForwardedArgs contains only options accepted by the selected debugger subcommand.
    # ForwardedArgs 只包含所选调试器子命令接受的选项。
    $ForwardedArgs = @($Command)
    if ($Command -ne "probe-mirrors") {
        # StageScript copies only formal release-package files into the ignored workspace.
        # StageScript 仅把正式发布包文件复制到被忽略的工作区。
        $StageScript = Join-Path $PSScriptRoot "stage_debug_skill.py"
        # StagedSkillPath is the clean source directory synchronized by the official debugger.
        # StagedSkillPath 是由官方调试器同步的干净源目录。
        $StagedSkillPath = (& python $StageScript | Select-Object -Last 1).Trim()
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $StagedSkillPath -PathType Container)) {
            throw "Failed to stage the current LuaSkill for debugging."
        }
        $ForwardedArgs += @("--runtime-root", $RuntimeRoot, "--skill-path", $StagedSkillPath)
        if (-not [string]::IsNullOrWhiteSpace($Tool)) {
            $ForwardedArgs += @("--tool", $Tool)
        }
        if (-not [string]::IsNullOrWhiteSpace($ArgsJson)) {
            $ForwardedArgs += @("--args-json", $ArgsJson)
        }
        if (-not [string]::IsNullOrWhiteSpace($ArgsFile)) {
            $ForwardedArgs += @("--args-file", (Resolve-Path -LiteralPath $ArgsFile).Path)
        }
        if ($EnableHostResult) {
            $ForwardedArgs += "--enable-host-result"
        }
        if (-not [string]::IsNullOrWhiteSpace($GithubTokenEnv)) {
            $ForwardedArgs += @("--github-token-env", $GithubTokenEnv)
        }
    }
    # Mirror is one built-in mirror id or mirror URL passed through unchanged.
    # Mirror 是原样传递的单个内置镜像标识或镜像地址。
    foreach ($Mirror in $GithubMirror) {
        $ForwardedArgs += @("--github-mirror", $Mirror)
    }
    $ForwardedArgs += @("--output", $Output)

    & $BinaryPath @ForwardedArgs
    $ExitCode = $LASTEXITCODE
}
finally {
    $DebugMutex.ReleaseMutex()
    $DebugMutex.Dispose()
}

exit $ExitCode
