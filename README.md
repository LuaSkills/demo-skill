[English](README.md) | [简体中文](README.zh-CN.md)

# Forkable LuaSkills Development Template

This repository is a complete, fork-ready LuaSkill template. It includes formal skill examples, an AI development skill, verified installation of the official `luaskills-debug` environment, real engine invocation, local validation and packaging, a bundled native library built per platform, and GitHub Actions release workflows.

The template targets the stable LuaSkills release **v0.7.2**. [`.luaskills-version`](.luaskills-version) is the single debugger and documentation version baseline. The skill package version lives in `skill.yaml`; these versions have different purposes and do not need to match.

<!-- >>> demo-only -->
The demo skill version is `0.3.1`. Run the [template cleaner](#start-from-a-minimal-template) to strip the demos and keep only a minimal `hello` tool.
<!-- <<< demo-only -->

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

Setup also downloads the official v0.7.2 `fetch_managed_runtimes.*` script, verifies its pinned SHA-256 digest, and only then executes it. The upstream fetcher verifies Node.js through the official `SHASUMS256.txt` and pnpm through npm integrity metadata. To inspect only the debugger without either runtime family, use:

```powershell
.\scripts\setup_debug.ps1 -SkipRuntimeSetup -SkipManagedNodeSetup
```

```bash
bash ./scripts/setup_debug.sh --skip-runtime-setup --skip-managed-node-setup
```

The v0.7.2 Linux debug tool archive also carries a detached OpenPGP signature at `bin/luaskills-debug.asc`. Setup verifies the SHA-256 checksum only. To check the signature as well, import the LuaSkills release key (`scripts/release/release-gpg-public.asc` in the LuaSkills repository at the same tag) and run:

```bash
gpg --verify .luaskills-debug/bin/luaskills-debug.asc .luaskills-debug/bin/luaskills-debug
```

## Debug the Current Skill

The wrapper uses the same loading and invocation path as the formal host. It stages only release-whitelisted source under `.luaskills-debug/source/<skill-id>/`, then synchronizes that source into the isolated runtime root. `.git/`, downloaded tools, AI prompts, tests, and build scripts are never recursively copied into the runtime. The wrapper calls `.luaskills-debug/bin/luaskills-debug` directly, because the launchers inside the v0.7.2 debug package forward only the classic options.

Each debug command serializes environment setup, whitelist staging, synchronization, and invocation with a repository-level lock. Multiple AI tasks or terminals can start commands concurrently without deleting each other's staged files.

Windows:

```powershell
.\scripts\debug_skill.ps1 -Command inspect
.\scripts\debug_skill.ps1 -Command list-tools
.\scripts\debug_skill.ps1 -Command call -Tool hello -ArgsFile .\examples\debug\hello.args.json -Output json
```

Linux/macOS:

```bash
bash ./scripts/debug_skill.sh inspect
bash ./scripts/debug_skill.sh list-tools
bash ./scripts/debug_skill.sh call --tool hello --args-file ./examples/debug/hello.args.json --output json
```

<!-- >>> demo-only -->
The demo tools are called the same way:

```powershell
.\scripts\debug_skill.ps1 -Command call -Tool demo-status -ArgsFile .\examples\debug\demo-status.args.json
.\scripts\debug_skill.ps1 -Command call -Tool rg-check -ArgsFile .\examples\debug\rg-check.args.json -Output json
.\scripts\debug_skill.ps1 -Command call -Tool overflow-demo -ArgsFile .\examples\debug\overflow-demo.args.json -Output content
.\scripts\debug_skill.ps1 -Command call -Tool node-runtime-demo -ArgsFile .\examples\debug\node-runtime-demo.args.json -Output json
.\scripts\debug_skill.ps1 -Command call -Tool native-demo -ArgsFile .\examples\debug\native-demo.args.json -Output json
```

```bash
bash ./scripts/debug_skill.sh call --tool demo-status --args-file ./examples/debug/demo-status.args.json
bash ./scripts/debug_skill.sh call --tool rg-check --args-file ./examples/debug/rg-check.args.json --output json
bash ./scripts/debug_skill.sh call --tool overflow-demo --args-file ./examples/debug/overflow-demo.args.json --output content
bash ./scripts/debug_skill.sh call --tool node-runtime-demo --args-file ./examples/debug/node-runtime-demo.args.json --output json
bash ./scripts/debug_skill.sh call --tool native-demo --args-file ./examples/debug/native-demo.args.json --output json
```
<!-- <<< demo-only -->

Available commands:

- `sync`: synchronize the staged skill into the debug runtime.
- `inspect`: validate and display the manifest, skill ID, entries, and engine loading result.
- `list-tools`: list real callable local and canonical tool names.
- `call`: invoke a tool through the formal engine.
- `probe-mirrors`: measure GitHub download mirrors; it needs no staged skill.

## Download Mirrors and GitHub Tokens

Dependencies declared with `source.type: github_release` are downloaded by the debugger while it prepares the skill. Two options control those downloads for `sync`, `inspect`, `list-tools`, and `call`:

- `--github-mirror <id|url>` (`-GithubMirror` on Windows) downloads release assets through a built-in mirror id or a mirror URL. Built-in ids in v0.7.2: `github`, `gh-proxy-com`, `ghfast-top`, `gh-llkk-cc`, `ghproxy-net`.
- `--github-token-env <NAME>` (`-GithubTokenEnv` on Windows) reads a GitHub token from the named environment variable. The token is sent only to `api.github.com`, which lifts the anonymous API rate limit. Pass the variable name, never the token itself.

These options do not change how `setup_debug` downloads the debugger, which always uses the official release URLs.

Measure every built-in mirror, or compare selected ones:

```powershell
.\scripts\debug_skill.ps1 -Command probe-mirrors
.\scripts\debug_skill.ps1 -Command probe-mirrors -GithubMirror ghfast-top, gh-proxy-com -Output json
```

```bash
bash ./scripts/debug_skill.sh probe-mirrors
bash ./scripts/debug_skill.sh probe-mirrors --github-mirror ghfast-top --github-mirror gh-proxy-com --output json
```

Load the skill through a mirror and authenticate GitHub API lookups with a token taken from the GitHub CLI:

```powershell
$env:LUASKILLS_GITHUB_TOKEN = gh auth token
.\scripts\debug_skill.ps1 -Command inspect -GithubMirror ghfast-top -GithubTokenEnv LUASKILLS_GITHUB_TOKEN
```

```bash
export LUASKILLS_GITHUB_TOKEN="$(gh auth token)"
bash ./scripts/debug_skill.sh inspect --github-mirror ghfast-top --github-token-env LUASKILLS_GITHUB_TOKEN
```

A dependency that is already installed in `.luaskills-debug/runtime/` is reused, so these options matter only when a download actually happens, for example after `setup_debug -Force` or `--force`.

<!-- >>> demo-only -->
## Bundled Native Library Demo

`native-demo` shows how a skill ships its own native library (`source.type: bundled`, introduced in LuaSkills 0.7.0) and calls it through LuaJIT FFI. Installing a bundled payload never touches the network.

- `native/demo_native.c` exports `demo_native_version()` and `demo_native_add(a, b)`.
- `scripts/build_native.py` compiles it for the current host into `native/<platform>/<library>`: `demo_native.dll` on `windows-x64`, `libdemo_native.so` on `linux-x64` and `linux-arm64`, and `libdemo_native.dylib` on `macos-x64` and `macos-arm64`. It uses `$CC` when set, otherwise the first of `gcc`, `clang`, or `cc`, and on Windows falls back to MSVC `cl`. MinGW builds link libgcc statically, MSVC builds link the static CRT, and macOS builds target macOS 11.0 unless `MACOSX_DEPLOYMENT_TARGET` is set.
- `dependencies.yaml` declares `demo-native` `1.0.0` with one `archive_type: raw` package per platform that exports `lib/<library>`. No `sha256` is pinned: the payload travels inside the skill zip, whose release checksum already covers it.
- `runtime/native_demo.lua` builds `vulcan.deps.ffi_path/demo-native/1.0.0/<platform>/lib/<library>`, reports whether it exists, and when it does, loads it with `ffi.load` and returns the library version and `a + b`.

Build the host library before debugging it:

```powershell
python .\scripts\build_native.py
```

```bash
python3 ./scripts/build_native.py
```

Built libraries match the `*.dll`, `*.so`, and `*.dylib` rules in `.gitignore`, so they never enter a commit, yet the `native/` directory is part of the package whitelist, so they do enter the skill zip.

The dependency declares `required: false`. Since LuaSkills 0.7.2, an optional dependency that cannot be made ready (the payload is missing, the current platform has no package entry, or a download fails) only logs a warning and the skill still loads. So:

- The release workflow builds all five platforms on native runners and packages with `--require-bundled`, so every published zip carries every payload.
- A host on `windows-arm64`, which has no entry, or a debug machine that has not run `build_native.py` still loads every other tool, and `native-demo` reports `exists: false`, just like `rg-check` reports a missing `rg`.

LuaSkills reuses an installed dependency of the same version. After changing the C source, bump the dependency version in `dependencies.yaml` and `runtime/native_demo.lua`, or delete `.luaskills-debug/runtime/dependencies/ffi/<skill-id>/demo-native/` before the next debug run.
<!-- <<< demo-only -->

<!-- >>> demo-only -->
## LuaSkills Package Configuration Example

The top-level `config` block in `skill.yaml` demonstrates package-scoped declarations for all five supported types: `string`, `integer`, `float`, `enum`, and `boolean`. It also covers constraints, defaults, a required sensitive value, titles, groups, ordering, formats, restart hints, advanced flags, and enum metadata. The contract was introduced in LuaSkills 0.5.5 and is unchanged in v0.7.2.

`runtime/config_validator.lua` demonstrates isolated cross-field validation. `resources/skill-config.example.json` shows the only supported persisted document shape with `format_version`, a decimal-string `revision`, and the package-keyed `skills` object. The required sensitive `api_token` is intentionally absent from the tracked example.

The embedding host must explicitly provide one absolute, writable, user-level `skill_config_root`. Normal package values are stored at `<skill_config_root>/skills/config.json`; package Lua can access only its own namespace through `vulcan.config.*`, while cross-package administration belongs to the host.

The v0.7.2 standalone `luaskills-debug` CLI validates configuration declarations and the `config_validator` path during `inspect`, but it does not expose a `skill_config_root` option. The validator itself runs only during configuration transactions. Therefore the repository debug flow validates the package contract without pretending to perform configuration writes. Use a host or SDK configured with `skill_config_root` to exercise `runtime-config` reads, writes, and cross-field validation.
<!-- <<< demo-only -->

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

1. Negative tests for package filtering, path traversal, symbolic links, release-version validation, bundled-payload packaging, and the template cleaner.
2. Strict repository and manifest validation, including that every `examples/debug/<tool>.args.json` names a declared entry.
3. Official debugger `inspect`, including the package configuration declaration and `config_validator` path when present.
4. Official debugger `list-tools`.
5. Real invocation of every example tool.
6. Deterministic release-package generation.

<!-- >>> demo-only -->
In this demo the verify scripts first build the host `demo-native` library, which needs a C compiler, and then call all six tools. `node-runtime-demo` creates the locked pnpm environment and performs two ESM Worker calls.
<!-- <<< demo-only -->

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
native/
help/
overflow_templates/
resources/
licenses/
```

`.agents/`, `.github/`, `scripts/`, `tests/`, `.luaskills-debug/`, `dist/`, `node_modules/`, `.pnpm-store/`, Python caches, other local artifacts, and symbolic links cannot enter the formal package.

Local packaging accepts missing bundled payloads so that one machine can package what it has built. `python scripts/package_skill.py --require-bundled` fails instead when any `path` declared by a bundled dependency in `dependencies.yaml` would be absent from the zip; the release workflow always uses it.

## GitHub Actions

The repository contains two reusable workflows:

- **Validate and Package LuaSkill**: on pull requests or manual dispatch, downloads the debugger and runtimes, loads the skill, enumerates tools, performs real invocations, packages the skill, and uploads `<repository-name>-verified-package`.
- **Release LuaSkill**: on a `v*` tag, reruns the same real debug flow, packages with `--require-bundled`, creates a GitHub Release, and uploads only the formal zip and checksum.

<!-- >>> demo-only -->
Both workflows build the host `demo-native` library before verification. The release workflow also runs a `native` matrix job that builds the library on `ubuntu-24.04` (linux-x64), `ubuntu-24.04-arm` (linux-arm64), `macos-15-intel` (macos-x64), `macos-15` (macos-arm64), and `windows-latest` with MSVC (windows-x64), the same runner labels the LuaSkills core release uses. The release job downloads each library into `native/<platform>/` before packaging.
<!-- <<< demo-only -->

The release script rejects a dirty worktree, requires its argument to match `skill.yaml.version`, and reruns the complete verification flow before it creates and pushes the tag. Pass the exact version from `skill.yaml`:

```powershell
.\scripts\tag_release.ps1 <version>
```

```bash
bash ./scripts/tag_release.sh <version>
```

<!-- >>> demo-only -->
For this demo the version is `0.3.1`.
<!-- <<< demo-only -->

## Start From a Minimal Template

The demo tools are useful references but noise in a new skill. One command reduces the repository to a minimal skill with a single `hello` tool:

```powershell
.\scripts\clean_to_template.ps1 -Yes
```

```bash
bash ./scripts/clean_to_template.sh --yes
```

The cleaner:

- removes the `demo-status`, `rg-check`, `overflow-demo`, `node-runtime-demo`, and `native-demo` tools with their runtime, help, and example files, the configuration example, and the `node/`, `native/`, `overflow_templates/`, and `resources/` directories;
- rewrites `skill.yaml`, `dependencies.yaml` (all groups empty), `help/help.md`, and `licenses/THIRD_PARTY_NOTICES.md` with minimal content;
- deletes every block marked `demo-only` in both README files, the verify scripts, and the workflows, so the verify scripts call only `hello` and the release workflow loses its native build job;
- keeps all tooling: the package, validate, debug, setup, release, tag, native build, and cleaner scripts, the workflows, `.agents/`, and `tests/`.

Without `--yes` it only lists the planned changes. It refuses to run while `git status --porcelain` reports changes unless `--force` is passed, prints every removed or rewritten path, and does nothing when run again. Afterwards run `validate_skill.py` and `verify_skill`, and pass `--skip-managed-node-setup` to `setup_debug` if the skill does not declare `node_runtime`.

## What to Replace After Forking

1. Optionally run the [template cleaner](#start-from-a-minimal-template) first.
2. Rename the repository to the final `skill_id`, using lowercase letters, digits, and single hyphens.
3. Replace the display name, version, entries, parameters, and help references in `skill.yaml`.
4. Replace example content under `runtime/`, `node/`, `python/`, `native/`, `help/`, `overflow_templates/`, `resources/`, and `licenses/`.
5. Declare real dependencies in `dependencies.yaml`. The validator does not require the example `rg` or `demo-native` dependencies. If Node.js is not needed, remove `node_runtime`, `node/`, and its entry together. If no native library is bundled, remove `native/` and the bundled entry together.
6. Replace remaining `demo-skill` descriptions in both README files and help documents.
7. Run `verify_skill`, complete five consecutive clean review passes, commit the intended files, and only then run the release script.

The physical repository directory name defines the formal `skill_id`. Changing only `skill.yaml.name` does not change the installation identity.

<!-- >>> demo-only -->
## Included Examples

- `hello`: the minimal tool kept by the template cleaner.
- `demo-status`: returns stable skill version, directory, request context, and lifecycle diagnostics.
- `rg-check`: demonstrates a private optional tool dependency and `vulcan.deps.tools_path`.
- `overflow-demo`: demonstrates paged output and a skill-local overflow template.
- `node-runtime-demo`: demonstrates managed Node.js `24.18.0`, pnpm-locked dependencies, an ESM handler, environment creation, Worker reuse, and real invocation diagnostics.
- `native-demo`: demonstrates a bundled native library per platform, `vulcan.deps.ffi_path`, and LuaJIT FFI calls.
- Package configuration: demonstrates LuaSkills package configuration declarations, UI metadata, cross-field validation, missing-secret guidance, and the persisted JSON format.
<!-- <<< demo-only -->

## Five-Pass Pre-Release Review

After implementation and the real flow test pass, the AI must repeatedly review code, manifests, download verification, cross-platform scripts, package whitelists, Actions, and documentation. Any finding must be fixed immediately, followed by a full retest and a reset of the consecutive-pass counter. Work may finish or release only after five consecutive complete reviews find no issues.

Use the official LuaSkills v0.7.2 documentation as the protocol authority:

- [Lua Skill Development Manual](https://github.com/LuaSkills/luaskills/blob/v0.7.2/docs/development/skill-development.md)
- [Lua Skill Development Manual (Simplified Chinese)](https://github.com/LuaSkills/luaskills/blob/v0.7.2/docs/zh-CN/development/skill-development.md)
- [Package Configuration Host Contract](https://github.com/LuaSkills/luaskills/blob/v0.7.2/docs/integration/package-configuration.md)
- [LuaSkills v0.7.2 Release](https://github.com/LuaSkills/luaskills/releases/tag/v0.7.2)
