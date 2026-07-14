[English](README.md) | [简体中文](README.zh-CN.md)

# LuaSkills 可 Fork 开发模板

这是一个可直接 Fork 的完整 LuaSkill 仓库模板。它提供正式 skill 示例、AI 开发技能、经过校验的官方 `luaskills-debug` 环境拉取、真实引擎调用、本地验证打包和 GitHub Actions 发布流程。

当前模板对齐的 LuaSkills 正式版本是 **v0.5.2**，[`.luaskills-version`](.luaskills-version) 是调试器与文档的唯一版本基线。当前示例 skill 版本为 `0.2.0`；两种版本用途不同，不要求保持一致。

## Fork 后直接交给 AI

Fork 并克隆仓库后，把下面这句话交给支持 Skill 文件的 AI：

```text
Read and strictly follow .agents/skills/luaskills-development/SKILL.md. Develop, debug, validate, review, and package this LuaSkill from my requirements.
```

AI Skill 要求先根据源码确认清单、入口、参数和调用链，再进行实现。它使用正式调试器，并禁止用候选字段或多路径 fallback 掩盖不确定性。详细说明位于：

- `.agents/skills/luaskills-development/references/ai-debugging.md`
- `.agents/skills/luaskills-development/references/review-loop.md`

## 一键准备调试环境

Windows：

```powershell
.\scripts\setup_debug.ps1
```

Linux/macOS：

```bash
bash ./scripts/setup_debug.sh
```

初始化脚本会根据操作系统与 CPU 架构选择官方 Release 资产：

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

初始化还会下载 v0.5.2 标签下的官方 `fetch_managed_runtimes.*`，验证固定 SHA-256 后才执行。上游脚本使用 Node.js 官方 `SHASUMS256.txt` 和 npm integrity 元数据校验 Node.js 与 pnpm。仅检查调试器本体时可跳过两类运行时：

```powershell
.\scripts\setup_debug.ps1 -SkipRuntimeSetup -SkipManagedNodeSetup
```

```bash
bash ./scripts/setup_debug.sh --skip-runtime-setup --skip-managed-node-setup
```

## 调试当前 Skill

调试封装使用与正式宿主相同的加载和调用链路。它只把发布白名单源码暂存到 `.luaskills-debug/source/<skill-id>/`，再同步到隔离的 runtime root；`.git/`、下载工具、AI 提示、测试和构建脚本不会被递归复制到运行环境。

每条调试命令都通过仓库级互斥锁串行化环境初始化、白名单暂存、同步与调用。多个 AI 任务或终端可以并发发起命令，而不会互相删除暂存文件。

Windows：

```powershell
.\scripts\debug_skill.ps1 -Command inspect
.\scripts\debug_skill.ps1 -Command list-tools
.\scripts\debug_skill.ps1 -Command call -Tool demo-status -ArgsFile .\examples\debug\demo-status.args.json
.\scripts\debug_skill.ps1 -Command call -Tool rg-check -ArgsFile .\examples\debug\rg-check.args.json -Output json
.\scripts\debug_skill.ps1 -Command call -Tool overflow-demo -ArgsFile .\examples\debug\overflow-demo.args.json -Output content
.\scripts\debug_skill.ps1 -Command call -Tool node-runtime-demo -ArgsFile .\examples\debug\node-runtime-demo.args.json -Output json
```

Linux/macOS：

```bash
bash ./scripts/debug_skill.sh inspect
bash ./scripts/debug_skill.sh list-tools
bash ./scripts/debug_skill.sh call --tool demo-status --args-file ./examples/debug/demo-status.args.json
bash ./scripts/debug_skill.sh call --tool rg-check --args-file ./examples/debug/rg-check.args.json --output json
bash ./scripts/debug_skill.sh call --tool overflow-demo --args-file ./examples/debug/overflow-demo.args.json --output content
bash ./scripts/debug_skill.sh call --tool node-runtime-demo --args-file ./examples/debug/node-runtime-demo.args.json --output json
```

可用命令：

