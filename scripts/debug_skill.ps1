<#
.SYNOPSIS
Run luaskills-debug against the repository-root skill: load, call, validate, or package it.
使用 luaskills-debug 处理仓库根目录中的 skill：加载、调用、校验或打包。
#>
param(
    # Debug command forwarded to the official debugger.
    # 转发给官方调试器的调试命令。
    [ValidateSet("sync", "inspect", "list-tools", "call", "validate", "package", "probe-mirrors")]
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
    [string]$GithubTokenEnv = "",
    # Release layout used by package: standard (default) or platform; LUASKILLS_PACKAGE_LAYOUT overrides the default.
    # package 使用的发布布局：standard（默认）或 platform；LUASKILLS_PACKAGE_LAYOUT 可覆盖默认值。
    [ValidateSet("", "standard", "platform")]
    [string]$Layout = "",
    # Directory that receives the release assets written by package.
    # 接收 package 写出的发布资产的目录。
    [string]$OutDir = "dist",
    # Extra top-level entries that validate and package ship beside the default package entries.
    # validate 与 package 在默认包条目之外额外发布的顶层条目。
    [string[]]$Include = @(),
    # Omit the all-systems package from a platform release.
    # 在分平台发布中省略全系统包。
    [switch]$NoUniversal
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
# BinaryPath is the luaskills-debug executable. The wrapper calls it directly so every subcommand and option is reachable.
# BinaryPath 是 luaskills-debug 可执行文件。封装脚本直接调用它，使每个子命令与选项都可用。
$BinaryPath = Join-Path $DebugRoot "bin\luaskills-debug.exe"
# RuntimeRoot is the package-local runtime used by every official debugger command.
# RuntimeRoot 是所有官方调试命令共同使用的包内 runtime。
$RuntimeRoot = Join-Path $DebugRoot "runtime"
if ($Command -eq "probe-mirrors") {
    if ($Tool -or $ArgsJson -or $ArgsFile -or $EnableHostResult -or $GithubTokenEnv) {
        throw "probe-mirrors accepts only -GithubMirror and -Output."
    }
}
elseif ($Command -in @("validate", "package")) {
    if ($Tool -or $ArgsJson -or $ArgsFile -or $EnableHostResult -or $GithubTokenEnv -or $GithubMirror.Count -gt 0) {
        throw "$Command accepts only -Layout, -OutDir, -Include, -NoUniversal and -Output."
    }
    if ($Output -eq "content") {
        throw "$Command renders pretty or json output."
    }
}
elseif ($Include.Count -gt 0 -or $NoUniversal) {
    throw "-Include and -NoUniversal apply only to validate and package."
}
elseif ($GithubMirror.Count -gt 1) {
    throw "$Command accepts at most one -GithubMirror value; only probe-mirrors compares several mirrors."
}
if ([string]::IsNullOrWhiteSpace($Layout)) {
    $Layout = if ([string]::IsNullOrWhiteSpace($env:LUASKILLS_PACKAGE_LAYOUT)) { "standard" } else { $env:LUASKILLS_PACKAGE_LAYOUT }
}
# DebugMutex serializes setup, synchronization, and invocation for this repository.
# DebugMutex 串行化当前仓库的初始化、同步与调用。
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
    if ($Command -in @("validate", "package")) {
        $ForwardedArgs += @("--skill-path", $ProjectRoot)
        foreach ($Entry in $Include) {
            $ForwardedArgs += @("--include", $Entry)
        }
    }
    if ($Command -eq "package") {
        # ResolvedOutDir anchors a relative -OutDir to the repository root, matching debug_skill.sh.
        # ResolvedOutDir 将相对 -OutDir 锚定到仓库根目录，与 debug_skill.sh 一致。
        $ResolvedOutDir = if ([System.IO.Path]::IsPathRooted($OutDir)) { $OutDir } else { Join-Path $ProjectRoot $OutDir }
        $ForwardedArgs += @("--out-dir", $ResolvedOutDir, "--layout", $Layout)
        if ($NoUniversal) {
            $ForwardedArgs += "--no-universal"
        }
    }
    if ($Command -notin @("validate", "package", "probe-mirrors")) {
        # The debugger copies the repository into the runtime root and skips build, checkout and packaging folders.
        # 调试器把仓库复制到 runtime root，并跳过构建、检出与打包目录。
        $ForwardedArgs += @("--runtime-root", $RuntimeRoot, "--skill-path", $ProjectRoot)
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
