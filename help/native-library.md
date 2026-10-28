# native-library

This topic documents the `demo-native` FFI dependency, which ships its payload inside the skill package (`source.type: bundled`).

How the payload gets into the package:

- `native/demo_native.c` is the library source.
- `scripts/build_native.py` compiles it for the current host into `native/<platform>/<library>`.
- The release workflow builds all five declared platforms on native runners and packages them with `--require-bundled`, which fails when any declared payload is missing.
- No `sha256` is pinned in `dependencies.yaml`: the payload travels inside the skill zip, and the release checksum already covers every byte of that zip.

How LuaSkills installs it:

- The payload is copied from the skill directory into `vulcan.deps.ffi_path/demo-native/1.0.0/<platform>/lib/`, with no network access.
- An existing installation of the same version is reused; bump the dependency version when the library changes.
- The dependency is `required: false`. Since LuaSkills 0.7.2, when the current platform has no package entry, such as `windows-arm64`, or the payload file is missing, the runtime logs a warning and loads the skill without it; `native-demo` then reports `exists: false`.

Use `native-demo` to verify:

- the expected installed library path and whether it exists
- that LuaJIT `ffi.load` can open it
- the values returned by `demo_native_version()` and `demo_native_add(a, b)`
