#!/usr/bin/env bash
set -euo pipefail

# Resolve the repository root and print its absolute path.
# 解析仓库根目录并输出其绝对路径。
resolve_project_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

# Normalize and validate a LuaSkills semantic release tag.
# 标准化并校验 LuaSkills 语义化发布标签。
resolve_release_tag() {
  # RawVersion is the explicit override or repository-pinned version.
  # RawVersion 是显式覆盖值或仓库固定版本。
  local raw_version="${1:-}"
  if [ -z "$raw_version" ]; then
    raw_version="$(tr -d '[:space:]' < "$PROJECT_ROOT/.luaskills-version")"
  fi
  if [[ "$raw_version" != v* ]]; then
    raw_version="v$raw_version"
  fi
  if [[ ! "$raw_version" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)([-+][0-9A-Za-z.-]+)?$ ]]; then
    echo "Invalid LuaSkills release tag: $raw_version" >&2
    return 1
  fi
  printf '%s\n' "$raw_version"
}

# Map the current operating system and CPU to an official release platform key.
# 将当前操作系统与 CPU 映射到官方发布平台标识。
resolve_platform_key() {
  # OperatingSystem is the normalized kernel name reported by uname.
  # OperatingSystem 是 uname 返回的标准化内核名称。
  local operating_system
  operating_system="$(uname -s)"
  # Architecture is the normalized machine architecture reported by uname.
  # Architecture 是 uname 返回的标准化机器架构。
  local architecture
  architecture="$(uname -m)"

  case "$operating_system" in
    Linux) operating_system="linux" ;;
    Darwin) operating_system="macos" ;;
    *) echo "Unsupported operating system for the shell debug package: $operating_system" >&2; return 1 ;;
  esac
  case "$architecture" in
    x86_64|amd64) architecture="x64" ;;
    arm64|aarch64) architecture="arm64" ;;
    *) echo "Unsupported architecture for the LuaSkills debug package: $architecture" >&2; return 1 ;;
  esac
  printf '%s-%s\n' "$operating_system" "$architecture"
}

# Calculate a lowercase SHA-256 digest for one file.
# 为单个文件计算小写 SHA-256 摘要。
calculate_sha256() {
  # FilePath is the archive whose digest must be calculated.
  # FilePath 是需要计算摘要的压缩包路径。
  local file_path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file_path" | awk '{print tolower($1)}'
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file_path" | awk '{print tolower($1)}'
    return 0
  fi
  echo "Neither sha256sum nor shasum is available." >&2
  return 1
}

# Remove only the verified repository-local debug workspace.
# 仅删除已校验的仓库本地调试工作区。
remove_debug_workspace() {
  if [ "$DEBUG_ROOT" != "$PROJECT_ROOT/.luaskills-debug" ]; then
    echo "Refusing to remove an unexpected debug path: $DEBUG_ROOT" >&2
    return 1
  fi
  if [ -e "$DEBUG_ROOT" ]; then
    rm -rf -- "$DEBUG_ROOT"
  fi
}

# ProjectRoot anchors every generated or downloaded path inside this repository.
# ProjectRoot 将所有生成与下载路径限定在当前仓库内。
PROJECT_ROOT="$(resolve_project_root)"
# DebugRoot is the Git-ignored standalone LuaSkills debug workspace.
# DebugRoot 是被 Git 忽略的独立 LuaSkills 调试工作区。
DEBUG_ROOT="$PROJECT_ROOT/.luaskills-debug"
# VersionOverride stores an optional caller-selected LuaSkills release tag.
# VersionOverride 保存调用方可选指定的 LuaSkills 发布标签。
VERSION_OVERRIDE=""
# SkipRuntimeSetup controls whether Lua runtime packages are downloaded.
# SkipRuntimeSetup 控制是否下载 Lua runtime packages。
SKIP_RUNTIME_SETUP="false"
# Force controls whether an existing matching workspace is rebuilt.
# Force 控制是否重建已有的匹配工作区。
FORCE="false"
# SkipManagedNodeSetup controls whether managed Node.js and pnpm are downloaded.
# SkipManagedNodeSetup 控制是否下载受管 Node.js 与 pnpm。
SKIP_MANAGED_NODE_SETUP="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      VERSION_OVERRIDE="${2:?--version requires a value}"
      shift 2
      ;;
    --skip-runtime-setup)
      SKIP_RUNTIME_SETUP="true"
      shift
      ;;
    --force)
      FORCE="true"
      shift
      ;;
    --skip-managed-node-setup)
      SKIP_MANAGED_NODE_SETUP="true"
      shift
      ;;
    *)
      echo "Unknown setup argument: $1" >&2
      exit 2
      ;;
  esac
done

