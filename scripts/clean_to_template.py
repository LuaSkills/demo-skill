"""
Turn the demo repository into a minimal LuaSkill starting template with one hello tool.
将演示仓库转换为只保留一个 hello 工具的最小 LuaSkill 起始模板。
"""

from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import subprocess
import sys


# DemoBlockBegin marks the first line of a demo-only block in docs, scripts, and workflows.
# DemoBlockBegin 标记文档、脚本与工作流中仅属于演示内容的块的首行。
DEMO_BLOCK_BEGIN = ">>> demo-only"
# DemoBlockEnd marks the last line of a demo-only block; both marker lines are removed with the block.
# DemoBlockEnd 标记仅属于演示内容的块的末行；两条标记行会随块一起删除。
DEMO_BLOCK_END = "<<< demo-only"
# RemovedPaths are demo-only files and directories, relative to the repository root.
# RemovedPaths 是仅属于演示的文件与目录，均相对仓库根目录。
REMOVED_PATHS = (
    "runtime/demo_status.lua",
    "runtime/rg_check.lua",
    "runtime/overflow_demo.lua",
    "runtime/node_runtime_demo.lua",
    "runtime/native_demo.lua",
    "runtime/config_validator.lua",
    "help/demo-status.md",
    "help/rg-dependency.md",
    "help/overflow-demo.md",
    "help/node-runtime.md",
    "help/native-library.md",
    "help/package-config.md",
    "examples/debug/demo-status.args.json",
    "examples/debug/rg-check.args.json",
    "examples/debug/overflow-demo.args.json",
    "examples/debug/node-runtime-demo.args.json",
    "examples/debug/native-demo.args.json",
    "node",
    "overflow_templates",
    "native",
    "resources",
)
# MarkedFiles contain demo-only blocks that are stripped while the surrounding tooling stays.
# MarkedFiles 包含仅属于演示的块；删除这些块时保留周围的工具内容。
MARKED_FILES = (
    "README.md",
    "README.zh-CN.md",
    "scripts/verify_skill.sh",
    "scripts/verify_skill.ps1",
    ".github/workflows/release.yml",
    ".github/workflows/validate.yml",
)
# TemplateSkillManifest is the minimal manifest that keeps only the hello entry.
# TemplateSkillManifest 是只保留 hello 入口的最小清单。
TEMPLATE_SKILL_MANIFEST = """name: LuaSkill Template
version: 0.1.0
enable: true
debug: false
help:
  main:
    description: Main help node for this LuaSkill.
    file: help/help.md
  topics:
    - name: hello
      description: Explain the minimal hello tool.
      file: help/hello.md
entries:
  - name: hello
    description: Return one greeting; replace it with the first real tool.
    lua_entry: runtime/hello.lua
    lua_module: hello
    help: hello
    parameters:
      - name: name
        type: string
        description: Optional name greeted by the tool.
        required: false
"""
# TemplateDependencies declares no dependencies while keeping every protocol group visible.
# TemplateDependencies 不声明任何依赖，同时保留每个协议分组以便查阅。
TEMPLATE_DEPENDENCIES = """tool_dependencies: []
lua_dependencies: []
ffi_dependencies: []
"""
# TemplateMainHelp is the main help node of the cleaned template.
# TemplateMainHelp 是清理后模板的主帮助节点。
TEMPLATE_MAIN_HELP = """# LuaSkill Template

Describe what this LuaSkill does and when an AI should use it.

Available workflows:

- `hello`
  - return one greeting; replace it with the first real tool
"""
# TemplateNotices states that the cleaned template ships no third-party code.
# TemplateNotices 说明清理后的模板不包含第三方代码。
TEMPLATE_NOTICES = """# Third-Party Notices

This skill package currently declares no third-party dependencies and bundles no third-party code.

List every dependency declared in `dependencies.yaml` and every bundled third-party file here, with its license.
"""
# GeneratedFiles are rewritten with fixed template content.
# GeneratedFiles 会被改写为固定的模板内容。
GENERATED_FILES = {
    "skill.yaml": TEMPLATE_SKILL_MANIFEST,
    "dependencies.yaml": TEMPLATE_DEPENDENCIES,
    "help/help.md": TEMPLATE_MAIN_HELP,
    "licenses/THIRD_PARTY_NOTICES.md": TEMPLATE_NOTICES,
}


"""
Return the repository root that also acts as the skill root.
返回同时作为技能根目录的仓库根目录。
"""
def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


