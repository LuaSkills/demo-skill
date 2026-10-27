"""
Test release-package filtering, manifest path safety, bundled payloads, and the template cleaner.
测试发布包过滤、清单路径安全性、内置载荷与模板清理脚本。
"""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest

import yaml

from scripts.build_native import (
    LIBRARY_FILE_NAMES,
    library_file_name,
    library_relative_path,
    normalize_platform_key,
)
from scripts.clean_to_template import DEMO_BLOCK_BEGIN, DEMO_BLOCK_END, MARKED_FILES, REMOVED_PATHS
from scripts.package_skill import collect_package_paths, repo_root, require_bundled_payloads
from scripts.release_version import normalize_requested_version, resolve_release_tag
from scripts.validate_skill import resolve_package_file


# CopyIgnorePatterns excludes Git metadata, downloaded debugger files, and build output from repository copies.
# CopyIgnorePatterns 在复制仓库时排除 Git 元数据、下载的调试器文件与构建产物。
COPY_IGNORE_PATTERNS = (".git", ".luaskills-debug", ".luaskills-debug.lock*", "dist", "__pycache__", "node_modules")
# RemovedToolNames are the demo tools that must not survive template cleanup.
# RemovedToolNames 是模板清理后不得残留的演示工具。
REMOVED_TOOL_NAMES = ("demo-status", "rg-check", "overflow-demo", "node-runtime-demo", "native-demo")


"""
Run one repository script with the current interpreter and capture its output.
使用当前解释器运行一个仓库脚本并捕获其输出。

Args:
    root: Repository copy that owns the script and acts as the working directory.
    root：拥有该脚本并作为工作目录的仓库副本。
    script: Script path relative to root.
    script：相对 root 的脚本路径。
    arguments: Extra command-line arguments.
    arguments：额外的命令行参数。

Returns:
    Completed process with text stdout and stderr.
    带文本 stdout 与 stderr 的已完成进程。
"""
def run_script(root: Path, script: str, *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(root / script), *arguments],
        cwd=root,
        check=False,
        capture_output=True,
        text=True,
    )


"""
Return the exact bytes of every working-tree file below root keyed by POSIX relative path.
返回 root 下每个工作区文件的精确字节，以 POSIX 相对路径为键。

Git metadata and bytecode caches are skipped because Git and Python may refresh them on read.
跳过 Git 元数据与字节码缓存，因为 Git 和 Python 在读取时可能刷新它们。
"""
def snapshot_tree(root: Path) -> dict[str, bytes]:
    return {
        path.relative_to(root).as_posix(): path.read_bytes()
        for path in sorted(root.rglob("*"))
        if path.is_file() and not {".git", "__pycache__"} & set(path.relative_to(root).parts)
    }


