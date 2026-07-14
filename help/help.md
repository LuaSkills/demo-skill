# LuaSkills Demo Skill

This `LuaSkills/demo-skill` repository is a complete demo package for LuaSkills.

It is designed to validate:

- package installation from GitHub release assets
- package updates through new release versions
- skill uninstall behavior
- skill-local dependency installation
- host overflow handling with a skill-local template hint

Available workflows:

- `demo-status`
  - inspect the active skill instance and request context
- `rg-dependency`
  - inspect the optional local `rg` dependency path
- `overflow-demo`
- verify paged host output and skill-local overflow templates
- `node-runtime-demo`
- invoke a pinned managed Node.js ESM handler with a pnpm-locked dependency
