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

Validate the repository through the same `load_from_roots -> call_skill` path used by the formal host. The repository wrapper first stages the release whitelist under `.luaskills-debug/source/<skill-id>`. The official debugger then synchronizes it to `.luaskills-debug/runtime/skills/<skill-id>` and loads it from the isolated runtime root. Never pass the repository root directly to the debugger, and never replace formal invocation with direct Lua file execution.

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

1. Read the pinned version from `.luaskills-version`.
2. Select the exact stable Release asset for the current operating system and CPU architecture.
3. Download both the `.tar.gz` archive and its `.sha256` sidecar.
4. Verify SHA-256 before extraction.
5. Store the complete debugger workspace under the Git-ignored `.luaskills-debug/` directory.
6. Run the official `setup_runtime` flow to download matching Lua runtime packages.
7. Download the v0.5.2 managed-runtime fetcher, verify its pinned SHA-256 digest, and install Node.js `24.18.0` with pnpm `11.11.0`.

Use `-Force` or `--force` to rebuild the workspace. When only the debugger binary is needed, pass both `-SkipRuntimeSetup -SkipManagedNodeSetup` or `--skip-runtime-setup --skip-managed-node-setup`.

## Standard Debug Sequence

After changing an entry or manifest, follow this fixed sequence:

1. `inspect`: validate the manifest, physical directory binding, entry files, and formal engine loading.
2. `list-tools`: confirm public and canonical tool names.
3. `call`: invoke the target tool with real arguments. If `node_runtime` is declared, invoke the managed Node.js entry in practice.
4. `verify_skill`: run negative safety tests, strict validation, loading, enumeration, every example tool call, and package generation.

Every debug command rebuilds the whitelist stage while holding a repository-level lock. This keeps debugger input identical to the Action package, prevents recursive synchronization of `.git/` or `.luaskills-debug/`, and serializes concurrent commands from multiple agents or terminals.

Windows:

```powershell
.\scripts\debug_skill.ps1 -Command inspect
.\scripts\debug_skill.ps1 -Command list-tools
.\scripts\debug_skill.ps1 -Command call -Tool demo-status -ArgsFile .\examples\debug\demo-status.args.json
.\scripts\debug_skill.ps1 -Command call -Tool node-runtime-demo -ArgsFile .\examples\debug\node-runtime-demo.args.json -Output json
.\scripts\verify_skill.ps1
```

Linux/macOS:

```bash
bash ./scripts/debug_skill.sh inspect
bash ./scripts/debug_skill.sh list-tools
bash ./scripts/debug_skill.sh call --tool demo-status --args-file ./examples/debug/demo-status.args.json
bash ./scripts/debug_skill.sh call --tool node-runtime-demo --args-file ./examples/debug/node-runtime-demo.args.json --output json
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
  "name": "ai-debug",
  "include_context": true
}
```

## Output Modes

- `pretty`: default human-readable diagnostics for interactive troubleshooting.
- `json`: complete structured output for exact field assertions and automation.
- `content`: tool content only, for validating final user-visible output.

Use `json` whenever evaluating return fields, error kinds, or context ownership. Never infer an internal structure from `pretty` output.

## Troubleshooting

### Download or Checksum Failure

Confirm that the Release pinned by `.luaskills-version` contains the exact current-platform asset. Never skip checksum verification. Remove `.luaskills-debug/` and use a forced rebuild when a fresh download is required.

### `inspect` Failure

Read the exact `skill.yaml`, entry file, and synchronization paths reported by the error before changing the manifest. Do not add speculative optional-field fallbacks to bypass the failure.

### Missing `list-tools` Entry

Check `skill.yaml.entries[].name`, `lua_entry`, and the physical file, then rerun `inspect`. Confirm the canonical tool name from debugger output.

### Invalid `call` Arguments

Read `skill.yaml.entries[].parameters` and the target Lua entry. Confirm required fields, types, and return contracts. Move complex payloads to JSON files so shell escaping cannot alter them.

### Unavailable Dependency

Distinguish Lua runtime packages, skill-owned `dependencies.yaml`, and host-managed capabilities. Repair only the layer identified by the debugger's real error, and never hard-code dependency paths into source code.

## Pre-Release Closure

After `verify_skill` succeeds, inspect `dist/` and require:

- `<skill-id>-v<version>-skill.zip` as the package name.
- `<skill-id>-v<version>-checksums.txt` as the checksum filename.
- Exactly one `<skill-id>/` top-level directory in the zip.
- No AI prompts, downloaded debugger files, Actions, scripts, or caches in the zip.
- `.luaskills-debug/` reported as ignored by `git status --short --ignored`.

Finally, commit every intended change and invoke the release script with the version declared by `skill.yaml`. The script reruns the same validation and packaging flow before pushing the exact tag consumed by the Release Action.