class ToolingSafetyTests(unittest.TestCase):
    """
    Verify that local generated files and unsafe paths cannot enter a release package.
    验证本地生成文件与不安全路径无法进入发布包。
    """

    def test_generated_node_directories_are_excluded(self) -> None:
        """
        Confirm that Node.js dependency caches are excluded while source files remain.
        确认 Node.js 依赖缓存被排除，同时保留源文件。

        Returns:
            None after the exact package member list matches expectations.
            精确包成员列表符合预期后返回空值。
        """
        with TemporaryDirectory() as temporary_directory:
            # Root is an isolated synthetic skill package used by the collector.
            # Root 是供收集器使用的隔离合成 skill 包。
            root = Path(temporary_directory) / "demo-skill"
            # NodeRoot is the formal source directory allowed by the package whitelist.
            # NodeRoot 是打包白名单允许的正式源码目录。
            node_root = root / "node"
            (node_root / "node_modules" / "dependency").mkdir(parents=True)
            (node_root / ".pnpm-store").mkdir()
            (node_root / "echo.mjs").write_text("export {};\n", encoding="utf-8")
            (node_root / "node_modules" / "dependency" / "index.js").write_text(
                "generated\n",
                encoding="utf-8",
            )
            (node_root / ".pnpm-store" / "cache").write_text("generated\n", encoding="utf-8")

            # RelativePaths exposes the exact files the release collector accepted.
            # RelativePaths 展示发布收集器接受的精确文件。
            relative_paths = [
                path.relative_to(root).as_posix()
                for path in collect_package_paths(root)
            ]
            self.assertEqual(["node/echo.mjs"], relative_paths)

    def test_parent_traversal_is_rejected(self) -> None:
        """
        Confirm that a path cannot move to a parent even when it resolves back inside root.
        确认路径即使最终回到根目录内，也不能先移动到父目录。

        Returns:
            None after the validator raises the required traversal error.
            校验器按要求抛出穿越错误后返回空值。
        """
        with TemporaryDirectory() as temporary_directory:
            # Root owns the target file used by the normalization edge case.
            # Root 是规范化边界用例目标文件所属的根目录。
            root = Path(temporary_directory) / "demo-skill"
            root.mkdir()
            (root / "README.md").write_text("demo\n", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "parent traversal"):
                resolve_package_file(root, "../demo-skill/README.md", "test.path")

    def test_package_symlink_is_rejected(self) -> None:
        """
        Confirm that a symbolic link below a whitelisted directory fails packaging.
        确认白名单目录下的符号链接会导致打包失败。

        Returns:
            None after the collector rejects the symbolic link.
            收集器拒绝符号链接后返回空值。
        """
        with TemporaryDirectory() as temporary_directory:
            # Root contains one regular source and one link that points to it.
            # Root 包含一个普通源文件和一个指向该文件的链接。
            root = Path(temporary_directory) / "demo-skill"
            # RuntimeRoot is a formal package directory used for the link test.
            # RuntimeRoot 是符号链接测试使用的正式包目录。
            runtime_root = root / "runtime"
            runtime_root.mkdir(parents=True)
            # TargetPath is the real file referenced by the test link.
            # TargetPath 是测试链接引用的真实文件。
            target_path = runtime_root / "target.lua"
            target_path.write_text("return true\n", encoding="utf-8")
            # LinkPath is the unsafe package member expected to be rejected.
            # LinkPath 是预期被拒绝的不安全包成员。
            link_path = runtime_root / "linked.lua"
            try:
                os.symlink(target_path, link_path)
            except OSError as error:
                self.skipTest(f"Symbolic links are unavailable in this environment: {error}")
            with self.assertRaisesRegex(RuntimeError, "symbolic link"):
                collect_package_paths(root)

    def test_release_version_must_match_manifest(self) -> None:
        """
        Confirm that release tags accept only the exact semantic manifest version.
        确认发布标签只接受与清单精确一致的语义化版本。

        Returns:
            None after valid forms pass and mismatched or malformed forms fail.
            有效形式通过且不匹配或畸形形式失败后返回空值。
        """
        with TemporaryDirectory() as temporary_directory:
            # Root owns the isolated release manifest used by the resolver.
            # Root 是解析器使用的隔离发布清单所属根目录。
            root = Path(temporary_directory) / "demo-skill"
            root.mkdir()
            (root / "skill.yaml").write_text(
                "name: Demo\nversion: 1.2.3\n",
                encoding="utf-8",
            )
            self.assertEqual("v1.2.3", resolve_release_tag(root, "1.2.3"))
            self.assertEqual("v1.2.3", resolve_release_tag(root, "v1.2.3"))
            with self.assertRaisesRegex(RuntimeError, "does not match"):
                resolve_release_tag(root, "1.2.4")
            with self.assertRaisesRegex(RuntimeError, "exact semantic version"):
                normalize_requested_version("latest")


