# LuaSkills 可 Fork 开发模板

这是一个可直接 Fork 的完整 LuaSkill 仓库模板。它同时提供正式 skill 示例、AI 开发技能、官方 `luaskills-debug` 调试环境拉取、真实引擎调用、本地验证打包和 GitHub Actions 发布流程。

当前模板对齐的 LuaSkills 正式版本是 **v0.5.2**，唯一版本基线保存在 [`.luaskills-version`](.luaskills-version)。当前示例 skill 版本为 `0.2.0`；两种版本含义不同，不应强行保持相同。

## Fork 后直接交给 AI

Fork 并克隆仓库后，把下面这句话交给支持技能文件的 AI：

```text
请读取并严格执行 .agents/skills/luaskills-development/SKILL.md，基于我的需求开发、调试、验证并打包这个 LuaSkill。
```

AI 技能会要求先查清真实清单、入口、参数和调用链，再使用正式调试器开发；不会通过候选字段或多路径 fallback 掩盖不确定性。详细调用手册位于：

- `.agents/skills/luaskills-development/references/ai-debugging.md`

## 一键准备调试环境

Windows：

```powershell
.\scripts\setup_debug.ps1
```

Linux / macOS：

```bash
bash ./scripts/setup_debug.sh
```

脚本会按操作系统和 CPU 架构下载官方 Release 中对应的：

```text
luaskills-debug-tool-{platform}.tar.gz
luaskills-debug-tool-{platform}.tar.gz.sha256
```

完成 checksum 校验后，调试器、Lua runtime packages、Node.js `24.18.0` 与 pnpm `11.11.0` 会保存到：

```text
.luaskills-debug/
```

该目录已被 Git 整体忽略，不会进入提交或正式 skill 包。需要重新下载时使用：

```powershell
.\scripts\setup_debug.ps1 -Force
```

```bash
bash ./scripts/setup_debug.sh --force
```

默认初始化还会下载 v0.5.2 标签下的官方 `fetch_managed_runtimes.*`，验证固定 SHA-256 后才执行；该脚本随后按照 Node.js 官方 `SHASUMS256.txt` 与 npm integrity 校验运行时资产。仅调试普通 Lua 入口时，可以同时跳过两类运行时：

```powershell
.\scripts\setup_debug.ps1 -SkipRuntimeSetup -SkipManagedNodeSetup
```

```bash
bash ./scripts/setup_debug.sh --skip-runtime-setup --skip-managed-node-setup
```

## 调试当前 skill

调试器使用与正式宿主相同的加载和调用链路。调用封装会先按正式包白名单把源码暂存到 `.luaskills-debug/source/<skill-id>/`，再同步到隔离的 runtime root；因此 `.git/`、调试器本身、AI 提示和构建脚本不会被递归复制进运行环境。

同一仓库中的调试命令会覆盖“环境初始化、白名单暂存、同步、调用”整个临界区进行串行化，避免多个 AI 任务或终端并发调用时互相删除暂存文件。

Windows：

```powershell
.\scripts\debug_skill.ps1 -Command inspect
.\scripts\debug_skill.ps1 -Command list-tools
.\scripts\debug_skill.ps1 -Command call -Tool demo-status -ArgsFile .\examples\debug\demo-status.args.json
.\scripts\debug_skill.ps1 -Command call -Tool overflow-demo -ArgsFile .\examples\debug\overflow-demo.args.json -Output content
.\scripts\debug_skill.ps1 -Command call -Tool node-runtime-demo -ArgsFile .\examples\debug\node-runtime-demo.args.json -Output json
```

Linux / macOS：

```bash
bash ./scripts/debug_skill.sh inspect
bash ./scripts/debug_skill.sh list-tools
bash ./scripts/debug_skill.sh call --tool demo-status --args-file ./examples/debug/demo-status.args.json
bash ./scripts/debug_skill.sh call --tool overflow-demo --args-file ./examples/debug/overflow-demo.args.json --output content
bash ./scripts/debug_skill.sh call --tool node-runtime-demo --args-file ./examples/debug/node-runtime-demo.args.json --output json
```

可用命令：

- `sync`：只同步源 skill 到调试 runtime。
- `inspect`：校验并显示清单、skill id、入口与加载结果。
- `list-tools`：列出真实可调用工具名。
- `call`：通过正式引擎调用一个工具。

