"""
Stage only release-package files for safe LuaSkills debugger synchronization.
仅暂存发布包文件，供 LuaSkills 调试器安全同步。
"""

from __future__ import annotations

from pathlib import Path
import shutil
import sys

import yaml

from build_native import host_platform_key
from package_skill import DEPENDENCY_GROUP_NAMES, collect_package_paths, repo_root


"""
Resolve the only allowed debugger source-staging directory.
解析唯一允许使用的调试器源暂存目录。

Args:
    root: Repository root that also acts as the source skill root.
    root：同时作为源 skill 根目录的仓库根目录。

Returns:
    Absolute staging path whose final directory name is the skill id.
    最终目录名等于 skill id 的绝对暂存路径。
"""
def resolve_stage_root(root: Path) -> Path:
    # DebugRoot is the repository-local ignored debugger workspace.
    # DebugRoot 是仓库本地被忽略的调试器工作区。
    debug_root = (root / ".luaskills-debug").resolve()
    # SourceRoot separates immutable source staging from the debugger runtime root.
    # SourceRoot 将不可变源暂存区与调试器 runtime root 分离。
    source_root = (debug_root / "source").resolve()
    # StageRoot keeps the physical directory name that defines the effective skill id.
    # StageRoot 保留用于定义最终 skill id 的物理目录名。
    stage_root = (source_root / root.name).resolve()
    if stage_root.parent != source_root:
        raise RuntimeError(f"Unsafe debug staging path: {stage_root}")
    return stage_root


"""
Rebuild one clean debugger source directory from the release-package whitelist.
根据发布包白名单重建一个干净的调试器源目录。

Args:
    root: Repository root that contains the source LuaSkill.
    root：包含源 LuaSkill 的仓库根目录。

Returns:
    Absolute staged skill directory passed to luaskills-debug.
    传给 luaskills-debug 的绝对 skill 暂存目录。
"""
def stage_skill(root: Path) -> Path:
    # StageRoot is the verified recursive replacement target under .luaskills-debug/source.
    # StageRoot 是 .luaskills-debug/source 下已校验的递归替换目标。
    stage_root = resolve_stage_root(root)
    if stage_root.exists():
        shutil.rmtree(stage_root)
    stage_root.mkdir(parents=True, exist_ok=True)

    # SourcePath iterates over exactly the same whitelist used by release packaging.
    # SourcePath 严格遍历与发布打包相同的白名单。
    for source_path in collect_package_paths(root):
        # RelativePath preserves the formal package layout below the skill directory.
        # RelativePath 保留 skill 目录下的正式包结构。
        relative_path = source_path.relative_to(root)
        # TargetPath is the exact staged counterpart of one whitelisted source file.
        # TargetPath 是单个白名单源文件对应的精确暂存目标。
        target_path = stage_root / relative_path
        target_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_path, target_path)
    return stage_root


"""
Drop optional bundled dependencies whose host payload is absent from the staged copy.
从暂存副本中移除宿主载荷缺失的可选内置依赖。

LuaSkills 0.7.1 refuses to load a skill whose bundled payload is missing or whose current platform has no package
entry, even when the dependency declares required: false. Release packages always carry every payload, so only the
local debug stage needs this step, which lets a machine without a C compiler debug the remaining tools.
LuaSkills 0.7.1 在内置载荷缺失或当前平台没有包条目时会拒绝加载整个 skill，即使依赖声明了 required: false。
正式发布包总会携带全部载荷，因此只有本地调试暂存需要此步骤，使没有 C 编译器的机器仍可调试其余工具。

Args:
    stage_root: Staged skill directory whose dependencies.yaml may be rewritten.
    stage_root：其 dependencies.yaml 可能被改写的暂存 skill 目录。
    platform_key: LuaSkills platform key of the debugging host.
    platform_key：调试主机的 LuaSkills 平台键。

Returns:
    Names of the dependencies removed from the staged manifest.
    从暂存清单中移除的依赖名称。
"""
def prune_unbuilt_optional_bundles(stage_root: Path, platform_key: str) -> list[str]:
    # ManifestPath is the staged copy; the repository manifest is never modified.
    # ManifestPath 是暂存副本；仓库中的清单绝不会被修改。
    manifest_path = stage_root / "dependencies.yaml"
    if not manifest_path.is_file():
        return []
    with manifest_path.open("r", encoding="utf-8") as handle:
        manifest = yaml.safe_load(handle) or {}

    # PrunedNames records every dependency omitted from the debug stage.
    # PrunedNames 记录被调试暂存区省略的每个依赖。
    pruned_names: list[str] = []
    for group_name in DEPENDENCY_GROUP_NAMES:
        # KeptDependencies preserves declaration order for every dependency that stays.
        # KeptDependencies 为保留的依赖维持声明顺序。
        kept_dependencies = []
        for dependency in manifest.get(group_name) or []:
            # Source and Required decide whether the entry is an optional bundled payload.
            # Source 与 Required 决定该条目是否为可选内置载荷。
            source = dependency.get("source") or {}
            is_optional_bundle = source.get("type") == "bundled" and dependency.get("required") is False
            # Package is the declaration for the debugging host, absent for undeclared platforms.
            # Package 是调试主机对应的声明，未声明的平台为空。
            package = (dependency.get("packages") or {}).get(platform_key)
            # PayloadPath is the staged file LuaSkills would install for this host.
            # PayloadPath 是 LuaSkills 将为该主机安装的暂存文件。
            payload_path = package.get("path") if isinstance(package, dict) else None
            if is_optional_bundle and (not payload_path or not (stage_root / payload_path).is_file()):
                pruned_names.append(str(dependency.get("name")))
                # Reason tells the developer whether building can fix the omission on this host.
                # Reason 告诉开发者在当前主机上构建能否解决该省略。
                reason = (
                    f"{payload_path} has not been built; run python scripts/build_native.py to include it"
                    if payload_path
                    else f"no {platform_key} package is declared"
                )
                print(
                    f"Debug stage omits optional bundled dependency '{dependency.get('name')}': {reason}.",
                    file=sys.stderr,
                )
                continue
            kept_dependencies.append(dependency)
        if group_name in manifest:
            manifest[group_name] = kept_dependencies

    if pruned_names:
        manifest_path.write_text(
            yaml.safe_dump(manifest, sort_keys=False, allow_unicode=False),
            encoding="utf-8",
        )
    return pruned_names


"""
Stage the current skill and print the debugger-ready absolute path.
暂存当前 skill，并输出调试器可用的绝对路径。

Returns:
    Zero process exit code after successful staging.
    暂存成功后的零进程退出码。
"""
def main() -> int:
    # Root is the source repository resolved by the shared package builder.
    # Root 是由共享打包器解析的源仓库。
    root = repo_root()
    # StageRoot is rebuilt for every debugger invocation to prevent stale files.
    # StageRoot 会在每次调试器调用前重建，避免残留旧文件。
    stage_root = stage_skill(root)
    prune_unbuilt_optional_bundles(stage_root, host_platform_key())
    print(stage_root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