class BundledPayloadTests(unittest.TestCase):
    """
    Verify that strict packaging requires every declared bundled payload.
    验证严格打包要求每个已声明的内置载荷都存在。
    """

    def test_require_bundled_detects_missing_and_present_payloads(self) -> None:
        """
        Confirm that --require-bundled fails while a declared payload is absent and passes once it exists.
        确认已声明载荷缺失时 --require-bundled 失败，载荷存在后通过。

        Returns:
            None after both the failing and the passing states are observed.
            观察到失败与通过两种状态后返回空值。
        """
        with TemporaryDirectory() as temporary_directory:
            # Root is an isolated synthetic skill that declares one bundled library.
            # Root 是声明了一个内置库的隔离合成 skill。
            root = Path(temporary_directory) / "demo-skill"
            root.mkdir()
            (root / "dependencies.yaml").write_text(
                "tool_dependencies: []\n"
                "lua_dependencies: []\n"
                "ffi_dependencies:\n"
                "  - name: sample\n"
                "    version: \"1.0.0\"\n"
                "    source:\n"
                "      type: bundled\n"
                "    packages:\n"
                "      linux-x64:\n"
                "        archive_type: raw\n"
                "        path: native/linux-x64/libsample.so\n"
                "        exports:\n"
                "          - archive_path: libsample.so\n"
                "            target_path: lib/libsample.so\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(RuntimeError, "native/linux-x64/libsample.so"):
                require_bundled_payloads(root)

            # PayloadPath is the declared library file created to satisfy the check.
            # PayloadPath 是为满足检查而创建的已声明库文件。
            payload_path = root / "native" / "linux-x64" / "libsample.so"
            payload_path.parent.mkdir(parents=True)
            payload_path.write_bytes(b"\x7fELF")
            require_bundled_payloads(root)


class NativeBuildMappingTests(unittest.TestCase):
    """
    Verify the platform-key and library-name mapping used by the native build script.
    验证原生构建脚本使用的平台键与库文件名映射。
    """

    def test_platform_key_normalization(self) -> None:
        """
        Confirm that operating-system and machine names map to LuaSkills platform keys.
        确认操作系统与机器名称映射为 LuaSkills 平台键。

        Returns:
            None after every supported spelling maps and unsupported values fail.
            每种受支持写法均完成映射且不受支持的值失败后返回空值。
        """
        # Cases pairs platform.system()/platform.machine() spellings with expected keys.
        # Cases 将 platform.system()/platform.machine() 的写法与期望键配对。
        cases = (
            ("Windows", "AMD64", "windows-x64"),
            ("Windows", "ARM64", "windows-arm64"),
            ("Linux", "x86_64", "linux-x64"),
            ("Linux", "aarch64", "linux-arm64"),
            ("Darwin", "x86_64", "macos-x64"),
            ("Darwin", "arm64", "macos-arm64"),
        )
        for system_name, machine_name, expected_key in cases:
            with self.subTest(system=system_name, machine=machine_name):
                self.assertEqual(expected_key, normalize_platform_key(system_name, machine_name))
        with self.assertRaises(RuntimeError):
            normalize_platform_key("FreeBSD", "x86_64")
        with self.assertRaises(RuntimeError):
            normalize_platform_key("Linux", "riscv64")

    def test_library_names_follow_platform_conventions(self) -> None:
        """
        Confirm that each declared platform uses its native shared-library naming convention.
        确认每个已声明平台都使用其原生共享库命名约定。

        Returns:
            None after every declared key resolves and an undeclared key fails.
            每个已声明键都能解析且未声明键失败后返回空值。
        """
        # Conventions maps the operating-system prefix to the expected prefix and suffix.
        # Conventions 将操作系统前缀映射到期望的文件名前缀与后缀。
        conventions = {"windows": ("", ".dll"), "linux": ("lib", ".so"), "macos": ("lib", ".dylib")}
        for platform_key in LIBRARY_FILE_NAMES:
            with self.subTest(platform=platform_key):
                # FileName is the library name produced for this platform.
                # FileName 是该平台产出的库文件名。
                file_name = library_file_name(platform_key)
                prefix, suffix = conventions[platform_key.split("-", 1)[0]]
                self.assertTrue(file_name.startswith(prefix) and file_name.endswith(suffix), file_name)
                self.assertEqual(
                    f"native/{platform_key}/{file_name}",
                    library_relative_path(platform_key).as_posix(),
                )
        with self.assertRaises(RuntimeError):
            library_file_name("windows-arm64")

    def test_mapping_matches_dependency_declaration(self) -> None:
        """
        Confirm that build output paths equal the demo-native payload paths in dependencies.yaml.
        确认构建输出路径与 dependencies.yaml 中 demo-native 的载荷路径一致。

        Returns:
            None after the declared packages and the build mapping agree.
            已声明包与构建映射一致后返回空值。
        """
        with (repo_root() / "dependencies.yaml").open("r", encoding="utf-8") as handle:
            # Manifest is the live dependency declaration of this repository.
            # Manifest 是本仓库当前的依赖声明。
            manifest = yaml.safe_load(handle) or {}
        # Dependency is the demo-native entry, absent after template cleanup.
        # Dependency 是 demo-native 条目，模板清理后不存在。
        dependency = next(
            (item for item in manifest.get("ffi_dependencies") or [] if item.get("name") == "demo-native"),
            None,
        )
        if dependency is None:
            self.skipTest("demo-native is not declared in dependencies.yaml")
        # Packages maps each declared platform to its bundled payload declaration.
        # Packages 将每个已声明平台映射到其内置载荷声明。
        packages = dependency["packages"]
        self.assertEqual(set(LIBRARY_FILE_NAMES), set(packages))
        for platform_key, package in packages.items():
            with self.subTest(platform=platform_key):
                self.assertEqual(library_relative_path(platform_key).as_posix(), package["path"])
                self.assertEqual(
                    [library_file_name(platform_key)],
                    [export["archive_path"] for export in package["exports"]],
                )


class TemplateCleanerTests(unittest.TestCase):
    """
    Verify that the template cleaner produces a valid minimal skill and is safe to rerun.
    验证模板清理脚本产出有效的最小 skill，且可以安全地重复运行。
    """

    def copy_repository(self, destination: Path) -> Path:
        """
        Copy the repository into destination without Git metadata or generated output.
        将仓库复制到 destination，不含 Git 元数据或生成产物。

        Returns:
            Root of the repository copy.
            仓库副本的根目录。
        """
        # CopyRoot is the isolated repository copy that the cleaner may modify.
        # CopyRoot 是清理脚本可以修改的隔离仓库副本。
        copy_root = destination / "demo-skill"
        shutil.copytree(repo_root(), copy_root, ignore=shutil.ignore_patterns(*COPY_IGNORE_PATTERNS))
        return copy_root

    def test_cleaned_copy_validates_and_is_idempotent(self) -> None:
        """
        Confirm that cleaning leaves only the hello tool, passes validation, and changes nothing on a second run.
        确认清理后只保留 hello 工具、通过校验，并且第二次运行不做任何修改。

        Returns:
            None after the cleaned copy satisfies every structural expectation.
            清理后的副本满足全部结构预期后返回空值。
        """
        with TemporaryDirectory() as temporary_directory:
            # Root is the repository copy outside any Git work tree.
            # Root 是位于任何 Git 工作区之外的仓库副本。
            root = self.copy_repository(Path(temporary_directory))
            # PreviewSnapshot proves that a run without --yes leaves files untouched.
            # PreviewSnapshot 证明未传 --yes 的运行不会修改文件。
            preview_snapshot = snapshot_tree(root)
            preview = run_script(root, "scripts/clean_to_template.py")
            self.assertNotEqual(0, preview.returncode, preview.stdout + preview.stderr)
            self.assertEqual(preview_snapshot, snapshot_tree(root))

            cleaned = run_script(root, "scripts/clean_to_template.py", "--yes")
            self.assertEqual(0, cleaned.returncode, cleaned.stdout + cleaned.stderr)
            for relative_path in REMOVED_PATHS:
                with self.subTest(removed=relative_path):
                    self.assertFalse((root / relative_path).exists())
                    self.assertIn(relative_path, cleaned.stdout)

            validation = run_script(root, "scripts/validate_skill.py")
            self.assertEqual(0, validation.returncode, validation.stdout + validation.stderr)

            with (root / "skill.yaml").open("r", encoding="utf-8") as handle:
                # Manifest is the cleaned skill manifest.
                # Manifest 是清理后的 skill 清单。
                manifest = yaml.safe_load(handle)
            self.assertEqual(["hello"], [entry["name"] for entry in manifest["entries"]])
            self.assertEqual(
                ["hello.args.json"],
                sorted(path.name for path in (root / "examples" / "debug").iterdir()),
            )
            for relative_path in MARKED_FILES:
                # Text is one stripped file that must keep no demo marker or call to a removed tool.
                # Text 是一个已剥离的文件，不得残留演示标记或对已删除工具的调用。
                text = (root / relative_path).read_text(encoding="utf-8")
                # IsReadme marks prose that may still name removed tools when describing the cleaner.
                # IsReadme 标记在描述清理脚本时仍可提及已删除工具名称的说明文档。
                is_readme = relative_path.startswith("README")
                with self.subTest(marked=relative_path):
                    self.assertNotIn(DEMO_BLOCK_BEGIN, text)
                    self.assertNotIn(DEMO_BLOCK_END, text)
                    for tool_name in REMOVED_TOOL_NAMES:
                        self.assertNotIn(f"{tool_name}.args.json", text)
                        if not is_readme:
                            self.assertNotIn(tool_name, text)

            # CleanedSnapshot is compared against the state after a second run.
            # CleanedSnapshot 与第二次运行后的状态进行比较。
            cleaned_snapshot = snapshot_tree(root)
            rerun = run_script(root, "scripts/clean_to_template.py", "--yes")
            self.assertEqual(0, rerun.returncode, rerun.stdout + rerun.stderr)
            self.assertEqual(cleaned_snapshot, snapshot_tree(root))

    def test_dirty_git_tree_requires_force(self) -> None:
        """
        Confirm that uncommitted changes block cleaning until --force is passed.
        确认存在未提交变更时，必须传入 --force 才能清理。

        Returns:
            None after the refusal leaves files untouched and --force proceeds.
            拒绝时文件保持不变且 --force 继续执行后返回空值。
        """
        if shutil.which("git") is None:
            self.skipTest("git is not available")
        with TemporaryDirectory() as temporary_directory:
            # Root becomes a fresh Git work tree whose files are all untracked.
            # Root 成为一个新的 Git 工作区，其中所有文件都未被跟踪。
            root = self.copy_repository(Path(temporary_directory))
            subprocess.run(["git", "init", "--quiet"], cwd=root, check=True)
            # DirtySnapshot proves that the refused run leaves files untouched.
            # DirtySnapshot 证明被拒绝的运行不会修改文件。
            dirty_snapshot = snapshot_tree(root)
            refused = run_script(root, "scripts/clean_to_template.py", "--yes")
            self.assertNotEqual(0, refused.returncode, refused.stdout + refused.stderr)
            self.assertEqual(dirty_snapshot, snapshot_tree(root))

            forced = run_script(root, "scripts/clean_to_template.py", "--yes", "--force")
            self.assertEqual(0, forced.returncode, forced.stdout + forced.stderr)
            self.assertFalse((root / "native").exists())


if __name__ == "__main__":
    unittest.main()