## 一键验证并生成发布包

Windows：

```powershell
.\scripts\verify_skill.ps1
```

Linux / macOS：

```bash
bash ./scripts/verify_skill.sh
```

该命令依次执行：

1. 打包过滤、路径穿越与符号链接负向测试。
2. 严格仓库结构与清单校验。
3. 官方调试器 `inspect`。
4. 官方调试器 `list-tools`。
5. 使用参数示例逐个真实调用四个工具，其中 `node-runtime-demo` 会触发 pnpm 环境创建与两次 ESM Worker 调用。
6. 确定性发布包构建。

生成结果位于 `dist/`：

```text
<skill-id>-v<version>-skill.zip
<skill-id>-v<version>-checksums.txt
```

zip 只有一个 `<skill-id>/` 顶层目录，并且只会从以下白名单收集存在的文件：

```text
skill.yaml
dependencies.yaml
README.md
LICENSE
runtime/
node/
python/
help/
overflow_templates/
resources/
licenses/
```

`.agents/`、`.github/`、`scripts/`、`.luaskills-debug/`、`dist/`、`node_modules/`、`.pnpm-store/`、Python 缓存与其他本地运行产物不会进入正式包；白名单内的符号链接也会被拒绝。

## GitHub Actions

仓库包含两个可直接复用的工作流：

- **Validate and Package LuaSkill**：Pull Request 或手动触发时实际下载调试器与运行时，执行加载、枚举、Node 工具调用和打包，并上传 `<仓库名>-verified-package` Artifact。适合在发布前直接从 Action 获取已验证包结构。
- **Release LuaSkill**：推送 `v*` 标签时重新执行同一套真实调试流程，随后创建 GitHub Release，只上传正式 zip 和 checksum。

发布脚本会先拒绝脏工作区、校验参数与 `skill.yaml.version` 完全一致，并重新执行完整验证；全部成功后才创建和推送标签。例如当前版本为 `0.2.0`：

```powershell
.\scripts\tag_release.ps1 0.2.0
```

```bash
bash ./scripts/tag_release.sh 0.2.0
```

## Fork 后需要替换的内容

1. 将仓库名改为最终 `skill_id`，格式为小写字母、数字和单连字符。
2. 修改 `skill.yaml` 的显示名称、版本、入口、参数和帮助引用。
3. 替换 `runtime/`、`help/`、`overflow_templates/`、`resources/` 与 `licenses/` 中的示例内容。
4. 按真实依赖修改 `dependencies.yaml`；校验器不要求保留示例 `rg`。不需要 Node.js 时应同时删除 `node_runtime`、`node/` 与对应入口。
5. 删除 README 与帮助文档中剩余的 `demo-skill` 示例描述。
6. 使用 `verify_skill` 完成闭环后再推送发布标签。

仓库根目录名决定正式包的 `skill_id`。仅修改 `skill.yaml.name` 不会改变安装标识。

## 当前示例能力

- `demo-status`：返回 skill 版本、目录、请求上下文和稳定诊断信息。
- `rg-check`：演示 skill 私有可选工具依赖及 `vulcan.deps.tools_path`。
- `overflow-demo`：演示分页输出与 skill 私有 overflow template。
- `node-runtime-demo`：演示 Node.js `24.18.0`、pnpm 锁定依赖、ESM handler、环境创建、Worker 复用信息与真实工具调用。

## 发布前五轮审核

AI 完成实现和流程测试后，必须循环执行代码审核。每轮覆盖代码、清单、下载校验、跨平台脚本、打包白名单、Action 与文档；发现问题时立即修复、完整复测并把连续通过计数清零。只有连续 5 轮均未发现任何问题，才能结束任务或发布。

LuaSkills v0.5.2 的正式 Skill API、托管运行时与发布规则以官方文档为准：

- [Lua Skill 开发手册（中文）](https://github.com/LuaSkills/luaskills/blob/v0.5.2/docs/zh-CN/skill-development.md)
- [Lua Skill Development Manual](https://github.com/LuaSkills/luaskills/blob/v0.5.2/docs/skill-development.md)
- [LuaSkills v0.5.2 Release](https://github.com/LuaSkills/luaskills/releases/tag/v0.5.2)