# ReleaseTag is the verified LuaSkills release used by this workspace.
# ReleaseTag 是当前工作区使用的已校验 LuaSkills 发布版本。
RELEASE_TAG="$(resolve_release_tag "$VERSION_OVERRIDE")"
# PlatformKey selects the exact official GitHub release asset.
# PlatformKey 用于选择精确的官方 GitHub Release 资产。
PLATFORM_KEY="$(resolve_platform_key)"
# AssetName is the official standalone debug tool archive name.
# AssetName 是官方独立调试器压缩包名称。
ASSET_NAME="luaskills-debug-tool-$PLATFORM_KEY.tar.gz"
# ReleaseBaseUrl is the immutable GitHub release download directory.
# ReleaseBaseUrl 是不可变的 GitHub Release 下载目录。
RELEASE_BASE_URL="https://github.com/LuaSkills/luaskills/releases/download/$RELEASE_TAG"
# InstalledVersion records the currently extracted release tag when present.
# InstalledVersion 记录当前已解压的发布标签（若存在）。
INSTALLED_VERSION=""
if [ -f "$DEBUG_ROOT/.installed-version" ]; then
  INSTALLED_VERSION="$(tr -d '[:space:]' < "$DEBUG_ROOT/.installed-version")"
fi

if [ "$FORCE" = "true" ] || [ "$INSTALLED_VERSION" != "$RELEASE_TAG" ] || [ ! -x "$DEBUG_ROOT/debug.sh" ]; then
  remove_debug_workspace
  mkdir -p "$DEBUG_ROOT"

  # ArchivePath stores the official archive inside the ignored workspace.
  # ArchivePath 将官方压缩包保存在被忽略的工作区内。
  ARCHIVE_PATH="$DEBUG_ROOT/$ASSET_NAME"
  # ChecksumPath stores the official checksum sidecar next to the archive.
  # ChecksumPath 将官方校验文件保存在压缩包旁。
  CHECKSUM_PATH="$ARCHIVE_PATH.sha256"
  curl --fail --location --silent --show-error "$RELEASE_BASE_URL/$ASSET_NAME" --output "$ARCHIVE_PATH"
  curl --fail --location --silent --show-error "$RELEASE_BASE_URL/$ASSET_NAME.sha256" --output "$CHECKSUM_PATH"

  # ExpectedHash is the SHA-256 value published by the official release.
  # ExpectedHash 是官方 Release 发布的 SHA-256 值。
  EXPECTED_HASH="$(awk 'NR == 1 {print tolower($1)}' "$CHECKSUM_PATH")"
  if [[ ! "$EXPECTED_HASH" =~ ^[0-9a-f]{64}$ ]]; then
    echo "Invalid checksum file downloaded from $RELEASE_BASE_URL/$ASSET_NAME.sha256" >&2
    exit 1
  fi
  # ActualHash is calculated from the downloaded archive before extraction.
  # ActualHash 是解压前根据下载压缩包计算出的哈希值。
  ACTUAL_HASH="$(calculate_sha256 "$ARCHIVE_PATH")"
  if [ "$ACTUAL_HASH" != "$EXPECTED_HASH" ]; then
    echo "SHA-256 mismatch for $ASSET_NAME. Expected $EXPECTED_HASH, got $ACTUAL_HASH." >&2
    exit 1
  fi

  tar -xzf "$ARCHIVE_PATH" -C "$DEBUG_ROOT"
  if [ ! -f "$DEBUG_ROOT/debug.sh" ]; then
    echo "The extracted package does not contain debug.sh at its documented package root." >&2
    exit 1
  fi
  chmod +x "$DEBUG_ROOT/debug.sh" "$DEBUG_ROOT/setup_runtime.sh" "$DEBUG_ROOT/bin/luaskills-debug"
  printf '%s\n' "$RELEASE_TAG" > "$DEBUG_ROOT/.installed-version"
  rm -f -- "$ARCHIVE_PATH" "$CHECKSUM_PATH"
  echo "LuaSkills debug tool $RELEASE_TAG installed at $DEBUG_ROOT"
else
  echo "LuaSkills debug tool $RELEASE_TAG is already installed at $DEBUG_ROOT"
fi

if [ "$SKIP_RUNTIME_SETUP" != "true" ]; then
  # LuaPackagesRoot is the official runtime package directory created by setup_runtime.
  # LuaPackagesRoot 是 setup_runtime 创建的官方运行时包目录。
  LUA_PACKAGES_ROOT="$DEBUG_ROOT/runtime/lua_packages"
  if [ ! -d "$LUA_PACKAGES_ROOT" ]; then
    "$DEBUG_ROOT/setup_runtime.sh" lua none
  else
    echo "LuaSkills runtime packages are already initialized at $DEBUG_ROOT/runtime"
  fi
