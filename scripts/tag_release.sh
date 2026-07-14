#!/usr/bin/env bash
set -euo pipefail

# Validate, package, create, and push the manifest-matching annotated release tag.
# 校验、打包、创建并推送与清单匹配的带注释发布标签。

if [ "$#" -ne 1 ]; then
  echo "Usage: ./scripts/tag_release.sh <version>"
  echo "用法：./scripts/tag_release.sh <版本号>"
  exit 1
fi

# ProjectRoot is the clean repository state that will be referenced by the tag.
# ProjectRoot 是标签将引用的干净仓库状态。
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# PythonCommand is the interpreter used by release-version validation.
# PythonCommand 是发布版本校验使用的解释器。
PYTHON_COMMAND="${PYTHON_COMMAND:-python3}"
# RequestedVersion is validated before any Git mutation occurs.
# RequestedVersion 在任何 Git 变更前接受校验。
REQUESTED_VERSION="$1"

cd "$PROJECT_ROOT"
# WorktreeStatus lists tracked and untracked changes that would be absent from the tag.
# WorktreeStatus 列出不会进入标签的已跟踪与未跟踪变更。
WORKTREE_STATUS="$(git status --porcelain=v1)"
if [ -n "$WORKTREE_STATUS" ]; then
  echo "Release requires a clean Git working tree. Commit or remove all changes first." >&2
  exit 1
fi

# ReleaseTag is the exact validated v-prefixed tag printed by the shared resolver.
# ReleaseTag 是共享解析器输出的精确已校验 v 前缀标签。
RELEASE_TAG="$("$PYTHON_COMMAND" -m scripts.release_version "$REQUESTED_VERSION")"

bash ./scripts/verify_skill.sh

echo "Creating annotated tag: $RELEASE_TAG"
git tag -a "$RELEASE_TAG" -m "发布 $RELEASE_TAG"

echo "Pushing tag to origin: $RELEASE_TAG"
git push origin "$RELEASE_TAG"
