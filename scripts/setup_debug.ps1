<#
.SYNOPSIS
Download, verify, and initialize the pinned LuaSkills debug workspace.
下载、校验并初始化固定版本的 LuaSkills 调试工作区。

.PARAMETER Version
Optional LuaSkills release tag that overrides .luaskills-version.
可选的 LuaSkills 发布标签，用于覆盖 .luaskills-version。

.PARAMETER SkipRuntimeSetup
Skip downloading Lua runtime packages after extracting the debug tool.
解压调试器后跳过 Lua runtime packages 下载。

.PARAMETER SkipManagedNodeSetup
Skip downloading the pinned managed Node.js and pnpm distributions.
跳过固定版本的受管 Node.js 与 pnpm 发行版下载。

.PARAMETER Force
Recreate the ignored debug workspace even when the requested version is installed.
即使目标版本已安装，也重新创建被忽略的调试工作区。
#>
param(
    # Optional release tag override.
    # 可选的发布标签覆盖值。
    [string]$Version = "",
    # Whether Lua runtime package setup should be skipped.
    # 是否跳过 Lua runtime package 初始化。
    [switch]$SkipRuntimeSetup,
    # Whether managed Node.js and pnpm setup should be skipped.
    # 是否跳过受管 Node.js 与 pnpm 初始化。
    [switch]$SkipManagedNodeSetup,
    # Whether the existing debug workspace should be rebuilt.
    # 是否重建已有调试工作区。
    [switch]$Force
)

# ErrorActionPreference makes every setup failure explicit and terminating.
# ErrorActionPreference 让所有初始化错误显式终止执行。
$ErrorActionPreference = "Stop"

function Get-ProjectRoot {
    <#
    .SYNOPSIS
    Resolve the repository root from this script location.
    根据当前脚本位置解析仓库根目录。

    .OUTPUTS
    Absolute repository root path.
    仓库根目录绝对路径。
    #>
    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
}

function Resolve-ReleaseTag {
    <#
    .SYNOPSIS
    Resolve and validate the effective LuaSkills release tag.
    解析并校验最终使用的 LuaSkills 发布标签。

    .PARAMETER ProjectRoot
    Absolute repository root containing .luaskills-version.
    包含 .luaskills-version 的仓库根目录绝对路径。

    .PARAMETER Override
    Optional caller-provided release tag.
    调用方提供的可选发布标签。

    .OUTPUTS
    Normalized release tag with a leading v.
    带 v 前缀的标准化发布标签。
    #>
    param(
        [string]$ProjectRoot,
        [string]$Override
    )

    # VersionFile is the repository-owned LuaSkills compatibility baseline.
    # VersionFile 是仓库维护的 LuaSkills 兼容版本基线文件。
    $VersionFile = Join-Path $ProjectRoot ".luaskills-version"
    # RawVersion comes from the explicit override or the pinned version file.
    # RawVersion 来自显式覆盖值或固定版本文件。
    $RawVersion = if ([string]::IsNullOrWhiteSpace($Override)) {
        if (-not (Test-Path -LiteralPath $VersionFile -PathType Leaf)) {
            throw "Missing LuaSkills version file: $VersionFile"
        }
        (Get-Content -Raw -Encoding UTF8 -LiteralPath $VersionFile).Trim()
    } else {
        $Override.Trim()
    }
    # ReleaseTag normalizes a semantic version into the GitHub tag form.
    # ReleaseTag 将语义版本标准化为 GitHub 标签格式。
    $ReleaseTag = if ($RawVersion.StartsWith("v")) { $RawVersion } else { "v$RawVersion" }
    if ($ReleaseTag -notmatch '^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:[-+][0-9A-Za-z.-]+)?$') {
        throw "Invalid LuaSkills release tag: $ReleaseTag"
    }
    return $ReleaseTag
}

