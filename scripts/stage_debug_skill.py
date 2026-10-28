"""
Stage only release-package files for safe LuaSkills debugger synchronization.
仅暂存发布包文件，供 LuaSkills 调试器安全同步。
"""

from __future__ import annotations

from pathlib import Path
import shutil

from package_skill import collect_package_paths, repo_root


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
    print(stage_root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
