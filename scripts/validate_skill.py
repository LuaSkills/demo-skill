"""
Validate the demo LuaSkill repository against the strict package rules.
校验演示 LuaSkill 仓库是否满足严格包结构规则。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml


"""
Return the repository root that also acts as the skill root.
返回同时作为技能根目录的仓库根目录。
"""
def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


"""
Raise one validation error when the condition is false.
当条件不成立时抛出一条校验错误。
"""
def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


"""
Return whether one version string follows strict semantic-version syntax.
返回单个版本字符串是否满足严格的语义化版本语法。
"""
def is_valid_semver(value: str) -> bool:
    pattern = re.compile(
        r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
        r"(?:-((?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*))?"
        r"(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$"
    )
    return bool(pattern.fullmatch(value.strip()))


"""
Load one YAML document from disk.
从磁盘加载一份 YAML 文档。
"""
def load_yaml(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        payload = yaml.safe_load(handle) or {}
    require(isinstance(payload, dict), f"Expected one YAML object in {path}")
    return payload


"""
Resolve one declared package-relative file while rejecting traversal and symbolic links.
解析一个清单声明的包内相对文件，同时拒绝目录穿越与符号链接。

Args:
    root: Repository root that owns the formal skill package.
    root：正式 skill 包所属的仓库根目录。
    relative_path: Manifest path that must stay below the package root.
    relative_path：必须保留在包根目录下的清单路径。
    label: Stable field label used in validation diagnostics.
    label：校验诊断使用的稳定字段标签。

Returns:
    Resolved regular-file path contained by the package root.
    位于包根目录内的已解析普通文件路径。
"""
def resolve_package_file(root: Path, relative_path: str, label: str) -> Path:
    # DeclaredPath preserves the exact relative structure supplied by the manifest.
    # DeclaredPath 保留清单提供的精确相对结构。
    declared_path = Path(relative_path)
    require(not declared_path.is_absolute(), f"{label} must be package-relative: {relative_path}")
    require(".." not in declared_path.parts, f"{label} cannot contain parent traversal: {relative_path}")
    # CandidatePath is checked before resolution so the declared leaf cannot be a symlink.
    # CandidatePath 在解析前接受检查，确保声明的叶子文件不是符号链接。
    candidate_path = root / declared_path
    require(not candidate_path.is_symlink(), f"{label} cannot reference a symbolic link: {relative_path}")
    # ResolvedRoot and ResolvedPath provide the canonical containment proof.
    # ResolvedRoot 与 ResolvedPath 提供规范化的包含关系证明。
    resolved_root = root.resolve()
    resolved_path = candidate_path.resolve()
    require(resolved_root in resolved_path.parents, f"{label} must stay under the package root: {relative_path}")
    require(resolved_path.is_file(), f"{label} points to a missing file: {relative_path}")
    # CurrentParent rejects an intermediate directory symlink even when it resolves inside root.
    # CurrentParent 拒绝中间目录符号链接，即使其解析结果仍位于根目录内。
    current_parent = candidate_path.parent
    while current_parent != root:
        require(not current_parent.is_symlink(), f"{label} cannot traverse a symbolic link: {relative_path}")
        current_parent = current_parent.parent
    return resolved_path


"""
Validate the strict top-level repository layout.
校验严格的顶层仓库目录结构。
"""
def validate_layout(root: Path) -> None:
    required_files = [
        root / "skill.yaml",
        root / "dependencies.yaml",
        root / "README.md",
    ]
    required_dirs = [
        root / "runtime",
        root / "help",
        root / "overflow_templates",
        root / "resources",
        root / "licenses",
    ]

    for file_path in required_files:
        require(file_path.is_file(), f"Missing required file: {file_path.name}")
    for dir_path in required_dirs:
        require(dir_path.is_dir(), f"Missing required directory: {dir_path.name}")


"""
Return whether text contains a CJK Unified Ideograph used by Chinese prose.
返回文本是否包含中文正文使用的中日韩统一表意文字。

Args:
    text: Unicode text inspected for Chinese ideographs.
    text：接受中文表意文字检查的 Unicode 文本。

Returns:
    True when at least one CJK Unified Ideograph is present.
    至少存在一个中日韩统一表意文字时返回真。
"""
def contains_han(text: str) -> bool:
    # HanPattern covers the common and Extension A ideograph blocks used by the docs.
    # HanPattern 覆盖文档使用的常用与扩展 A 表意文字区块。
    han_pattern = re.compile(r"[\u3400-\u4DBF\u4E00-\u9FFF]")
    return han_pattern.search(text) is not None


"""
Validate the English-default documentation and English-only AI Skill prompts.
校验英文默认文档与全英文 AI Skill 提示词。