fi

if [ "$SKIP_MANAGED_NODE_SETUP" != "true" ]; then
  # NodeVersion is the exact managed Node.js version declared by dependencies.yaml.
  # NodeVersion 是 dependencies.yaml 声明的精确受管 Node.js 版本。
  NODE_VERSION="24.18.0"
  # PnpmVersion is the exact managed package-manager version declared by dependencies.yaml.
  # PnpmVersion 是 dependencies.yaml 声明的精确受管包管理器版本。
  PNPM_VERSION="11.11.0"
  # VerifiedReleaseTag identifies the release whose fetcher digest is pinned below.
  # VerifiedReleaseTag 标识下方固定拉取器摘要对应的发布版本。
  VERIFIED_RELEASE_TAG="v0.5.2"
  # ExpectedFetcherHash is the SHA-256 digest of the v0.5.2 shell fetcher.
  # ExpectedFetcherHash 是 v0.5.2 Shell 拉取脚本的 SHA-256 摘要。
  EXPECTED_FETCHER_HASH="613f58d6c771eb677651c9fa59389fde2c62d2cc9748145a0e05d082b7b3e053"
  if [ "$RELEASE_TAG" != "$VERIFIED_RELEASE_TAG" ]; then
    echo "Managed Node.js fetcher checksum is not registered for $RELEASE_TAG. Update the pinned checksum or use --skip-managed-node-setup." >&2
    exit 1
  fi

  # NodeManifest is the official installation marker for the pinned Node.js distribution.
  # NodeManifest 是固定 Node.js 发行版的官方安装标记。
  NODE_MANIFEST="$DEBUG_ROOT/runtime/dependencies/runtimes/node/node-$NODE_VERSION-$PLATFORM_KEY/runtime-manifest.json"
  # PnpmManifest is the official installation marker for the pinned pnpm distribution.
  # PnpmManifest 是固定 pnpm 发行版的官方安装标记。
  PNPM_MANIFEST="$DEBUG_ROOT/runtime/dependencies/runtimes/node/pnpm-$PNPM_VERSION/runtime-manifest.json"
  if [ ! -f "$NODE_MANIFEST" ] || [ ! -f "$PNPM_MANIFEST" ]; then
    # FetcherDirectory is the package-compatible location expected by the official script.
    # FetcherDirectory 是官方脚本期望的包兼容位置。
    FETCHER_DIRECTORY="$DEBUG_ROOT/scripts/deps"
    mkdir -p "$FETCHER_DIRECTORY"
    # FetcherPath is the verified script executed only after digest validation.
    # FetcherPath 是仅在摘要校验后执行的脚本路径。
    FETCHER_PATH="$FETCHER_DIRECTORY/fetch_managed_runtimes.sh"
    # FetcherDownloadPath isolates incomplete downloads from executable script paths.
    # FetcherDownloadPath 将未完成下载与可执行脚本路径隔离。
    FETCHER_DOWNLOAD_PATH="$FETCHER_PATH.download"
    # FetcherUrl is the immutable tag-bound official source URL.
    # FetcherUrl 是绑定不可变标签的官方源码地址。
    FETCHER_URL="https://raw.githubusercontent.com/LuaSkills/luaskills/$RELEASE_TAG/scripts/deps/fetch_managed_runtimes.sh"
    curl --fail --location --silent --show-error "$FETCHER_URL" --output "$FETCHER_DOWNLOAD_PATH"
    # ActualFetcherHash verifies the exact downloaded script bytes before execution.
    # ActualFetcherHash 在执行前校验下载脚本的精确字节。
    ACTUAL_FETCHER_HASH="$(calculate_sha256 "$FETCHER_DOWNLOAD_PATH")"
    if [ "$ACTUAL_FETCHER_HASH" != "$EXPECTED_FETCHER_HASH" ]; then
      echo "SHA-256 mismatch for managed runtime fetcher. Expected $EXPECTED_FETCHER_HASH, got $ACTUAL_FETCHER_HASH." >&2
      exit 1
    fi
    mv -f -- "$FETCHER_DOWNLOAD_PATH" "$FETCHER_PATH"
    chmod +x "$FETCHER_PATH"
    RUNTIME_ROOT="$DEBUG_ROOT/runtime" NODE_VERSION="$NODE_VERSION" PNPM_VERSION="$PNPM_VERSION" bash "$FETCHER_PATH" node
    if [ ! -f "$NODE_MANIFEST" ] || [ ! -f "$PNPM_MANIFEST" ]; then
      echo "Managed Node.js setup completed without the documented runtime manifests." >&2
      exit 1
    fi
  else
    echo "Managed Node.js $NODE_VERSION and pnpm $PNPM_VERSION are already initialized."
  fi
fi