"""
Resolve one constant repository-relative path and prove that it stays inside the repository.
解析一个常量仓库相对路径，并证明其位于仓库内部。

Args:
    root: Repository root being cleaned.
    root：正在清理的仓库根目录。
    relative_path: POSIX path relative to root.
    relative_path：相对 root 的 POSIX 路径。

Returns:
    Unresolved path below root, so a symbolic link is handled as the link itself.
    位于 root 下的未解析路径，使符号链接按链接本身处理。
"""
def contained_path(root: Path, relative_path: str) -> Path:
    # Candidate keeps the link itself when the final component is a symbolic link.
    # Candidate 在最后一级是符号链接时保留链接本身。
    candidate = root / relative_path
    # ResolvedParent proves that no intermediate directory escapes the repository.
    # ResolvedParent 证明没有中间目录逃逸出仓库。
    resolved_parent = candidate.parent.resolve()
    if resolved_parent != root.resolve() and root.resolve() not in resolved_parent.parents:
        raise RuntimeError(f"Refusing to touch a path outside the repository: {relative_path}")
    return candidate


"""
Remove every demo-only block from one text document.
从一个文本文档中删除所有仅属于演示的块。

Args:
    text: Document text that may contain marker lines.
    text：可能包含标记行的文档文本。
    label: File label used in diagnostics.
    label：诊断信息中使用的文件标签。

Returns:
    Text without the marked blocks; unbalanced or nested markers raise an error.
    删除标记块后的文本；标记不成对或嵌套时抛出错误。
"""
def strip_demo_blocks(text: str, label: str) -> str:
    # KeptLines preserves original line endings for every line outside a block.
    # KeptLines 为块外每一行保留原始换行符。
    kept_lines: list[str] = []
    # InsideBlock tracks whether the current line belongs to a demo-only block.
    # InsideBlock 记录当前行是否属于仅演示块。
    inside_block = False
    for line_number, line in enumerate(text.splitlines(keepends=True), start=1):
        if DEMO_BLOCK_BEGIN in line:
            if inside_block:
                raise RuntimeError(f"{label}:{line_number}: nested demo-only block")
            inside_block = True
            continue
        if DEMO_BLOCK_END in line:
            if not inside_block:
                raise RuntimeError(f"{label}:{line_number}: demo-only end marker without a begin marker")
            inside_block = False
            continue
        if not inside_block:
            kept_lines.append(line)
    if inside_block:
        raise RuntimeError(f"{label}: demo-only block is not closed")
    return "".join(kept_lines)


"""
Return the Git status of the repository, or None when root is not the top of a Git work tree.
返回仓库的 Git 状态；当 root 不是 Git 工作树顶层时返回 None。

Args:
    root: Repository root being cleaned.
    root：正在清理的仓库根目录。

Returns:
    Porcelain status text, possibly empty, or None for a plain directory copy.
    porcelain 状态文本（可能为空），对普通目录副本返回 None。
"""
def git_worktree_status(root: Path) -> str | None:
    try:
        # TopLevel identifies the work tree that owns root; a nested copy belongs to another repository.
        # TopLevel 标识拥有 root 的工作树；嵌套副本属于其他仓库。
        top_level = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=root,
            check=False,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError:
        return None
    if top_level.returncode != 0 or Path(top_level.stdout.strip()).resolve() != root.resolve():
        return None
    # StatusResult lists tracked and untracked changes that cleaning could overwrite.
    # StatusResult 列出清理可能覆盖的已跟踪与未跟踪变更。
    status_result = subprocess.run(
        ["git", "status", "--porcelain=v1"],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    )
    return status_result.stdout