Args:
    root: Repository root containing user documentation and the AI Skill.
    root：包含用户文档与 AI Skill 的仓库根目录。

Returns:
    None after every documentation-language invariant passes.
    所有文档语言约束通过后返回空值。
"""
def validate_documentation(root: Path) -> None:
    # LanguageSwitch is the exact first-line navigation shared by both README files.
    # LanguageSwitch 是两份 README 共享的精确首行语言导航。
    language_switch = "[English](README.md) | [简体中文](README.zh-CN.md)"
    # EnglishReadme is the default repository documentation.
    # EnglishReadme 是仓库默认说明文档。
    english_readme = root / "README.md"
    # ChineseReadme is the optional Simplified Chinese companion document.
    # ChineseReadme 是附加的简体中文说明文档。
    chinese_readme = root / "README.zh-CN.md"
    require(chinese_readme.is_file(), "Missing optional-language documentation: README.zh-CN.md")
    # EnglishText and ChineseText preserve exact line order for first-line validation.
    # EnglishText 与 ChineseText 保留精确行序以校验首行。
    english_text = english_readme.read_text(encoding="utf-8")
    chinese_text = chinese_readme.read_text(encoding="utf-8")
    require(english_text.splitlines()[0] == language_switch, "README.md must start with the language switch")
    require(chinese_text.splitlines()[0] == language_switch, "README.zh-CN.md must start with the language switch")
    # EnglishBody excludes the bilingual navigation label before enforcing English prose.
    # EnglishBody 在强制英文正文前排除双语导航标签。
    english_body = "\n".join(english_text.splitlines()[1:])
    require(not contains_han(english_body), "README.md must use English after the language switch")
    require(contains_han(chinese_text), "README.zh-CN.md must contain Simplified Chinese documentation")

    # SkillRoot owns every prompt and reference that must remain English-only.
    # SkillRoot 包含所有必须保持全英文的提示词与引用资料。
    skill_root = root / ".agents" / "skills" / "luaskills-development"
    require((skill_root / "SKILL.md").is_file(), "Missing LuaSkills AI Skill prompt")
    # PromptPath iterates over every textual Skill prompt or UI metadata file.
    # PromptPath 遍历每个 Skill 文本提示或 UI 元数据文件。
    for prompt_path in sorted(skill_root.rglob("*")):
        if not prompt_path.is_file() or prompt_path.suffix.lower() not in {".md", ".yaml", ".yml"}:
            continue
        # PromptText is checked independently so diagnostics identify the exact file.
        # PromptText 独立接受检查，使诊断能够定位精确文件。
        prompt_text = prompt_path.read_text(encoding="utf-8")
        require(not contains_han(prompt_text), f"AI Skill prompts must be English-only: {prompt_path.relative_to(root)}")


"""
Validate the skill manifest and entry references.
校验技能清单及其入口引用。
"""
def validate_manifest(root: Path) -> None:
    manifest = load_yaml(root / "skill.yaml")
    require("skill_id" not in manifest, "skill.yaml must not declare skill_id")
    version = manifest.get("version")
    require(isinstance(version, str) and version.strip(), "skill.yaml must declare a non-empty version")
    require(is_valid_semver(version), "skill.yaml version must be a valid semantic version")
    entries = manifest.get("entries")
    require(isinstance(entries, list) and entries, "skill.yaml must declare at least one entry")

    for entry in entries:
        require(isinstance(entry, dict), "Each entry must be one YAML object")
        entry_name = entry.get("name")
        lua_entry = entry.get("lua_entry")
        require(isinstance(entry_name, str) and entry_name, "Each entry requires a non-empty name")
        require(isinstance(lua_entry, str) and lua_entry, f"Entry '{entry_name}' requires lua_entry")
        resolve_package_file(root, lua_entry, f"Entry '{entry_name}' lua_entry")

    help_block = manifest.get("help", {})
    main_help = help_block.get("main")
    require(isinstance(main_help, dict), "skill.yaml must declare help.main")
    main_help_file = main_help.get("file")
    require(isinstance(main_help_file, str) and main_help_file, "help.main.file must be a non-empty string")
    resolve_package_file(root, main_help_file, "help.main.file")

    for topic in help_block.get("topics", []) or []:
        require(isinstance(topic, dict), "Each help topic must be one YAML object")
        topic_name = topic.get("name")
        topic_file = topic.get("file")
        require(isinstance(topic_name, str) and topic_name, "Each help topic requires a non-empty name")
        require(isinstance(topic_file, str) and topic_file, f"Help topic '{topic_name}' requires one file path")
        resolve_package_file(root, topic_file, f"Help topic '{topic_name}' file")


"""
Validate the dependency manifest used by the current package.
校验当前包使用的依赖清单。
"""
def validate_dependencies(root: Path) -> None:
    dependency_manifest = load_yaml(root / "dependencies.yaml")
    tools = dependency_manifest.get("tool_dependencies", [])
    require(isinstance(tools, list), "tool_dependencies must be a YAML list")

    # Tool is one explicitly declared skill dependency validated without demo-specific names.
    # Tool 是一个显式声明的 skill 依赖，校验时不绑定示例专用名称。
    for tool in tools:
        require(isinstance(tool, dict), "Each tool dependency must be one YAML object")
        # ToolName identifies the dependency in diagnostics and installed paths.
        # ToolName 在诊断信息与安装路径中标识该依赖。
        tool_name = tool.get("name")
        require(isinstance(tool_name, str) and tool_name, "Each tool dependency requires a non-empty name")
        # ToolVersion is the exact dependency version required by the manifest.
        # ToolVersion 是清单要求的精确依赖版本。
        tool_version = tool.get("version")
        require(tool_version is None or (isinstance(tool_version, str) and tool_version), f"Tool dependency '{tool_name}' has an invalid version")
        # RequiredValue preserves the protocol default when the field is omitted.
        # RequiredValue 在字段省略时保留协议默认语义。
        required_value = tool.get("required")
        require(required_value is None or isinstance(required_value, bool), f"Tool dependency '{tool_name}' has an invalid required field")
        # ScopeValue accepts only the serialized DependencyScope enum values from LuaSkills.
        # ScopeValue 仅接受 LuaSkills 中 DependencyScope 枚举的序列化值。
        scope_value = tool.get("scope")
        require(scope_value is None or scope_value in {"skill", "host"}, f"Tool dependency '{tool_name}' has an unsupported scope")
        require(isinstance(tool.get("source"), dict), f"Tool dependency '{tool_name}' requires one source object")
        # PackagesValue preserves the protocol's empty-map default when omitted.
        # PackagesValue 在字段省略时保留协议的空映射默认值。
        packages_value = tool.get("packages")
        require(packages_value is None or isinstance(packages_value, dict), f"Tool dependency '{tool_name}' has invalid platform packages")

    for group_name in ("lua_dependencies", "ffi_dependencies"):
        group = dependency_manifest.get(group_name, [])
        require(isinstance(group, list), f"{group_name} must be a YAML list")

    # NodeRuntime is the optional managed Node.js declaration defined by the current protocol.
    # NodeRuntime 是当前协议定义的可选受管 Node.js 声明。
    node_runtime = dependency_manifest.get("node_runtime")
    if node_runtime is not None:
        require(isinstance(node_runtime, dict), "node_runtime must be one YAML object")
        # NodeVersion is the exact semantic Node.js runtime version.
        # NodeVersion 是精确的 Node.js 运行时语义版本。
        node_version = node_runtime.get("version")
        require(isinstance(node_version, str) and is_valid_semver(node_version), "node_runtime.version must be an exact semantic version")
        require(node_runtime.get("package_manager") == "pnpm", "node_runtime.package_manager must be pnpm")
        # PackageManagerVersion is the exact pnpm semantic version.
        # PackageManagerVersion 是精确的 pnpm 语义版本。
        package_manager_version = node_runtime.get("package_manager_version")
        require(isinstance(package_manager_version, str) and is_valid_semver(package_manager_version), "node_runtime.package_manager_version must be an exact semantic version")
        # NodeRequired preserves the protocol default when omitted.
        # NodeRequired 在字段省略时保留协议默认语义。
        node_required = node_runtime.get("required")
        require(node_required is None or isinstance(node_required, bool), "node_runtime.required must be boolean when provided")

        for field_name in ("package_json", "lockfile"):
            # RelativePath is one optional package-relative Node.js declaration path.
            # RelativePath 是一个可选的 Node.js 包相对声明路径。
            relative_path = node_runtime.get(field_name, "")
            require(isinstance(relative_path, str), f"node_runtime.{field_name} must be a string")
            if not relative_path:
                continue
            resolve_package_file(root, relative_path, f"node_runtime.{field_name}")


"""
Execute the repository validation flow and return one process exit code.
执行仓库校验流程并返回进程退出码。
"""
def main() -> int:
    root = repo_root()
    try:
        validate_layout(root)
        validate_documentation(root)
        validate_manifest(root)
        validate_dependencies(root)
    except Exception as error:  # noqa: BLE001
        print(f"Validation failed: {error}")
        return 1

    print("Validation passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
