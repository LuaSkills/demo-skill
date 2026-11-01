# AI Invocation Debugging Guide

## Contents

- [Goal](#goal)
- [First-Time Setup](#first-time-setup)
- [Standard Debug Sequence](#standard-debug-sequence)
- [Invocation Arguments](#invocation-arguments)
- [Output Modes](#output-modes)
- [Troubleshooting](#troubleshooting)
- [Pre-Release Closure](#pre-release-closure)

## Goal

Validate the repository through the same `load_from_roots -> call_skill` path used by the formal host. The repository wrapper passes the repository root to the official debugger as `--skill-path`. The debugger copies it to `.luaskills-debug/runtime/skills/<skill-id>` and loads it from the isolated runtime root. The copy skips `target`, `.git`, `.svn`, `node_modules`, `__pycache__`, and `.luaskills-debug` at every depth, and `dist`, `out`, `temp`, `state`, `databases`, `dependencies`, `lua_packages`, and `libs` only directly under the repository root. Always go through `scripts/debug_skill.*`, and never replace formal invocation with direct Lua file execution.

## First-Time Setup

Windows:

```powershell
.\scripts\setup_debug.ps1
```

Linux/macOS:

```bash
bash ./scripts/setup_debug.sh
```

Require the setup script to:

1. Read the pinned `luaskills-debug` release tag from `.luaskills-version`.
2. Select `luaskills-debug-tool-{platform}.tar.gz` for the current operating system and CPU architecture (`windows-x64`, `linux-x64`, `linux-arm64`, `macos-x64`, or `macos-arm64`) from `https://github.com/LuaSkills/luaskills-debug/releases/download/<tag>/`.
3. Download the archive and the release-wide `luaskills-debug-checksums.txt`.
4. Verify the archive's SHA-256 against its checksums entry before extraction.
5. Store the complete debugger workspace under the Git-ignored `.luaskills-debug/` directory.
6. Run the official `setup_runtime` flow to download matching Lua runtime packages.
7. Run `scripts/deps/fetch_managed_runtimes.*` from the verified archive to install Node.js `24.18.0` with pnpm `11.11.0`.

Use `-Force` or `--force` to rebuild the workspace. When only the debugger binary is needed, pass both `-SkipRuntimeSetup -SkipManagedNodeSetup` or `--skip-runtime-setup --skip-managed-node-setup`.

## Standard Debug Sequence

After changing an entry or manifest, follow this fixed sequence:

1. `inspect`: validate the manifest, physical directory binding, entry files, and formal engine loading.
2. `list-tools`: confirm public and canonical tool names.
3. `call`: invoke the target tool with real arguments. If `node_runtime` is declared, invoke the managed Node.js entry in practice.
4. `verify_skill`: run the Python unit tests, loading, enumeration, every example tool call, `validate`, and `package`.

Run `validate` and `package` through the same wrapper when checking release readiness alone. `package` uses `LUASKILLS_PACKAGE_LAYOUT` when set, otherwise `standard`; pass `--layout platform` (`-Layout platform` on Windows) to preview the platform layout.

Every debug command runs setup, synchronization, and invocation while holding a repository-level lock, which serializes concurrent commands from multiple agents or terminals.

Windows:

```powershell
.\scripts\debug_skill.ps1 -Command inspect
.\scripts\debug_skill.ps1 -Command list-tools
.\scripts\debug_skill.ps1 -Command call -Tool hello -ArgsFile .\examples\debug\hello.args.json -Output json
.\scripts\debug_skill.ps1 -Command validate
.\scripts\debug_skill.ps1 -Command package
.\scripts\verify_skill.ps1
```

Linux/macOS:

```bash
bash ./scripts/debug_skill.sh inspect
bash ./scripts/debug_skill.sh list-tools
bash ./scripts/debug_skill.sh call --tool hello --args-file ./examples/debug/hello.args.json --output json
bash ./scripts/debug_skill.sh validate
bash ./scripts/debug_skill.sh package
bash ./scripts/verify_skill.sh
```

## Invocation Arguments

- Use `ArgsJson` or `--args-json` for small payloads.
- Store large or heavily escaped payloads in JSON files and use `ArgsFile` or `--args-file`.
- Use only tool names confirmed by `list-tools`; never guess an entry name.
- Enable `EnableHostResult` or `--enable-host-result` only when explicitly testing the `host_result` bridge.

Example argument file:

```json
{
  "name": "ai-debug"
}
```

## Output Modes

- `pretty`: default human-readable diagnostics for interactive troubleshooting.
- `json`: complete structured output for exact field assertions and automation.
- `content`: tool content only, for validating final user-visible output.

Use `json` whenever evaluating return fields, error kinds, or context ownership. Never infer an internal structure from `pretty` output.

## Troubleshooting

### Download or Checksum Failure

Confirm that the `LuaSkills/luaskills-debug` Release pinned by `.luaskills-version` contains the exact current-platform archive and that `luaskills-debug-checksums.txt` lists it. Never skip checksum verification. Remove `.luaskills-debug/` and use a forced rebuild when a fresh download is required.

### `inspect` Failure

Read the exact `skill.yaml`, entry file, and synchronization paths reported by the error before changing the manifest. Do not add speculative optional-field fallbacks to bypass the failure.

### Missing `list-tools` Entry

Check `skill.yaml.entries[].name`, `lua_entry`, and the physical file, then rerun `inspect`. Confirm the canonical tool name from debugger output.

### Invalid `call` Arguments

Read `skill.yaml.entries[].parameters` and the target Lua entry. Confirm required fields, types, and return contracts. Move complex payloads to JSON files so shell escaping cannot alter them.

### Unavailable Dependency

Distinguish Lua runtime packages, skill-owned `dependencies.yaml`, and host-managed capabilities. Repair only the layer identified by the debugger's real error, and never hard-code dependency paths into source code.

Since LuaSkills 0.7.2, a `required: false` dependency that cannot be made ready only logs a warning, so the skill still loads; a required one fails the whole skill. When a bundled native payload reports as missing, build the host payload with `scripts/build_native.py`.

### `validate` or `package` Failure

Read the exact issue code and path. A bundled payload declared in `dependencies.yaml` that is missing or outside the package entries always fails; build the payload or move it under `native/`, and never delete the declaration to pass. Other top-level entries ship only when added with `--include <name>`.

When a `github_release` download is slow or rate-limited, measure mirrors with `probe-mirrors`, then pass `--github-mirror <id|url>` and `--github-token-env <NAME>` (`-GithubMirror`, `-GithubTokenEnv` on Windows). Pass the name of an environment variable that holds the token, never the token itself.

## Pre-Release Closure

After `verify_skill` or `package` succeeds, inspect `dist/` and require:

- With the `standard` layout: `<skill-id>-v<version>-skill.zip` and `<skill-id>-v<version>-checksums.txt`.
- With the `platform` layout: one `<skill-id>-v<version>-<platform>-skill.zip` per system with bundled payloads, each carrying only that system's libraries, the package index `<skill-id>-v<version>-packages.json`, the checksums file, and the all-systems `<skill-id>-v<version>-skill.zip` unless it was omitted with `--no-universal`.
- Exactly one `<skill-id>/` top-level directory in every zip.
- No AI prompts, downloaded debugger files, Actions, scripts, tests, or caches in any zip.
- `.luaskills-debug/` reported as ignored by `git status --short --ignored`.

Choose `standard` for a skill without native libraries and `platform` for a skill with large native libraries for several systems; the release workflow reads the GitHub repository variable `LUASKILLS_PACKAGE_LAYOUT`.

Finally, commit every intended change and invoke the release script with the version declared by `skill.yaml`. The script reruns verification before pushing the exact tag. The Release Action then runs `LuaSkills/luaskills-debug` with `expect-tag`, which validates, packages, and fails when the tag differs from `skill.yaml.version`, and uploads every asset to the GitHub Release.