function Get-WindowsPlatformKey {
    <#
    .SYNOPSIS
    Resolve the official Windows debug asset platform key.
    解析官方 Windows 调试资产的平台标识。

    .OUTPUTS
    Supported official release platform key.
    受支持的官方发布平台标识。
    #>
    if (-not [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
        throw "setup_debug.ps1 supports Windows packages only. Use scripts/setup_debug.sh on Linux or macOS."
    }

    # Architecture is the current PowerShell process architecture.
    # Architecture 是当前 PowerShell 进程架构。
    $Architecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString().ToLowerInvariant()
    if ($Architecture -ne "x64") {
        throw "The official LuaSkills release does not provide a Windows debug asset for architecture '$Architecture'."
    }
    return "windows-x64"
}

function Get-Sha256Hash {
    <#
    .SYNOPSIS
    Calculate a lowercase SHA-256 digest without relying on optional cmdlets.
    在不依赖可选 cmdlet 的情况下计算小写 SHA-256 摘要。

    .PARAMETER Path
    File path whose digest must be calculated.
    需要计算摘要的文件路径。

    .OUTPUTS
    Lowercase hexadecimal SHA-256 digest.
    小写十六进制 SHA-256 摘要。
    #>
    param([string]$Path)

    # Sha256 is the framework-provided hash algorithm instance.
    # Sha256 是框架提供的哈希算法实例。
    $Sha256 = [System.Security.Cryptography.SHA256]::Create()
    # Stream is the read-only archive stream consumed by the hash algorithm.
    # Stream 是供哈希算法读取的只读压缩包流。
    $Stream = [System.IO.File]::OpenRead($Path)
    try {
        # HashBytes contains the binary SHA-256 result.
        # HashBytes 包含二进制 SHA-256 结果。
        $HashBytes = $Sha256.ComputeHash($Stream)
        return -join ($HashBytes | ForEach-Object { $_.ToString("x2") })
    } finally {
        $Stream.Dispose()
        $Sha256.Dispose()
    }
}

function Clear-DirectoryAttributes {
    <#
    .SYNOPSIS
    Clear read-only attributes below one verified debugger workspace path.
    清除已校验调试工作区路径下的只读属性。

    .PARAMETER Path
    Extended-length directory path whose generated contents will be normalized.
    需要标准化生成内容的扩展长度目录路径。
    #>
    param([string]$Path)

    # FilePaths are generated files that may inherit read-only Git object attributes.
    # FilePaths 是可能继承 Git 对象只读属性的生成文件。
    $FilePaths = [System.IO.Directory]::EnumerateFiles($Path)
    foreach ($FilePath in $FilePaths) {
        [System.IO.File]::SetAttributes($FilePath, [System.IO.FileAttributes]::Normal)
    }

    # DirectoryPaths are generated child directories normalized recursively before deletion.
    # DirectoryPaths 是删除前递归标准化的生成子目录。
    $DirectoryPaths = [System.IO.Directory]::EnumerateDirectories($Path)
    foreach ($DirectoryPath in $DirectoryPaths) {
        Clear-DirectoryAttributes -Path $DirectoryPath
        [System.IO.File]::SetAttributes($DirectoryPath, [System.IO.FileAttributes]::Directory)
    }
    [System.IO.File]::SetAttributes($Path, [System.IO.FileAttributes]::Directory)
}

function Remove-DebugWorkspace {
    <#
    .SYNOPSIS
    Remove only the verified repository-local debug workspace.
    仅删除已校验的仓库本地调试工作区。

    .PARAMETER ProjectRoot
    Absolute repository root path.
    仓库根目录绝对路径。

    .PARAMETER DebugRoot
    Absolute debug workspace path to remove.
    要删除的调试工作区绝对路径。
    #>
    param(
        [string]$ProjectRoot,
        [string]$DebugRoot
    )

    # ExpectedDebugRoot is the only recursive deletion target allowed by this script.
    # ExpectedDebugRoot 是此脚本唯一允许递归删除的目标。
    $ExpectedDebugRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot ".luaskills-debug"))
    # ResolvedDebugRoot normalizes the caller path before the safety comparison.
    # ResolvedDebugRoot 在安全比较前标准化调用方路径。
    $ResolvedDebugRoot = [System.IO.Path]::GetFullPath($DebugRoot)
    if ($ResolvedDebugRoot -ne $ExpectedDebugRoot) {
        throw "Refusing to remove an unexpected debug path: $ResolvedDebugRoot"
    }
    if (Test-Path -LiteralPath $ResolvedDebugRoot) {
        # ExtendedDebugRoot enables deterministic cleanup of debugger-created long paths on Windows.
        # ExtendedDebugRoot 支持确定性清理调试器在 Windows 上生成的超长路径。
        $ExtendedDebugRoot = "\\?\$ResolvedDebugRoot"
        Clear-DirectoryAttributes -Path $ExtendedDebugRoot
        [System.IO.Directory]::Delete($ExtendedDebugRoot, $true)
    }
}

