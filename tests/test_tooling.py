"""
Test release-package filtering and manifest path safety.
测试发布包过滤与清单路径安全性。
"""

from __future__ import annotations

import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from scripts.package_skill import collect_package_paths
from scripts.release_version import normalize_requested_version, resolve_release_tag
from scripts.validate_skill import resolve_package_file


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


if __name__ == "__main__":
    unittest.main()
