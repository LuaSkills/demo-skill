"""
Resolve and validate the only Git release tag allowed by the skill manifest.
解析并校验 skill 清单唯一允许的 Git 发布标签。
"""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

from scripts.package_skill import load_manifest, manifest_version, repo_root
from scripts.validate_skill import is_valid_semver


"""
Normalize one requested version and reject tags outside strict semantic-version syntax.
规范化一个请求版本，并拒绝不符合严格语义化版本语法的标签。

Args:
    requested_version: User input with an optional single leading letter v.
    requested_version：用户输入，可带一个前导字母 v。

Returns:
    Semantic version without a leading v.
    不带前导 v 的语义化版本。
"""
def normalize_requested_version(requested_version: str) -> str:
    # NormalizedInput removes surrounding whitespace without changing version content.
    # NormalizedInput 移除首尾空白，但不改变版本内容。
    normalized_input = requested_version.strip()
    # VersionValue removes exactly one supported tag prefix.
    # VersionValue 仅移除一个受支持的标签前缀。
    version_value = normalized_input[1:] if normalized_input.startswith("v") else normalized_input
    if not is_valid_semver(version_value):
        raise RuntimeError(f"Release version must be one exact semantic version: {requested_version}")
    return version_value


"""
Return the exact manifest-matching Git tag for one requested release version.
返回与清单精确匹配的请求发布版本 Git 标签。

Args:
    root: Repository root containing skill.yaml.
    root：包含 skill.yaml 的仓库根目录。
    requested_version: User-supplied semantic version or v-prefixed tag.
    requested_version：用户提供的语义化版本或带 v 前缀标签。

Returns:
    Exact v-prefixed tag allowed for the current manifest.
    当前清单允许的精确 v 前缀标签。
"""
def resolve_release_tag(root: Path, requested_version: str) -> str:
    # RequestedVersion is normalized before comparison to prevent ambiguous tag forms.
    # RequestedVersion 在比较前完成规范化，避免含糊的标签形式。
    requested_value = normalize_requested_version(requested_version)
    # DeclaredVersion is the single release version source from skill.yaml.
    # DeclaredVersion 是来自 skill.yaml 的唯一发布版本来源。
    declared_version = manifest_version(load_manifest(root))
    if not is_valid_semver(declared_version):
        raise RuntimeError(f"skill.yaml version is not a valid semantic version: {declared_version}")
    if requested_value != declared_version:
        raise RuntimeError(
            f"Requested release version {requested_value} does not match skill.yaml version {declared_version}"
        )
    return f"v{declared_version}"


"""
Parse command-line arguments for release-tag validation.
解析发布标签校验使用的命令行参数。

Returns:
    Parsed command-line namespace containing the requested version.
    包含请求版本的已解析命令行命名空间。
"""
def parse_args() -> argparse.Namespace:
    # Parser defines the single explicit version argument accepted by release scripts.
    # Parser 定义发布脚本接受的唯一显式版本参数。
    parser = argparse.ArgumentParser(description="Validate one LuaSkill release version.")
    parser.add_argument("version", help="Semantic version with an optional leading v.")
    return parser.parse_args()


"""
Validate the requested version and print the exact allowed Git tag.
校验请求版本并输出唯一允许的 Git 标签。

Returns:
    Zero on success or one after a concise validation diagnostic.
    成功时返回零；输出简洁校验诊断后返回一。
"""
def main() -> int:
    # Arguments contains the user-supplied release version.
    # Arguments 包含用户提供的发布版本。
    arguments = parse_args()
    try:
        # ReleaseTag is the only value safe to pass to git tag and git push.
        # ReleaseTag 是唯一可安全传给 git tag 与 git push 的值。
        release_tag = resolve_release_tag(repo_root(), arguments.version)
    except RuntimeError as error:
        print(f"Release validation failed: {error}", file=sys.stderr)
        return 1
    print(release_tag)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