function Test-InstalledVersion {
    <#
    .SYNOPSIS
    Check whether the requested debug tool version is already installed.
    检查请求的调试器版本是否已经安装。

    .PARAMETER DebugRoot
    Absolute debug workspace path.
    调试工作区绝对路径。

    .PARAMETER ReleaseTag
    Requested LuaSkills release tag.
    请求的 LuaSkills 发布标签。

    .OUTPUTS
    Boolean installation match result.
    布尔类型的安装匹配结果。
    #>
    param(
        [string]$DebugRoot,
        [string]$ReleaseTag
    )

    # LauncherPath is the required official Windows debug launcher.
    # LauncherPath 是必需的官方 Windows 调试启动器。
    $LauncherPath = Join-Path $DebugRoot "debug.ps1"
    # InstalledVersionFile records the exact downloaded LuaSkills release tag.
    # InstalledVersionFile 记录实际下载的 LuaSkills 发布标签。
    $InstalledVersionFile = Join-Path $DebugRoot ".installed-version"
    if (-not (Test-Path -LiteralPath $LauncherPath -PathType Leaf) -or -not (Test-Path -LiteralPath $InstalledVersionFile -PathType Leaf)) {
        return $false
    }
    # InstalledVersion is the normalized tag persisted by a successful setup.
    # InstalledVersion 是成功初始化后持久化的标准化标签。
    $InstalledVersion = (Get-Content -Raw -Encoding UTF8 -LiteralPath $InstalledVersionFile).Trim()
    return $InstalledVersion -eq $ReleaseTag
}

