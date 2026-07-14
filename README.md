[English](README.md) | [简体中文](README.zh-CN.md)

# Forkable LuaSkills Development Template

This repository is a complete, fork-ready LuaSkill template. It includes formal skill examples, an AI development skill, verified installation of the official `luaskills-debug` environment, real engine invocation, local validation and packaging, and GitHub Actions release workflows.

The template targets the stable LuaSkills release **v0.5.2**. [`.luaskills-version`](.luaskills-version) is the single debugger and documentation version baseline. The example skill version is `0.2.0`; these versions have different purposes and do not need to match.

## Give the Fork to an AI

After forking and cloning the repository, give this prompt to an AI that supports Skill files:

```text
Read and strictly follow .agents/skills/luaskills-development/SKILL.md. Develop, debug, validate, review, and package this LuaSkill from my requirements.
```

The AI Skill requires source-backed facts for manifests, entries, arguments, and call paths before implementation. It uses the formal debugger and forbids speculative candidate fields or multi-path fallbacks. Detailed instructions are available in:

- `.agents/skills/luaskills-development/references/ai-debugging.md`
- `.agents/skills/luaskills-development/references/review-loop.md`

## One-Command Debug Environment Setup

Windows:

```powershell
.\scripts\setup_debug.ps1
```

Linux/macOS:

```bash
bash ./scripts/setup_debug.sh
```

The setup script selects the official Release assets for the current operating system and CPU architecture:

```text
luaskills-debug-tool-{platform}.tar.gz
luaskills-debug-tool-{platform}.tar.gz.sha256
```

After checksum verification, the debugger, Lua runtime packages, Node.js `24.18.0`, and pnpm `11.11.0` are stored under:

```text
.luaskills-debug/
```

The entire directory is ignored by Git and cannot enter a commit or formal skill package. Force a fresh download with:

```powershell
.\scripts\setup_debug.ps1 -Force
```

```bash
bash ./scripts/setup_debug.sh --force
```

Setup also downloads the official v0.5.2 `fetch_managed_runtimes.*` script, verifies its pinned SHA-256 digest, and only then executes it. The upstream fetcher verifies Node.js through the official `SHASUMS256.txt` and pnpm through npm integrity metadata. To inspect only the debugger without either runtime family, use:

```powershell
.\scripts\setup_debug.ps1 -SkipRuntimeSetup -SkipManagedNodeSetup
```

```bash
bash ./scripts/setup_debug.sh --skip-runtime-setup --skip-managed-node-setup
```

## Debug the Current Skill

The wrapper uses the same loading and invocation path as the formal host. It stages only release-whitelisted source under `.luaskills-debug/source/<skill-id>/`, then synchronizes that source into the isolated runtime root. `.git/`, downloaded tools, AI prompts, tests, and build scripts are never recursively copied into the runtime.

Each debug command serializes environment setup, whitelist staging, synchronization, and invocation with a repository-level lock. Multiple AI tasks or terminals can start commands concurrently without deleting each other's staged files.

Windows:

```powershell
.\scripts\debug_skill.ps1 -Command inspect
.\scripts\debug_skill.ps1 -Command list-tools
.\scripts\debug_skill.ps1 -Command call -Tool demo-status -ArgsFile .\examples\debug\demo-status.args.json
.\scripts\debug_skill.ps1 -Command call -Tool rg-check -ArgsFile .\examples\debug\rg-check.args.json -Output json
.\scripts\debug_skill.ps1 -Command call -Tool overflow-demo -ArgsFile .\examples\debug\overflow-demo.args.json -Output content
.\scripts\debug_skill.ps1 -Command call -Tool node-runtime-demo -ArgsFile .\examples\debug\node-runtime-demo.args.json -Output json
```

Linux/macOS:

```bash
bash ./scripts/debug_skill.sh inspect
bash ./scripts/debug_skill.sh list-tools
bash ./scripts/debug_skill.sh call --tool demo-status --args-file ./examples/debug/demo-status.args.json
bash ./scripts/debug_skill.sh call --tool rg-check --args-file ./examples/debug/rg-check.args.json --output json
bash ./scripts/debug_skill.sh call --tool overflow-demo --args-file ./examples/debug/overflow-demo.args.json --output content
bash ./scripts/debug_skill.sh call --tool node-runtime-demo --args-file ./examples/debug/node-runtime-demo.args.json --output json
```

