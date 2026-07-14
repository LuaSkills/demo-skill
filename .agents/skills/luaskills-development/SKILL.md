---
name: luaskills-development
description: Develop, inspect, invoke, validate, review, package, and release LuaSkills with the official LuaSkills debugger and managed Node.js runtime. Use when creating or modifying a skill, downloading luaskills-debug, debugging Lua or Node.js entries, running iterative code reviews, generating release packages, or publishing a GitHub Release.
---

# LuaSkills Development

## Fact Baseline

1. Read `.luaskills-version` from the repository root and treat it as the single LuaSkills version baseline for debugger assets and documentation.
2. Before editing, read `skill.yaml`, `dependencies.yaml`, the target `runtime/*.lua` file, its help file, and every relevant caller. Never guess fields, entry names, or return structures.
3. Before upgrading LuaSkills, verify the latest stable `LuaSkills/luaskills` Release and its exact asset names, then update `.luaskills-version`, examples, and documentation references together.
4. Never commit `.luaskills-debug/`, `dist/`, or runtime-generated directories.

## Development Loop

1. Run `scripts/setup_debug.ps1` or `scripts/setup_debug.sh` to download and verify the official `luaskills-debug-tool-{platform}.tar.gz`, Lua runtime packages, Node.js, and pnpm. Keep every downloaded artifact under `.luaskills-debug/`.
2. Modify only formal skill content in `skill.yaml`, `dependencies.yaml`, `runtime/`, `node/`, `python/`, `help/`, `overflow_templates/`, `resources/`, and `licenses/`.
3. Write every generated code comment in bilingual pairs: English on the first line and Chinese on the second line. Cover every class, function, method, interface, parameter, return value, variable definition, and non-obvious design decision.
4. Inspect and invoke real entries through the official debugger. Read [AI Invocation Debugging Guide](references/ai-debugging.md) completely before first-time debugging or invocation troubleshooting.
5. Run `scripts/verify_skill.ps1` or `scripts/verify_skill.sh` to execute negative safety tests, strict validation, real engine loading, tool enumeration, all example tool calls, and release packaging.
6. Inspect `dist/<skill-id>-v<version>-skill.zip`. Confirm it contains only formal runtime files and that its single top-level directory matches the repository-derived `skill_id`.
7. Read and execute the [Five-Consecutive-Pass Review Protocol](references/review-loop.md) completely. If any issue appears, fix it, rerun the full flow, reset the consecutive-pass counter to zero, and continue until five consecutive reviews find no issues.
8. Before release, update `skill.yaml.version`, commit all intended changes, and run `scripts/tag_release.ps1` or `scripts/tag_release.sh` with the matching version. The release script rejects a dirty worktree, reruns verification, creates the exact `v<version>` tag, and pushes it for the Release Action.

## Debug Commands

Windows:

```powershell
.\scripts\debug_skill.ps1 -Command inspect
.\scripts\debug_skill.ps1 -Command list-tools
.\scripts\debug_skill.ps1 -Command call -Tool demo-status -ArgsFile .\examples\debug\demo-status.args.json
.\scripts\debug_skill.ps1 -Command call -Tool node-runtime-demo -ArgsFile .\examples\debug\node-runtime-demo.args.json -Output json
```

Linux/macOS:

```bash
bash ./scripts/debug_skill.sh inspect
bash ./scripts/debug_skill.sh list-tools
bash ./scripts/debug_skill.sh call --tool demo-status --args-file ./examples/debug/demo-status.args.json
bash ./scripts/debug_skill.sh call --tool node-runtime-demo --args-file ./examples/debug/node-runtime-demo.args.json --output json
```

## Release Constraints

- Treat `skill.yaml.version` as the only release version source.
- Require the Git tag to equal `v<skill.yaml.version>` exactly.
- Allow release files only from `skill.yaml`, `dependencies.yaml`, `README.md`, `README.zh-CN.md`, `LICENSE`, `runtime/`, `node/`, `python/`, `help/`, `overflow_templates/`, `resources/`, and `licenses/` when present.
- Exclude `.agents/`, `.github/`, `scripts/`, `.luaskills-debug/`, `node_modules/`, `.pnpm-store/`, test caches, local build artifacts, and symbolic links from the formal skill zip.
- Never hide missing facts with candidate fields, speculative multi-path fallbacks, or fuzzy compatibility logic. Stop and report the verified path and missing evidence when the fact chain cannot be established.
