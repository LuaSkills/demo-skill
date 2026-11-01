---
name: luaskills-development
description: Develop, inspect, invoke, validate, review, package, and release LuaSkills with the official LuaSkills debugger and managed Node.js runtime. Use when creating or modifying a skill, downloading luaskills-debug, debugging Lua or Node.js entries, running iterative code reviews, generating release packages, or publishing a GitHub Release.
---

# LuaSkills Development

## Fact Baseline

1. Read `.luaskills-version` from the repository root. It holds the `LuaSkills/luaskills-debug` release tag, whose major and minor version follow the embedded LuaSkills runtime, and it is the single version baseline for debugger assets and documentation.
2. Before editing, read `skill.yaml`, `dependencies.yaml`, the target `runtime/*.lua` file, its help file, and every relevant caller. Never guess fields, entry names, or return structures.
3. Before upgrading, verify the latest `LuaSkills/luaskills-debug` Release and its exact asset names (`luaskills-debug-tool-{platform}.tar.gz`, `luaskills-debug-checksums.txt`), then update `.luaskills-version`, the `LuaSkills/luaskills-debug@<tag>` action reference in `.github/workflows/release.yml`, examples, and documentation references together.
4. Never commit `.luaskills-debug/`, `dist/`, or runtime-generated directories.

## Development Loop

1. Run `scripts/setup_debug.ps1` or `scripts/setup_debug.sh` to download `luaskills-debug-tool-{platform}.tar.gz`, verify it against `luaskills-debug-checksums.txt`, and install Lua runtime packages, Node.js, and pnpm. Keep every downloaded artifact under `.luaskills-debug/`.
2. Modify only formal skill content in `skill.yaml`, `dependencies.yaml`, `runtime/`, `node/`, `python/`, `native/`, `help/`, `overflow_templates/`, `resources/`, `licenses/`, and `schemas/`. Build bundled native libraries with `scripts/build_native.py`; never commit the built binaries.
3. Write every generated code comment in bilingual pairs: English on the first line and Chinese on the second line. Cover every class, function, method, interface, parameter, return value, variable definition, and non-obvious design decision.
4. Inspect and invoke real entries through `scripts/debug_skill.ps1` or `scripts/debug_skill.sh`. Read [AI Invocation Debugging Guide](references/ai-debugging.md) completely before first-time debugging or invocation troubleshooting.
5. Run `scripts/verify_skill.ps1` or `scripts/verify_skill.sh` to execute the Python unit tests, real engine loading, tool enumeration, all example tool calls, `validate`, and `package`. In the demo repository, verify skips `validate` and `package` because only the host's native library is built locally; the release workflow runs them after all five native builds.
6. Choose the release layout: a skill without native libraries uses `standard`; a skill with large native libraries for several systems uses `platform`, selected by the GitHub repository variable `LUASKILLS_PACKAGE_LAYOUT`. Preview it with `debug_skill package --layout platform` (`-Layout platform` on Windows).
7. Inspect the assets in `dist/`. Confirm every zip contains only formal package entries and that its single top-level directory matches the repository-derived `skill_id`.
8. Read and execute the [Five-Consecutive-Pass Review Protocol](references/review-loop.md) completely. If any issue appears, fix it, rerun the full flow, reset the consecutive-pass counter to zero, and continue until five consecutive reviews find no issues.
9. Before release, update `skill.yaml.version`, commit all intended changes, and run `scripts/tag_release.ps1` or `scripts/tag_release.sh` with the matching version. The release script rejects a dirty worktree, reruns verification, creates the exact `v<version>` tag, and pushes it for the Release Action.

## Debug Commands

Windows:

```powershell
.\scripts\debug_skill.ps1 -Command inspect
.\scripts\debug_skill.ps1 -Command list-tools
.\scripts\debug_skill.ps1 -Command call -Tool hello -ArgsFile .\examples\debug\hello.args.json -Output json
.\scripts\debug_skill.ps1 -Command validate
.\scripts\debug_skill.ps1 -Command package -Layout standard -OutDir dist
```

Linux/macOS:

```bash
bash ./scripts/debug_skill.sh inspect
bash ./scripts/debug_skill.sh list-tools
bash ./scripts/debug_skill.sh call --tool hello --args-file ./examples/debug/hello.args.json --output json
bash ./scripts/debug_skill.sh validate
bash ./scripts/debug_skill.sh package --layout standard
```

## Release Constraints

- Treat `skill.yaml.version` as the only release version source.
- Require the Git tag to equal `v<skill.yaml.version>` exactly; the release action enforces it with `expect-tag`.
- `luaskills-debug validate` and `package` always fail when a bundled payload declared in `dependencies.yaml` is missing or outside the package entries. Never work around that failure by removing declarations.
- Packaging rules come from the LuaSkills runtime (`luaskills::package`). Package entries are `skill.yaml`, `dependencies.yaml`, `README.md`, `README.zh-CN.md`, `LICENSE`, `THIRD_PARTY_NOTICES.md`, `THIRD_PARTY_LICENSES.md`, `runtime/`, `node/`, `python/`, `native/`, `help/`, `overflow_templates/`, `resources/`, `licenses/`, and `schemas/` when present; `--include <name>` adds another top-level entry.
- Symbolic links and generated folders never enter a package. `.agents/`, `.github/`, `scripts/`, `tests/`, `examples/`, `.luaskills-debug/`, and `dist/` stay out.
- The `standard` layout writes `<id>-v<version>-skill.zip` and `<id>-v<version>-checksums.txt`. The `platform` layout adds one `<id>-v<version>-<platform>-skill.zip` per system with bundled payloads and the package index `<id>-v<version>-packages.json`, and keeps the all-systems zip unless `include-universal: false` or `--no-universal` is set.
- LuaSkills Hub imports skills only from GitHub Releases and binds a skill to the first repository it is published from. It accepts at most 100 MiB per package, 600 MiB per version, and 1 GiB expanded.
- Never hide missing facts with candidate fields, speculative multi-path fallbacks, or fuzzy compatibility logic. Stop and report the verified path and missing evidence when the fact chain cannot be established.