- `sync`：把暂存 skill 同步到调试 runtime。
- `inspect`：校验并显示清单、skill ID、入口与引擎加载结果。
- `list-tools`：列出真实可调用的本地与 canonical 工具名。
- `call`：通过正式引擎调用一个工具。

## 一键验证并生成发布包

Windows：

```powershell
.\scripts\verify_skill.ps1
```

Linux/macOS：

```bash
bash ./scripts/verify_skill.sh
```

该命令依次执行：

1. 打包过滤、路径穿越、符号链接与发布版本负向测试。
2. 严格仓库结构与清单校验。
3. 官方调试器 `inspect`。
4. 官方调试器 `list-tools`。
5. 使用参数示例真实调用四个工具；`node-runtime-demo` 会创建锁定的 pnpm 环境并执行两次 ESM Worker 调用。
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
README.zh-CN.md
LICENSE
runtime/
node/
python/
help/
overflow_templates/
resources/
licenses/
```

`.agents/`、`.github/`、`scripts/`、`tests/`、`.luaskills-debug/`、`dist/`、`node_modules/`、`.pnpm-store/`、Python 缓存、其他本地产物和符号链接不会进入正式包。

## GitHub Actions

仓库包含两个可直接复用的工作流：

- **Validate and Package LuaSkill**：Pull Request 或手动触发时下载调试器与运行时，加载 skill、枚举工具、执行真实调用、打包并上传 `<仓库名>-verified-package`。
- **Release LuaSkill**：推送 `v*` 标签时重新执行相同的真实调试流程，创建 GitHub Release，并且只上传正式 zip 和 checksum。

发布脚本会拒绝脏工作区，要求参数与 `skill.yaml.version` 完全一致，并在创建、推送标签前重新执行完整验证。当前版本为 `0.2.0`：

```powershell
.\scripts\tag_release.ps1 0.2.0
```

```bash
bash ./scripts/tag_release.sh 0.2.0
```

## Fork 后需要替换的内容

1. 将仓库名改为最终 `skill_id`，只使用小写字母、数字和单连字符。
2. 替换 `skill.yaml` 中的显示名称、版本、入口、参数和帮助引用。
3. 替换 `runtime/`、`node/`、`python/`、`help/`、`overflow_templates/`、`resources/` 与 `licenses/` 中的示例内容。
4. 在 `dependencies.yaml` 中声明真实依赖；校验器不要求保留示例 `rg`。不需要 Node.js 时应同时删除 `node_runtime`、`node/` 与对应入口。
5. 替换两份 README 和帮助文档中剩余的 `demo-skill` 示例描述。
6. 运行 `verify_skill`，完成连续五轮零问题审核，提交全部目标文件，然后运行发布脚本。

仓库物理目录名决定正式 `skill_id`。仅修改 `skill.yaml.name` 不会改变安装标识。

## 当前示例能力

- `demo-status`：返回稳定的 skill 版本、目录、请求上下文与生命周期诊断。
- `rg-check`：演示 skill 私有可选工具依赖及 `vulcan.deps.tools_path`。
- `overflow-demo`：演示分页输出与 skill 私有 overflow template。
- `node-runtime-demo`：演示受管 Node.js `24.18.0`、pnpm 锁定依赖、ESM handler、环境创建、Worker 复用与真实调用诊断。

## 发布前五轮审核

实现与真实流程测试通过后，AI 必须循环审核代码、清单、下载校验、跨平台脚本、打包白名单、Action 与文档。发现任何问题都必须立即修复、完整复测并把连续通过计数清零。只有连续五次完整审核均未发现问题，才能结束或发布。

以 LuaSkills v0.5.2 官方文档作为协议依据：

- [Lua Skill Development Manual](https://github.com/LuaSkills/luaskills/blob/v0.5.2/docs/skill-development.md)
- [Lua Skill 开发手册（简体中文）](https://github.com/LuaSkills/luaskills/blob/v0.5.2/docs/zh-CN/skill-development.md)
- [LuaSkills v0.5.2 Release](https://github.com/LuaSkills/luaskills/releases/tag/v0.5.2)
