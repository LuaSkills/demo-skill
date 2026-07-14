"""
Build one release zip that expands into the strict LuaSkill top-level directory.
构建一个发布 zip，并在解压后还原严格的 LuaSkill 顶层目录。
"""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import re
import subprocess
from zipfile import ZIP_DEFLATED, ZipFile

import yaml


# PackageRootNames is the exact top-level release-package whitelist.
# PackageRootNames 是正式发布包允许包含的精确顶层白名单。
PACKAGE_ROOT_NAMES = frozenset(
    {
        "skill.yaml",
        "dependencies.yaml",
        "README.md",
        "README.zh-CN.md",
        "LICENSE",
        "runtime",
        "node",
        "python",
        "help",
        "overflow_templates",
        "resources",
        "licenses",
    }
)
# GeneratedDirectoryNames identifies local dependency and cache directories that never ship.
# GeneratedDirectoryNames 标识绝不进入发布包的本地依赖与缓存目录。
GENERATED_DIRECTORY_NAMES = frozenset({"node_modules", ".pnpm-store", "__pycache__"})
# GeneratedFileNames identifies platform metadata files that never ship.
# GeneratedFileNames 标识绝不进入发布包的平台元数据文件。
GENERATED_FILE_NAMES = frozenset({".DS_Store"})


"""
Return the repository root that also acts as the skill root.
返回同时作为技能根目录的仓库根目录。
"""
def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


"""
Load the skill manifest from disk.
从磁盘加载技能清单。
"""
def load_manifest(root: Path) -> dict:
    with (root / "skill.yaml").open("r", encoding="utf-8") as handle:
        payload = yaml.safe_load(handle) or {}
    if not isinstance(payload, dict):
        raise RuntimeError("skill.yaml must contain one YAML object")
    return payload


"""
Return the semantic package version declared by the manifest.
返回清单中声明的语义化包版本。
"""
def manifest_version(manifest: dict) -> str:
    version = manifest.get("version")
    if not isinstance(version, str) or not version.strip():
        raise RuntimeError("skill.yaml must contain a non-empty version")
    return version.strip()


"""
Resolve the effective package version and enforce it against CLI or GitHub tag inputs.
解析最终打包版本，并强制要求其与命令行或 GitHub 标签输入保持一致。
"""
def resolve_version(manifest: dict, cli_version: str | None) -> str:
    declared_version = manifest_version(manifest)

    if cli_version and cli_version.strip() != declared_version:
        raise RuntimeError(
            f"--version must match skill.yaml version {declared_version}, got {cli_version.strip()}"
        )

    # RefName is the current GitHub branch or tag short name.
    # RefName 是当前 GitHub 分支或标签的短名称。
    ref_name = os.environ.get("GITHUB_REF_NAME", "").strip()
    # RefType distinguishes branch validation builds from tag release builds.
    # RefType 用于区分分支验证构建与标签发布构建。
    ref_type = os.environ.get("GITHUB_REF_TYPE", "").strip()
    # IsTagRef preserves explicit local tag simulations when only GITHUB_REF_NAME is set.
    # IsTagRef 在仅设置 GITHUB_REF_NAME 时保留显式的本地标签模拟能力。
    is_tag_ref = ref_type == "tag" or (not ref_type and ref_name.startswith("v"))
    if ref_name and is_tag_ref:
        expected_tag = f"v{declared_version}"
        if ref_name != expected_tag:
            raise RuntimeError(
                f"GITHUB_REF_NAME must match {expected_tag}, got {ref_name}"
            )

    return declared_version


"""
Resolve the GitHub repository slug from Actions or the configured origin remote.
从 GitHub Actions 或已配置的 origin 远端解析 GitHub 仓库标识。
"""
def resolve_github_repository(root: Path) -> str:
    # ActionsRepository is the authoritative repository slug provided by GitHub Actions.
    # ActionsRepository 是 GitHub Actions 提供的权威仓库标识。
    actions_repository = os.environ.get("GITHUB_REPOSITORY", "").strip()
    if actions_repository:
        if not re.fullmatch(r"[^/\s]+/[^/\s]+", actions_repository):
            raise RuntimeError(f"GITHUB_REPOSITORY is invalid: {actions_repository}")
        return actions_repository

    # RemoteResult reads the only configured origin URL used for local fork packaging.
    # RemoteResult 读取本地 Fork 打包时唯一使用的 origin URL。
    remote_result = subprocess.run(
        ["git", "remote", "get-url", "origin"],
        cwd=root,
        check=False,
        capture_output=True,
        text=True,
    )
    if remote_result.returncode != 0:
        raise RuntimeError("Unable to read git origin; pass --base-url explicitly")

    # RemoteUrl is the exact origin URL returned by Git.
    # RemoteUrl 是 Git 返回的精确 origin URL。
    remote_url = remote_result.stdout.strip()
    # GitHubPrefixes are the documented HTTPS and SSH URL forms accepted here.
    # GitHubPrefixes 是此处明确接受的 GitHub HTTPS 与 SSH URL 形式。
    github_prefixes = (
        "https://github.com/",
        "git@github.com:",
        "ssh://git@github.com/",
    )
    # Prefix is one explicitly supported GitHub transport prefix.
    # Prefix 是一个明确受支持的 GitHub 传输前缀。
    for prefix in github_prefixes:
        if not remote_url.startswith(prefix):
            continue
        # RepositorySlug removes only the matched GitHub prefix and optional .git suffix.
        # RepositorySlug 仅移除已匹配的 GitHub 前缀与可选 .git 后缀。
        repository_slug = remote_url[len(prefix) :].rstrip("/")
        if repository_slug.endswith(".git"):
            repository_slug = repository_slug[:-4]
        if re.fullmatch(r"[^/\s]+/[^/\s]+", repository_slug):
            return repository_slug
        break

    raise RuntimeError(
        f"origin is not a supported GitHub repository URL: {remote_url}; pass --base-url explicitly"
    )


