# package-config

LuaSkills 0.5.5 configuration belongs to the whole skill package. The top-level `config` block in `skill.yaml` demonstrates `string`, `integer`, `float`, `enum`, and `boolean` declarations, constraints, defaults, sensitive values, and host-facing UI metadata.

`runtime/config_validator.lua` demonstrates isolated cross-field validation: the example rejects a local provider with a temperature above `1.0`.

The host must provide one absolute, writable, user-level `skill_config_root`. Normal skill values are persisted in:

```text
<skill_config_root>/skills/config.json
```

`resources/skill-config.example.json` shows the only supported versioned file shape. Its required sensitive `api_token` is intentionally omitted. Do not copy secrets into repository files; use an authorized host `runtime-config` operation to set them.

When configuration is incomplete, use the host `runtime-config` tool with `action=describe` and skill id `demo-skill`. If mutation is authorized, submit available values in one `set` batch. Package Lua code is isolated to its own configuration namespace through `vulcan.config.*`; cross-package administration belongs to the host.
