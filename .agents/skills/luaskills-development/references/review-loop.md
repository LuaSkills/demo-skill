# Five-Consecutive-Pass Review Protocol

## Goal

After the real flow test passes, review and auto-fix the repository until five consecutive complete reviews find no issues. Any finding resets the consecutive-pass counter to zero; restart from pass one after fixing and retesting.

## State Rules

Maintain two explicit counters:

- `review_iteration`: increment after every complete review.
- `consecutive_clean_passes`: increment only when the current review finds nothing; reset to zero after any finding.

Stop only when `consecutive_clean_passes = 5`. A successful static command does not constitute a review pass. Every pass must include semantic inspection and real call-path verification.

## Required Scope for Every Pass

1. Manifest and protocol: compare `skill.yaml`, `dependencies.yaml`, entry parameters, help references, exact Node.js/pnpm versions, and authoritative upstream definitions.
2. Code correctness: inspect parameters, returns, error paths, and bilingual code comments in Lua, JavaScript, Python, PowerShell, and Shell.
3. Download safety: verify immutable Release URLs, checksum validation before execution or extraction, and isolation of incomplete downloads.
4. File safety: inspect recursive deletion targets, traversal rejection, symbolic links, the debugger staging whitelist, and Git ignore boundaries.
5. Cross-platform behavior: inspect Windows PowerShell and Linux/macOS Shell platform keys, paths, arguments, markers, encodings, and line endings.
6. Real invocation: confirm the official `sync -> inspect -> list-tools -> call` path, invoke every example tool, use the managed Node.js distribution instead of system Node.js, and verify repository-level locking for concurrent commands.
7. Packaging and release: verify the single zip root, exact member whitelist, checksum, Action branch/tag behavior, clean-worktree release guard, and dynamic Fork repository identity.
8. Documentation consistency: compare the default English README, optional Chinese README, English-only AI skill prompts, debugging guide, example commands, and actual script parameters.

## Action After a Finding

1. Record the exact file, location, root cause, and impact.
2. Fix the issue immediately without candidate fields or speculative multi-path behavior.
3. Run focused tests for the finding.
4. Rerun the complete real flow.
5. Reset `consecutive_clean_passes` to zero and restart accumulation on the next review.

## Pass Conditions

- The current review finds no new issue.
- Static validation, Skill validation, script syntax, every real tool call, managed Node.js invocation, idempotent download checks, and zip/checksum verification still pass.
- `git status --short --ignored` proves that downloads and build outputs remain ignored while AI skill files and formal source remain visible.
- No Chinese characters remain in `.agents/skills/luaskills-development/`; generated code may still contain the required second-line Chinese comments.
