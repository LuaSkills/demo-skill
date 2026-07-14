# Managed Node.js Runtime Demo

`node-runtime-demo` demonstrates the LuaSkills v0.5.2 managed Node.js runtime contract.

It uses the exact versions declared in `dependencies.yaml`:

- Node.js `24.18.0`
- pnpm `11.11.0`
- `is-odd` `3.0.1`, locked by `node/pnpm-lock.yaml`

The Lua entry calls `vulcan.runtime.node.status()`, invokes `node/echo.mjs` twice through `vulcan.runtime.node.invoke(...)`, validates the declared dependency, and returns the before/after runtime state together with both invocation results.
