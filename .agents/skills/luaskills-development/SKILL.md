---
name: luaskills-development
description: 基于官方 LuaSkills 调试器和托管 Node.js Runtime 开发、检查、调用、验证、审核、打包并通过 GitHub Actions 发布 LuaSkill。用户要求新建或修改 skill、拉取 luaskills-debug、调试 Lua/Node 入口、循环代码审核、生成发布包或发布 GitHub Release 时使用。
---

# LuaSkills 开发

## 事实基线

1. 读取仓库根目录的 `.luaskills-version`，将其作为调试器与文档的唯一 LuaSkills 版本基线。
2. 修改前读取 `skill.yaml`、`dependencies.yaml`、目标 `runtime/*.lua`、对应帮助文件和调用方；禁止猜测字段、入口或返回结构。
3. 需要升级 LuaSkills 时，先核对 `LuaSkills/luaskills` 最新正式 Release 的资产名称，再同时更新 `.luaskills-version`、示例和本文档引用。
4. 不要把 `.luaskills-debug/`、`dist/` 或任何运行时生成目录加入 Git。

## 开发闭环

1. 运行 `scripts/setup_debug.ps1` 或 `scripts/setup_debug.sh`，下载并校验官方 `luaskills-debug-tool-{platform}.tar.gz`、Lua runtime packages、Node.js 与 pnpm，全部保存到 `.luaskills-debug/`。
2. 修改 `skill.yaml`、`dependencies.yaml`、`runtime/`、`help/`、`overflow_templates/`、`resources/` 与 `licenses/` 中确实属于正式 skill 的内容。
3. 所有新增代码必须使用英文第一行、中文第二行的双语注释；类、函数、接口、参数、返回值和关键逻辑均需覆盖。
4. 运行调试器检查并调用真实入口。首次调试或排查调用问题时，完整读取 [AI 调用调试说明书](references/ai-debugging.md)。
5. 运行 `scripts/verify_skill.ps1` 或 `scripts/verify_skill.sh`，完成负向安全测试、结构校验、正式引擎加载、工具枚举、四个示例工具真实调用与发布包生成。
6. 检查 `dist/<skill-id>-v<version>-skill.zip` 仅含正式运行文件，并确认 zip 顶层目录、仓库名和 `skill_id` 一致。
7. 完整读取并执行 [五轮连续审核协议](references/review-loop.md)。发现问题时自动修复、完整复测并把连续通过计数清零；只有连续 5 轮零问题才可继续。
8. 发布前更新 `skill.yaml.version`，提交后推送匹配的 `v<version>` 标签；Release Action 会重新校验并上传 zip 与 checksum。

## 调试命令

Windows：

```powershell
.\scripts\debug_skill.ps1 -Command inspect
.\scripts\debug_skill.ps1 -Command list-tools
.\scripts\debug_skill.ps1 -Command call -Tool demo-status -ArgsFile .\examples\debug\demo-status.args.json
.\scripts\debug_skill.ps1 -Command call -Tool node-runtime-demo -ArgsFile .\examples\debug\node-runtime-demo.args.json -Output json
```

Linux/macOS：

```bash
bash ./scripts/debug_skill.sh inspect
bash ./scripts/debug_skill.sh list-tools
bash ./scripts/debug_skill.sh call --tool demo-status --args-file ./examples/debug/demo-status.args.json
bash ./scripts/debug_skill.sh call --tool node-runtime-demo --args-file ./examples/debug/node-runtime-demo.args.json --output json
```

## 发布约束

- `skill.yaml.version` 是发布版本唯一来源。
- Git 标签必须严格等于 `v<skill.yaml.version>`。
- 发布包只允许包含 `skill.yaml`、`dependencies.yaml`、`README.md`、`LICENSE`、`runtime/`、`node/`、`python/`、`help/`、`overflow_templates/`、`resources/` 与 `licenses/` 中存在的文件。
- `.agents/`、`.github/`、`scripts/`、`.luaskills-debug/`、`node_modules/`、`.pnpm-store/`、测试缓存、本地构建产物与符号链接不得进入正式 skill zip。
- 不要为了通过调试编写候选字段、多路径 fallback 或模糊兼容逻辑；无法确认事实链时停止并说明缺失证据。