"""
Return a normalized release asset base URL without a trailing slash.
返回去除尾部斜杠后的规范化发布资产基础 URL。
"""
def normalize_base_url(root: Path, base_url: str | None, version: str) -> str:
    if base_url is not None and base_url.strip():
        return base_url.strip().rstrip("/")
    # RepositorySlug binds generated metadata to the current fork instead of the template origin.
    # RepositorySlug 将生成的元数据绑定到当前 Fork，而不是模板仓库。
    repository_slug = resolve_github_repository(root)
    return f"https://github.com/{repository_slug}/releases/download/v{version}"


"""
Return the list of repository-relative paths included in the release package.
返回发布包中应包含的仓库相对路径列表。
"""
def collect_package_paths(root: Path) -> list[Path]:
    # ResolvedRoot anchors every accepted file to the physical repository root.
    # ResolvedRoot 将每个允许文件约束在仓库物理根目录内。
    resolved_root = root.resolve()
    # Collected contains only regular, non-generated, non-symlink release files.
    # Collected 仅包含普通、非生成、非符号链接的发布文件。
    collected: list[Path] = []
    for package_root_name in sorted(PACKAGE_ROOT_NAMES):
        # PackageRoot is one explicit top-level whitelist member.
        # PackageRoot 是一个显式的顶层白名单成员。
        package_root = root / package_root_name
        if not package_root.exists():
            continue
        if package_root.is_symlink():
            raise RuntimeError(f"Release package root cannot be a symbolic link: {package_root_name}")
        # Candidates handles one root file or every descendant of one root directory.
        # Candidates 处理单个根文件或根目录下的每个后代路径。
        candidates = [package_root] if package_root.is_file() else package_root.rglob("*")
        for candidate in candidates:
            # RelativePath is used for generated-path filtering and deterministic sorting.
            # RelativePath 用于生成路径过滤与确定性排序。
            relative_path = candidate.relative_to(root)
            if any(part in GENERATED_DIRECTORY_NAMES for part in relative_path.parts):
                continue
            if candidate.name in GENERATED_FILE_NAMES or candidate.suffix == ".pyc":
                continue
            if candidate.is_symlink():
                raise RuntimeError(f"Release package cannot contain a symbolic link: {relative_path}")
            if not candidate.is_file():
                continue
            # ResolvedCandidate proves that no filesystem indirection escaped the repository.
            # ResolvedCandidate 证明不存在逃逸仓库的文件系统间接路径。
            resolved_candidate = candidate.resolve()
            if resolved_root not in resolved_candidate.parents:
                raise RuntimeError(f"Release package path escapes the repository: {relative_path}")
            collected.append(candidate)
    return sorted(collected, key=lambda item: item.relative_to(root).as_posix())


"""
Verify that one generated zip exactly matches the formal package whitelist.
校验生成的 zip 是否与正式包白名单完全一致。
"""
def verify_package_archive(root: Path, package_path: Path) -> None:
    # SkillName is the physical directory name that owns every archive member.
    # SkillName 是所有压缩包成员所属的物理目录名。
    skill_name = root.name
    # ExpectedPaths is the authoritative archive member set derived from the whitelist.
    # ExpectedPaths 是根据白名单派生的权威压缩包成员集合。
    expected_paths = {
        (Path(skill_name) / source_path.relative_to(root)).as_posix()
        for source_path in collect_package_paths(root)
    }
    with ZipFile(package_path, "r") as archive:
        # ArchiveNames preserves duplicates so malformed archives cannot pass set comparison.
        # ArchiveNames 保留重复项，避免异常压缩包通过集合比较。
        archive_names = archive.namelist()
    if len(archive_names) != len(set(archive_names)):
        raise RuntimeError(f"Release archive contains duplicate members: {package_path}")
    # ActualPaths is the exact generated archive member set.
    # ActualPaths 是实际生成的精确压缩包成员集合。
    actual_paths = set(archive_names)
    if actual_paths != expected_paths:
        # MissingPaths records whitelisted files omitted from the archive.
        # MissingPaths 记录被压缩包遗漏的白名单文件。
        missing_paths = sorted(expected_paths - actual_paths)
        # UnexpectedPaths records every non-whitelisted archive member.
        # UnexpectedPaths 记录所有不在白名单内的压缩包成员。
        unexpected_paths = sorted(actual_paths - expected_paths)
        raise RuntimeError(
            f"Release archive layout mismatch; missing={missing_paths}, unexpected={unexpected_paths}"
        )