function Install-ManagedNodeRuntime {
    <#
    .SYNOPSIS
    Download the pinned official managed-runtime fetcher and install Node.js plus pnpm.
    下载固定版本的官方受管运行时拉取器，并安装 Node.js 与 pnpm。

    .PARAMETER DebugRoot
    Absolute ignored LuaSkills debug workspace path.
    被忽略的 LuaSkills 调试工作区绝对路径。

    .PARAMETER ReleaseTag
    LuaSkills release tag that owns the verified fetcher script.
    提供已校验拉取脚本的 LuaSkills 发布标签。
    #>
    param(
        [string]$DebugRoot,
        [string]$ReleaseTag
    )

    # NodeVersion is the exact managed Node.js version declared by dependencies.yaml.
    # NodeVersion 是 dependencies.yaml 声明的精确受管 Node.js 版本。
    $NodeVersion = "24.18.0"
    # PnpmVersion is the exact managed package-manager version declared by dependencies.yaml.
    # PnpmVersion 是 dependencies.yaml 声明的精确受管包管理器版本。
    $PnpmVersion = "11.11.0"
    # VerifiedReleaseTag identifies the release whose fetcher digest is pinned below.
    # VerifiedReleaseTag 标识下方固定拉取器摘要对应的发布版本。
    $VerifiedReleaseTag = "v0.5.2"
    # ExpectedFetcherHash is the SHA-256 digest of the v0.5.2 PowerShell fetcher.
    # ExpectedFetcherHash 是 v0.5.2 PowerShell 拉取脚本的 SHA-256 摘要。
    $ExpectedFetcherHash = "59e0bf3b6e85b34299a16517e4045e88facd08165ad9511df99fc33d9295dcbe"
    if ($ReleaseTag -ne $VerifiedReleaseTag) {
        throw "Managed Node.js fetcher checksum is not registered for $ReleaseTag. Update the pinned checksum or use -SkipManagedNodeSetup."
    }

    # RuntimeRoot is the compatible LuaSkills data root used by the debug binary.
    # RuntimeRoot 是调试二进制使用的兼容 LuaSkills 数据根。
    $RuntimeRoot = Join-Path $DebugRoot "runtime"
    # NodeManifest is the official installation marker for the pinned Node.js distribution.
    # NodeManifest 是固定 Node.js 发行版的官方安装标记。
    $NodeManifest = Join-Path $RuntimeRoot "dependencies\runtimes\node\node-$NodeVersion-windows-x64\runtime-manifest.json"
    # PnpmManifest is the official installation marker for the pinned pnpm distribution.
    # PnpmManifest 是固定 pnpm 发行版的官方安装标记。
    $PnpmManifest = Join-Path $RuntimeRoot "dependencies\runtimes\node\pnpm-$PnpmVersion\runtime-manifest.json"
    if ((Test-Path -LiteralPath $NodeManifest -PathType Leaf) -and (Test-Path -LiteralPath $PnpmManifest -PathType Leaf)) {
        Write-Host "Managed Node.js $NodeVersion and pnpm $PnpmVersion are already initialized."
        return
    }

    # FetcherDirectory is the package-compatible location expected by the official script.
    # FetcherDirectory 是官方脚本期望的包兼容位置。
    $FetcherDirectory = Join-Path $DebugRoot "scripts\deps"
    New-Item -ItemType Directory -Force -Path $FetcherDirectory | Out-Null
    # FetcherPath is the verified script executed only after digest validation.
    # FetcherPath 是仅在摘要校验后执行的脚本路径。
    $FetcherPath = Join-Path $FetcherDirectory "fetch_managed_runtimes.ps1"
    # FetcherDownloadPath isolates incomplete downloads from executable script paths.
    # FetcherDownloadPath 将未完成下载与可执行脚本路径隔离。
    $FetcherDownloadPath = "$FetcherPath.download"
    # FetcherUrl is the immutable tag-bound official source URL.
    # FetcherUrl 是绑定不可变标签的官方源码地址。
    $FetcherUrl = "https://raw.githubusercontent.com/LuaSkills/luaskills/$ReleaseTag/scripts/deps/fetch_managed_runtimes.ps1"
    Invoke-WebRequest -UseBasicParsing -Uri $FetcherUrl -OutFile $FetcherDownloadPath
    # ActualFetcherHash verifies the exact downloaded script bytes before execution.
    # ActualFetcherHash 在执行前校验下载脚本的精确字节。
    $ActualFetcherHash = Get-Sha256Hash -Path $FetcherDownloadPath
    if ($ActualFetcherHash -ne $ExpectedFetcherHash) {
        throw "SHA-256 mismatch for managed runtime fetcher. Expected $ExpectedFetcherHash, got $ActualFetcherHash."
    }
    Move-Item -Force -LiteralPath $FetcherDownloadPath -Destination $FetcherPath

    & powershell -NoProfile -ExecutionPolicy Bypass -File $FetcherPath -Target node -RuntimeRoot $RuntimeRoot -NodeVersion $NodeVersion -PnpmVersion $PnpmVersion
    if ($LASTEXITCODE -ne 0) {
        throw "Managed Node.js setup failed with exit code $LASTEXITCODE."
    }
    if (-not (Test-Path -LiteralPath $NodeManifest -PathType Leaf) -or -not (Test-Path -LiteralPath $PnpmManifest -PathType Leaf)) {
        throw "Managed Node.js setup completed without the documented runtime manifests."
    }
}

# ProjectRoot anchors every generated or downloaded path inside this repository.
# ProjectRoot 将所有生成与下载路径限定在当前仓库内。
$ProjectRoot = Get-ProjectRoot
# DebugRoot is the Git-ignored standalone LuaSkills debug workspace.
# DebugRoot 是被 Git 忽略的独立 LuaSkills 调试工作区。
$DebugRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot ".luaskills-debug"))
# ReleaseTag is the verified LuaSkills release used by this workspace.
# ReleaseTag 是当前工作区使用的已校验 LuaSkills 发布版本。
$ReleaseTag = Resolve-ReleaseTag -ProjectRoot $ProjectRoot -Override $Version
# PlatformKey selects the exact official GitHub release asset.
# PlatformKey 用于选择精确的官方 GitHub Release 资产。
$PlatformKey = Get-WindowsPlatformKey
# AssetName is the official standalone debug tool archive name.
# AssetName 是官方独立调试器压缩包名称。
$AssetName = "luaskills-debug-tool-$PlatformKey.tar.gz"
# ReleaseBaseUrl is the immutable GitHub release download directory.
# ReleaseBaseUrl 是不可变的 GitHub Release 下载目录。
$ReleaseBaseUrl = "https://github.com/LuaSkills/luaskills/releases/download/$ReleaseTag"