"""
Compute every removal and rewrite without touching the filesystem.
在不修改文件系统的前提下计算全部删除与改写操作。

Args:
    root: Repository root being cleaned.
    root：正在清理的仓库根目录。

Returns:
    Tuple of existing removal paths and a mapping from rewritten paths to their new text.
    由现存待删除路径以及改写路径到新文本的映射组成的元组。
"""
def plan_changes(root: Path) -> tuple[list[str], dict[str, str]]:
    # Removals are only the demo paths that still exist, which makes a second run a no-op.
    # Removals 只包含仍然存在的演示路径，使第二次运行不做任何改动。
    removals = [
        relative_path
        for relative_path in REMOVED_PATHS
        if contained_path(root, relative_path).exists() or contained_path(root, relative_path).is_symlink()
    ]
    # Rewrites maps each changed file to its complete new content.
    # Rewrites 将每个发生变化的文件映射到其完整新内容。
    rewrites: dict[str, str] = {}
    for relative_path, content in GENERATED_FILES.items():
        # TargetPath is one generated template file.
        # TargetPath 是一个生成的模板文件。
        target_path = contained_path(root, relative_path)
        if not target_path.is_file() or target_path.read_text(encoding="utf-8") != content:
            rewrites[relative_path] = content
    for relative_path in MARKED_FILES:
        # MarkedPath is one tooling file that may contain demo-only blocks.
        # MarkedPath 是一个可能包含仅演示块的工具文件。
        marked_path = contained_path(root, relative_path)
        if not marked_path.is_file():
            continue
        # OriginalText is read as bytes-to-text without newline translation to keep line endings.
        # OriginalText 在不转换换行的情况下读取，以保留原始换行符。
        original_text = marked_path.read_bytes().decode("utf-8")
        # StrippedText is the same file without its demo-only blocks.
        # StrippedText 是删除仅演示块后的同一文件。
        stripped_text = strip_demo_blocks(original_text, relative_path)
        if stripped_text != original_text:
            rewrites[relative_path] = stripped_text
    return removals, rewrites


"""
Apply one computed plan and print every removed or rewritten path.
执行已计算的计划，并输出每个被删除或改写的路径。

Args:
    root: Repository root being cleaned.
    root：正在清理的仓库根目录。
    removals: Existing repository-relative paths to delete.
    removals：需要删除的现存仓库相对路径。
    rewrites: Repository-relative paths mapped to their complete new text.
    rewrites：仓库相对路径到其完整新文本的映射。

Returns:
    None after every change has been written.
    所有变更写入完成后返回空值。
"""
def apply_changes(root: Path, removals: list[str], rewrites: dict[str, str]) -> None:
    for relative_path in removals:
        # TargetPath is deleted as a link, a file, or a whole directory tree.
        # TargetPath 按链接、文件或整个目录树删除。
        target_path = contained_path(root, relative_path)
        if target_path.is_dir() and not target_path.is_symlink():
            shutil.rmtree(target_path)
        else:
            target_path.unlink()
        print(f"Removed: {relative_path}")
    for relative_path, content in rewrites.items():
        # TargetPath is written with LF line endings and UTF-8, matching the repository files.
        # TargetPath 以 LF 换行与 UTF-8 写入，与仓库文件保持一致。
        target_path = contained_path(root, relative_path)
        target_path.parent.mkdir(parents=True, exist_ok=True)
        target_path.write_bytes(content.encode("utf-8"))
        print(f"Rewrote: {relative_path}")


"""
Parse command-line arguments for the template cleaner.
解析模板清理脚本的命令行参数。
"""
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Remove the demo tools and keep a minimal LuaSkill template with one hello tool."
    )
    parser.add_argument("--yes", action="store_true", help="Confirm that the demo files may be deleted and rewritten.")
    parser.add_argument(
        "--force",
        action="store_true",
        help="Run even when the Git working tree has uncommitted or untracked changes.",
    )
    return parser.parse_args()


"""
Run the cleaner and return one process exit code.
执行清理脚本并返回进程退出码。
"""
def main() -> int:
    args = parse_args()
    root = repo_root()
    try:
        removals, rewrites = plan_changes(root)
    except RuntimeError as error:
        print(f"Template cleanup failed: {error}", file=sys.stderr)
        return 1
    if not removals and not rewrites:
        print("The repository is already a minimal template; nothing to change.")
        return 0
    if not args.yes:
        for relative_path in removals:
            print(f"Would remove: {relative_path}")
        for relative_path in rewrites:
            print(f"Would rewrite: {relative_path}")
        print("Re-run with --yes to apply these changes.", file=sys.stderr)
        return 1

    # WorktreeStatus protects uncommitted work from being mixed with the generated template.
    # WorktreeStatus 防止未提交的工作与生成的模板混在一起。
    worktree_status = git_worktree_status(root)
    if worktree_status is None:
        print("No Git work tree is rooted here; skipping the clean working tree check.", file=sys.stderr)
    elif worktree_status.strip() and not args.force:
        print(
            "The Git working tree has changes. Commit or stash them first, or pass --force.",
            file=sys.stderr,
        )
        return 1

    apply_changes(root, removals, rewrites)
    print("Template cleanup finished. Run the validate and verify scripts next.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