"""
Build the release zip and checksum file under the selected output directory.
在选定输出目录下构建发布 zip 与校验文件。
"""
def build_package(root: Path, out_dir: Path, version: str) -> tuple[Path, Path]:
    manifest = load_manifest(root)
    skill_name = root.name
    display_name = manifest.get("name", skill_name)
    if not isinstance(display_name, str) or not display_name:
        raise RuntimeError("skill.yaml must contain a non-empty name")

    out_dir.mkdir(parents=True, exist_ok=True)
    package_name = f"{skill_name}-v{version}-skill.zip"
    checksum_name = f"{skill_name}-v{version}-checksums.txt"
    package_path = out_dir / package_name
    checksum_path = out_dir / checksum_name

    with ZipFile(package_path, "w", compression=ZIP_DEFLATED) as archive:
        for file_path in collect_package_paths(root):
            relative_path = file_path.relative_to(root)
            archive_path = Path(skill_name) / relative_path
            archive.write(file_path, archive_path.as_posix())

    verify_package_archive(root, package_path)
    digest = hashlib.sha256(package_path.read_bytes()).hexdigest()
    checksum_path.write_text(f"{digest}  {package_name}\n", encoding="utf-8")
    return package_path, checksum_path


"""
Build one source metadata YAML file for URL-based installation and update tests.
构建一个用于 URL 安装与更新测试的来源描述 YAML 文件。
"""
def build_source_metadata(
    root: Path,
    out_dir: Path,
    version: str,
    base_url: str | None,
    package_path: Path,
    checksum_path: Path,
) -> Path:
    manifest = load_manifest(root)
    skill_name = root.name
    display_name = manifest.get("name", skill_name)
    if not isinstance(display_name, str) or not display_name:
        raise RuntimeError("skill.yaml must contain a non-empty name")

    source_name = f"{skill_name}-v{version}-source.yaml"
    source_path = out_dir / source_name
    normalized_base_url = normalize_base_url(root, base_url, version)
    package_name = package_path.name
    checksum_name = checksum_path.name
    checksum_sha256 = checksum_path.read_text(encoding="utf-8").split()[0]

    payload = {
        "skill_id": skill_name,
        "name": display_name,
        "version": version,
        "source": {
            "kind": "url",
            "locator": f"{normalized_base_url}/{source_name}",
        },
        "package": {
            "url": f"{normalized_base_url}/{package_name}",
            "sha256": checksum_sha256,
            "filename": package_name,
        },
        "checksums": {
            "url": f"{normalized_base_url}/{checksum_name}",
            "filename": checksum_name,
        },
        "release": {
            "tag": f"v{version}",
        },
    }
    source_path.write_text(
        yaml.safe_dump(payload, sort_keys=False, allow_unicode=False),
        encoding="utf-8",
    )
    return source_path


"""
Parse command-line arguments for the package builder.
解析打包脚本使用的命令行参数。
"""
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Package one LuaSkill release zip.")
    parser.add_argument("--out-dir", default="dist", help="Output directory for release assets.")
    parser.add_argument(
        "--base-url",
        default=None,
        help="Optional base URL used to build generated source metadata; defaults to the current GitHub Actions repository or git origin.",
    )
    parser.add_argument(
        "--emit-source-yaml",
        action="store_true",
        help="Generate one source metadata YAML file for non-GitHub distribution channels.",
    )
    parser.add_argument("--version", default=None, help="Semantic version without the leading v.")
    return parser.parse_args()


"""
Run the package build and print the generated artifact paths.
执行打包流程并输出生成的产物路径。
"""
def main() -> int:
    args = parse_args()
    root = repo_root()
    out_dir = (root / args.out_dir).resolve()
    manifest = load_manifest(root)
    version = resolve_version(manifest, args.version)
    package_path, checksum_path = build_package(root, out_dir, version)
    print(f"Package created: {package_path}")
    print(f"Checksums created: {checksum_path}")
    if args.emit_source_yaml:
        source_path = build_source_metadata(
            root,
            out_dir,
            version,
            args.base_url,
            package_path,
            checksum_path,
        )
        print(f"Source metadata created: {source_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