# ExistingMatch indicates whether download and extraction can be reused.
# ExistingMatch 表示是否可以复用已有下载与解压结果。
$ExistingMatch = Test-InstalledVersion -DebugRoot $DebugRoot -ReleaseTag $ReleaseTag
if ($Force -or -not $ExistingMatch) {
    Remove-DebugWorkspace -ProjectRoot $ProjectRoot -DebugRoot $DebugRoot
    New-Item -ItemType Directory -Force -Path $DebugRoot | Out-Null

    # ArchivePath stores the downloaded official debug archive inside the ignored workspace.
    # ArchivePath 将下载的官方调试压缩包保存在被忽略的工作区内。
    $ArchivePath = Join-Path $DebugRoot $AssetName
    # ChecksumPath stores the official checksum sidecar next to the archive.
    # ChecksumPath 将官方校验文件保存在压缩包旁。
    $ChecksumPath = "$ArchivePath.sha256"
    Invoke-WebRequest -UseBasicParsing -Uri "$ReleaseBaseUrl/$AssetName" -OutFile $ArchivePath
    Invoke-WebRequest -UseBasicParsing -Uri "$ReleaseBaseUrl/$AssetName.sha256" -OutFile $ChecksumPath

    # ExpectedHash is the SHA-256 value published by the official release.
    # ExpectedHash 是官方 Release 发布的 SHA-256 值。
    $ExpectedHash = ((Get-Content -Raw -Encoding UTF8 -LiteralPath $ChecksumPath).Trim() -split '\s+')[0].ToLowerInvariant()
    if ($ExpectedHash -notmatch '^[0-9a-f]{64}$') {
        throw "Invalid checksum file downloaded from $ReleaseBaseUrl/$AssetName.sha256"
    }
    # ActualHash is calculated from the downloaded archive before extraction.
    # ActualHash 是解压前根据下载压缩包计算出的哈希值。
    $ActualHash = Get-Sha256Hash -Path $ArchivePath
    if ($ActualHash -ne $ExpectedHash) {
        throw "SHA-256 mismatch for $AssetName. Expected $ExpectedHash, got $ActualHash."
    }

    & tar -xzf $ArchivePath -C $DebugRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to extract $ArchivePath"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $DebugRoot "debug.ps1") -PathType Leaf)) {
        throw "The extracted package does not contain debug.ps1 at its documented package root."
    }
    Set-Content -NoNewline -Encoding UTF8 -LiteralPath (Join-Path $DebugRoot ".installed-version") -Value $ReleaseTag
    Remove-Item -LiteralPath $ArchivePath, $ChecksumPath -Force
    Write-Host "LuaSkills debug tool $ReleaseTag installed at $DebugRoot"
} else {
    Write-Host "LuaSkills debug tool $ReleaseTag is already installed at $DebugRoot"
}

if (-not $SkipRuntimeSetup) {
    # RuntimeManifest is the official marker written by Lua runtime package setup.
    # RuntimeManifest 是 Lua runtime package 初始化写入的官方标记文件。
    $RuntimeManifest = Join-Path $DebugRoot "runtime\resources\luaskills-packages-manifest.json"
    if (-not (Test-Path -LiteralPath $RuntimeManifest -PathType Leaf)) {
        # RuntimeSetupPath is the official package-owned dependency bootstrap script.
        # RuntimeSetupPath 是官方调试包自带的依赖初始化脚本。
        $RuntimeSetupPath = Join-Path $DebugRoot "setup_runtime.ps1"
        & powershell -NoProfile -ExecutionPolicy Bypass -File $RuntimeSetupPath -Target lua -Database none
        if ($LASTEXITCODE -ne 0) {
            throw "LuaSkills debug runtime setup failed with exit code $LASTEXITCODE."
        }
    } else {
        Write-Host "LuaSkills runtime packages are already initialized at $(Join-Path $DebugRoot 'runtime')"
    }
}

if (-not $SkipManagedNodeSetup) {
    Install-ManagedNodeRuntime -DebugRoot $DebugRoot -ReleaseTag $ReleaseTag
}