Available commands:

- `sync`: synchronize the staged skill into the debug runtime.
- `inspect`: validate and display the manifest, skill ID, entries, and engine loading result.
- `list-tools`: list real callable local and canonical tool names.
- `call`: invoke a tool through the formal engine.

## One-Command Verification and Packaging

Windows:

```powershell
.\scripts\verify_skill.ps1
```

Linux/macOS:

```bash
bash ./scripts/verify_skill.sh
```

The command executes:

1. Negative tests for package filtering, path traversal, symbolic links, and release-version validation.
2. Strict repository and manifest validation.
3. Official debugger `inspect`.
4. Official debugger `list-tools`.
5. Real invocation of all four example tools. `node-runtime-demo` creates the locked pnpm environment and performs two ESM Worker calls.
6. Deterministic release-package generation.

Generated artifacts are stored under `dist/`:

```text
<skill-id>-v<version>-skill.zip
<skill-id>-v<version>-checksums.txt
```

The zip has one `<skill-id>/` top-level directory and collects only existing files from this whitelist:

```text
skill.yaml
dependencies.yaml
README.md
README.zh-CN.md
LICENSE
runtime/
node/
python/
help/
overflow_templates/
resources/
licenses/
```

`.agents/`, `.github/`, `scripts/`, `tests/`, `.luaskills-debug/`, `dist/`, `node_modules/`, `.pnpm-store/`, Python caches, other local artifacts, and symbolic links cannot enter the formal package.

## GitHub Actions

The repository contains two reusable workflows:

- **Validate and Package LuaSkill**: on pull requests or manual dispatch, downloads the debugger and runtimes, loads the skill, enumerates tools, performs real invocations, packages the skill, and uploads `<repository-name>-verified-package`.
- **Release LuaSkill**: on a `v*` tag, reruns the same real debug flow, creates a GitHub Release, and uploads only the formal zip and checksum.

The release script rejects a dirty worktree, requires its argument to match `skill.yaml.version`, and reruns the complete verification flow before it creates and pushes the tag. For version `0.2.0`:

```powershell
.\scripts\tag_release.ps1 0.2.0
```

```bash
bash ./scripts/tag_release.sh 0.2.0
```

## What to Replace After Forking

1. Rename the repository to the final `skill_id`, using lowercase letters, digits, and single hyphens.
2. Replace the display name, version, entries, parameters, and help references in `skill.yaml`.
3. Replace example content under `runtime/`, `node/`, `python/`, `help/`, `overflow_templates/`, `resources/`, and `licenses/`.
4. Declare real dependencies in `dependencies.yaml`. The validator does not require the example `rg` dependency. If Node.js is not needed, remove `node_runtime`, `node/`, and its entry together.
5. Replace remaining `demo-skill` descriptions in both README files and help documents.
6. Run `verify_skill`, complete five consecutive clean review passes, commit the intended files, and only then run the release script.

The physical repository directory name defines the formal `skill_id`. Changing only `skill.yaml.name` does not change the installation identity.

## Included Examples

- `demo-status`: returns stable skill version, directory, request context, and lifecycle diagnostics.
- `rg-check`: demonstrates a private optional tool dependency and `vulcan.deps.tools_path`.
- `overflow-demo`: demonstrates paged output and a skill-local overflow template.
- `node-runtime-demo`: demonstrates managed Node.js `24.18.0`, pnpm-locked dependencies, an ESM handler, environment creation, Worker reuse, and real invocation diagnostics.

## Five-Pass Pre-Release Review

After implementation and the real flow test pass, the AI must repeatedly review code, manifests, download verification, cross-platform scripts, package whitelists, Actions, and documentation. Any finding must be fixed immediately, followed by a full retest and a reset of the consecutive-pass counter. Work may finish or release only after five consecutive complete reviews find no issues.

Use the official LuaSkills v0.5.2 documentation as the protocol authority:

- [Lua Skill Development Manual](https://github.com/LuaSkills/luaskills/blob/v0.5.2/docs/skill-development.md)
- [Lua Skill Development Manual (Simplified Chinese)](https://github.com/LuaSkills/luaskills/blob/v0.5.2/docs/zh-CN/skill-development.md)
- [LuaSkills v0.5.2 Release](https://github.com/LuaSkills/luaskills/releases/tag/v0.5.2)
