[English](README.md) | [简体中文](README.zh-CN.md)

# LuaSkills 可 Fork 开发模板

这是一个可直接 Fork 的完整 LuaSkill 仓库模板。它提供正式 skill 示例、AI 开发技能、经过校验的官方 `luaskills-debug` 环境拉取、真实引擎调用、本地验证打包、按平台构建的内置原生库和 GitHub Actions 发布流程。

当前模板对齐的 LuaSkills 正式版本是 **v0.7.2**，[`.luaskills-version`](.luaskills-version) 是调试器与文档的唯一版本基线。技能包版本由 `skill.yaml` 声明；两种版本用途不同，不要求保持一致。

<!-- >>> demo-only -->
当前演示 skill 版本为 `0.3.1`。运行[模板清理脚本](#从最小模板开始)可删除全部演示，只保留一个最小的 `hello` 工具。
<!-- <<< demo-only -->

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

初始化还会下载 v0.7.2 标签下的官方 `fetch_managed_runtimes.*`，验证固定 SHA-256 后才执行。上游脚本使用 Node.js 官方 `SHASUMS256.txt` 和 npm integrity 元数据校验 Node.js 与 pnpm。仅检查调试器本体时可跳过两类运行时：

```powershell
.\scripts\setup_debug.ps1 -SkipRuntimeSetup -SkipManagedNodeSetup
```

```bash
bash ./scripts/setup_debug.sh --skip-runtime-setup --skip-managed-node-setup
```

v0.7.2 的 Linux 调试工具压缩包还在 `bin/luaskills-debug.asc` 附带分离式 OpenPGP 签名。初始化脚本只校验 SHA-256；如需同时校验签名，请导入 LuaSkills 发布密钥（LuaSkills 仓库同一标签下的 `scripts/release/release-gpg-public.asc`），然后执行：

```bash
gpg --verify .luaskills-debug/bin/luaskills-debug.asc .luaskills-debug/bin/luaskills-debug
```

## 调试当前 Skill

调试封装使用与正式宿主相同的加载和调用链路。它只把发布白名单源码暂存到 `.luaskills-debug/source/<skill-id>/`，再同步到隔离的 runtime root；`.git/`、下载工具、AI 提示、测试和构建脚本不会被递归复制到运行环境。由于 v0.7.2 调试包内的启动器只转发传统参数，封装脚本会直接调用 `.luaskills-debug/bin/luaskills-debug`。

每条调试命令都通过仓库级互斥锁串行化环境初始化、白名单暂存、同步与调用。多个 AI 任务或终端可以并发发起命令，而不会互相删除暂存文件。

Windows：

```powershell
.\scripts\debug_skill.ps1 -Command inspect
.\scripts\debug_skill.ps1 -Command list-tools
.\scripts\debug_skill.ps1 -Command call -Tool hello -ArgsFile .\examples\debug\hello.args.json -Output json
```

Linux/macOS：

```bash
bash ./scripts/debug_skill.sh inspect
bash ./scripts/debug_skill.sh list-tools
bash ./scripts/debug_skill.sh call --tool hello --args-file ./examples/debug/hello.args.json --output json
```

<!-- >>> demo-only -->
演示工具的调用方式相同：

```powershell
.\scripts\debug_skill.ps1 -Command call -Tool demo-status -ArgsFile .\examples\debug\demo-status.args.json
.\scripts\debug_skill.ps1 -Command call -Tool rg-check -ArgsFile .\examples\debug\rg-check.args.json -Output json
.\scripts\debug_skill.ps1 -Command call -Tool overflow-demo -ArgsFile .\examples\debug\overflow-demo.args.json -Output content
.\scripts\debug_skill.ps1 -Command call -Tool node-runtime-demo -ArgsFile .\examples\debug\node-runtime-demo.args.json -Output json
.\scripts\debug_skill.ps1 -Command call -Tool native-demo -ArgsFile .\examples\debug\native-demo.args.json -Output json
```

```bash
bash ./scripts/debug_skill.sh call --tool demo-status --args-file ./examples/debug/demo-status.args.json
bash ./scripts/debug_skill.sh call --tool rg-check --args-file ./examples/debug/rg-check.args.json --output json
bash ./scripts/debug_skill.sh call --tool overflow-demo --args-file ./examples/debug/overflow-demo.args.json --output content
bash ./scripts/debug_skill.sh call --tool node-runtime-demo --args-file ./examples/debug/node-runtime-demo.args.json --output json
bash ./scripts/debug_skill.sh call --tool native-demo --args-file ./examples/debug/native-demo.args.json --output json
```
<!-- <<< demo-only -->

可用命令：

- `sync`：把暂存 skill 同步到调试 runtime。
- `inspect`：校验并显示清单、skill ID、入口与引擎加载结果。
- `list-tools`：列出真实可调用的本地与 canonical 工具名。
- `call`：通过正式引擎调用一个工具。
- `probe-mirrors`：测量 GitHub 下载镜像，无需暂存 skill。

## 下载镜像与 GitHub 令牌

使用 `source.type: github_release` 声明的依赖由调试器在准备 skill 时下载。`sync`、`inspect`、`list-tools` 与 `call` 支持两个控制下载的选项：

- `--github-mirror <id|url>`（Windows 为 `-GithubMirror`）：通过内置镜像标识或镜像地址下载 Release 资产。v0.7.2 的内置标识为 `github`、`gh-proxy-com`、`ghfast-top`、`gh-llkk-cc`、`ghproxy-net`。
- `--github-token-env <NAME>`（Windows 为 `-GithubTokenEnv`）：从指定环境变量读取 GitHub 令牌。令牌只发送给 `api.github.com`，用于解除匿名 API 限流。这里传入的是变量名，绝不是令牌本身。

这两个选项不影响 `setup_debug` 下载调试器的方式，后者始终使用官方 Release 地址。

测量全部内置镜像，或比较指定镜像：

```powershell
.\scripts\debug_skill.ps1 -Command probe-mirrors
.\scripts\debug_skill.ps1 -Command probe-mirrors -GithubMirror ghfast-top, gh-proxy-com -Output json
```

```bash
bash ./scripts/debug_skill.sh probe-mirrors
bash ./scripts/debug_skill.sh probe-mirrors --github-mirror ghfast-top --github-mirror gh-proxy-com --output json
```

通过镜像加载 skill，并用从 GitHub CLI 取得的令牌认证 GitHub API 查询：

```powershell
$env:LUASKILLS_GITHUB_TOKEN = gh auth token
.\scripts\debug_skill.ps1 -Command inspect -GithubMirror ghfast-top -GithubTokenEnv LUASKILLS_GITHUB_TOKEN
```

```bash
export LUASKILLS_GITHUB_TOKEN="$(gh auth token)"
bash ./scripts/debug_skill.sh inspect --github-mirror ghfast-top --github-token-env LUASKILLS_GITHUB_TOKEN
```

已安装在 `.luaskills-debug/runtime/` 中的依赖会被复用，因此只有真正发生下载时这些选项才起作用，例如执行 `setup_debug -Force` 或 `--force` 之后。

<!-- >>> demo-only -->
## 内置原生库演示

`native-demo` 演示 skill 如何随包分发自己的原生库（`source.type: bundled`，LuaSkills 0.7.0 引入），并通过 LuaJIT FFI 调用它。安装内置载荷从不访问网络。

- `native/demo_native.c` 导出 `demo_native_version()` 与 `demo_native_add(a, b)`。
- `scripts/build_native.py` 为当前主机编译到 `native/<platform>/<library>`：`windows-x64` 为 `demo_native.dll`，`linux-x64` 与 `linux-arm64` 为 `libdemo_native.so`，`macos-x64` 与 `macos-arm64` 为 `libdemo_native.dylib`。设置了 `$CC` 时使用它，否则依次使用 `gcc`、`clang`、`cc` 中第一个可用的编译器，Windows 上还会回退到 MSVC `cl`。MinGW 构建静态链接 libgcc，MSVC 构建链接静态 CRT，macOS 构建在未设置 `MACOSX_DEPLOYMENT_TARGET` 时以 macOS 11.0 为目标。
- `dependencies.yaml` 声明 `demo-native` `1.0.0`，每个平台一个 `archive_type: raw` 包并导出 `lib/<library>`。这里不固定 `sha256`：载荷随 skill zip 分发，发布 checksum 已覆盖其全部字节。
- `runtime/native_demo.lua` 构造 `vulcan.deps.ffi_path/demo-native/1.0.0/<platform>/lib/<library>`，报告其是否存在；存在时用 `ffi.load` 加载并返回库版本与 `a + b`。

调试前先构建当前主机的库：

```powershell
python .\scripts\build_native.py
```

```bash
python3 ./scripts/build_native.py
```

构建产物命中 `.gitignore` 中的 `*.dll`、`*.so` 与 `*.dylib` 规则，因此不会进入提交；但 `native/` 目录属于打包白名单，因此会进入 skill zip。

该依赖声明了 `required: false`。自 LuaSkills 0.7.2 起，无法就绪的可选依赖（载荷缺失、当前平台没有包条目或下载失败）只记录警告，skill 照常加载。因此：

- 发布工作流在原生 Runner 上构建全部五个平台，并使用 `--require-bundled` 打包，因此每个发布 zip 都包含全部载荷。
- 没有条目的 `windows-arm64` 宿主，或尚未运行 `build_native.py` 的调试机器，仍可使用其他全部工具，`native-demo` 会报告 `exists: false`，与 `rg-check` 报告缺失 `rg` 的方式一致。

LuaSkills 会复用同版本的已安装依赖。修改 C 源码后，请同时提升 `dependencies.yaml` 与 `runtime/native_demo.lua` 中的依赖版本，或在下次调试前删除 `.luaskills-debug/runtime/dependencies/ffi/<skill-id>/demo-native/`。
<!-- <<< demo-only -->

<!-- >>> demo-only -->
## LuaSkills 技能包配置示例

`skill.yaml` 顶层的 `config` 块演示包级共享配置，并覆盖五种受支持类型：`string`、`integer`、`float`、`enum` 与 `boolean`。示例同时包含约束、默认值、必填敏感值、标题、分组、顺序、格式、重启提示、高级标记和枚举元数据。该契约由 LuaSkills 0.5.5 引入，在 v0.7.2 中保持不变。

`runtime/config_validator.lua` 演示隔离的跨字段校验。`resources/skill-config.example.json` 展示唯一受支持的持久化文档形状，包括 `format_version`、十进制字符串 `revision` 和按包标识组织的 `skills` 对象。仓库内示例有意不保存必填敏感项 `api_token`。

嵌入宿主必须显式提供一个绝对、可写、用户级的 `skill_config_root`。普通技能包配置存储在 `<skill_config_root>/skills/config.json`；技能包 Lua 只能通过 `vulcan.config.*` 访问自身命名空间，跨包管理权限由宿主负责。

v0.7.2 独立版 `luaskills-debug` CLI 会在 `inspect` 阶段校验配置声明与 `config_validator` 路径，但尚未暴露 `skill_config_root` 参数；校验器本身只会在配置事务中执行。因此本仓库调试流程会真实校验技能包契约，不伪造配置写入；需要验证 `runtime-config` 读写与跨字段校验时，应使用已配置 `skill_config_root` 的宿主或 SDK。
<!-- <<< demo-only -->

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

1. 打包过滤、路径穿越、符号链接、发布版本、内置载荷打包与模板清理负向测试。
2. 严格仓库结构与清单校验，包括每个 `examples/debug/<tool>.args.json` 都必须对应已声明入口。
3. 官方调试器 `inspect`，存在配置时同时校验技能包配置声明与 `config_validator` 路径。
4. 官方调试器 `list-tools`。
5. 使用参数示例真实调用每个示例工具。
6. 确定性发布包构建。

<!-- >>> demo-only -->
在本演示中，验证脚本会先构建当前主机的 `demo-native` 库（需要 C 编译器），再调用全部六个工具；`node-runtime-demo` 会创建锁定的 pnpm 环境并执行两次 ESM Worker 调用。
<!-- <<< demo-only -->

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
native/
help/
overflow_templates/
resources/
licenses/
```

`.agents/`、`.github/`、`scripts/`、`tests/`、`.luaskills-debug/`、`dist/`、`node_modules/`、`.pnpm-store/`、Python 缓存、其他本地产物和符号链接不会进入正式包。

本地打包允许内置载荷缺失，便于单台机器打包它已构建的内容。`python scripts/package_skill.py --require-bundled` 则会在 `dependencies.yaml` 中任何内置依赖声明的 `path` 不会进入 zip 时失败；发布工作流始终使用该参数。

## GitHub Actions

仓库包含两个可直接复用的工作流：

- **Validate and Package LuaSkill**：Pull Request 或手动触发时下载调试器与运行时，加载 skill、枚举工具、执行真实调用、打包并上传 `<仓库名>-verified-package`。
- **Release LuaSkill**：推送 `v*` 标签时重新执行相同的真实调试流程，使用 `--require-bundled` 打包，创建 GitHub Release，并且只上传正式 zip 和 checksum。

<!-- >>> demo-only -->
两个工作流都会在验证前构建当前主机的 `demo-native` 库。发布工作流还包含一个 `native` 矩阵任务，分别在 `ubuntu-24.04`（linux-x64）、`ubuntu-24.04-arm`（linux-arm64）、`macos-15-intel`（macos-x64）、`macos-15`（macos-arm64）与使用 MSVC 的 `windows-latest`（windows-x64）上构建该库，这些 Runner 标签与 LuaSkills 核心发布一致。发布任务在打包前把每个库下载到 `native/<platform>/`。
<!-- <<< demo-only -->

发布脚本会拒绝脏工作区，要求参数与 `skill.yaml.version` 完全一致，并在创建、推送标签前重新执行完整验证。参数应为 `skill.yaml` 中的精确版本：

```powershell
.\scripts\tag_release.ps1 <version>
```

```bash
bash ./scripts/tag_release.sh <version>
```

<!-- >>> demo-only -->
本演示当前版本为 `0.3.1`。
<!-- <<< demo-only -->

## 从最小模板开始

演示工具适合参考，但在新 skill 中只是干扰。一个命令即可把仓库精简为只有一个 `hello` 工具的最小 skill：

```powershell
.\scripts\clean_to_template.ps1 -Yes
```

```bash
bash ./scripts/clean_to_template.sh --yes
```

清理脚本会：

- 删除 `demo-status`、`rg-check`、`overflow-demo`、`node-runtime-demo` 与 `native-demo` 工具及其 runtime、帮助和示例文件，删除配置示例，以及 `node/`、`native/`、`overflow_templates/` 与 `resources/` 目录；
- 用最小内容改写 `skill.yaml`、`dependencies.yaml`（全部分组为空）、`help/help.md` 与 `licenses/THIRD_PARTY_NOTICES.md`；
- 删除两份 README、验证脚本与工作流中所有标记为 `demo-only` 的块，使验证脚本只调用 `hello`，发布工作流不再包含原生构建任务；
- 保留全部工具：打包、校验、调试、初始化、发布、打标签、原生构建与清理脚本，工作流，`.agents/` 和 `tests/`。

未传入 `--yes` 时只列出计划中的变更。`git status --porcelain` 报告存在变更时，除非传入 `--force`，否则拒绝执行；执行时会输出每个被删除或改写的路径，再次运行不会做任何改动。完成后运行 `validate_skill.py` 与 `verify_skill`；如果 skill 未声明 `node_runtime`，可向 `setup_debug` 传入 `--skip-managed-node-setup`。

## Fork 后需要替换的内容

1. 可先运行[模板清理脚本](#从最小模板开始)。
2. 将仓库名改为最终 `skill_id`，只使用小写字母、数字和单连字符。
3. 替换 `skill.yaml` 中的显示名称、版本、入口、参数和帮助引用。
4. 替换 `runtime/`、`node/`、`python/`、`native/`、`help/`、`overflow_templates/`、`resources/` 与 `licenses/` 中的示例内容。
5. 在 `dependencies.yaml` 中声明真实依赖；校验器不要求保留示例 `rg` 或 `demo-native`。不需要 Node.js 时应同时删除 `node_runtime`、`node/` 与对应入口；不分发原生库时应同时删除 `native/` 与对应内置依赖。
6. 替换两份 README 和帮助文档中剩余的 `demo-skill` 示例描述。
7. 运行 `verify_skill`，完成连续五轮零问题审核，提交全部目标文件，然后运行发布脚本。

仓库物理目录名决定正式 `skill_id`。仅修改 `skill.yaml.name` 不会改变安装标识。

<!-- >>> demo-only -->
## 当前示例能力

- `hello`：模板清理脚本保留的最小工具。
- `demo-status`：返回稳定的 skill 版本、目录、请求上下文与生命周期诊断。
- `rg-check`：演示 skill 私有可选工具依赖及 `vulcan.deps.tools_path`。
- `overflow-demo`：演示分页输出与 skill 私有 overflow template。
- `node-runtime-demo`：演示受管 Node.js `24.18.0`、pnpm 锁定依赖、ESM handler、环境创建、Worker 复用与真实调用诊断。
- `native-demo`：演示按平台随包分发的原生库、`vulcan.deps.ffi_path` 与 LuaJIT FFI 调用。
- 技能包配置：演示 LuaSkills 技能包配置声明、UI 元数据、跨字段校验、缺少敏感配置时的指引与持久化 JSON 格式。
<!-- <<< demo-only -->

## 发布前五轮审核

实现与真实流程测试通过后，AI 必须循环审核代码、清单、下载校验、跨平台脚本、打包白名单、Action 与文档。发现任何问题都必须立即修复、完整复测并把连续通过计数清零。只有连续五次完整审核均未发现问题，才能结束或发布。

以 LuaSkills v0.7.2 官方文档作为协议依据：

- [Lua Skill Development Manual](https://github.com/LuaSkills/luaskills/blob/v0.7.2/docs/development/skill-development.md)
- [Lua Skill 开发手册（简体中文）](https://github.com/LuaSkills/luaskills/blob/v0.7.2/docs/zh-CN/development/skill-development.md)
- [技能包配置宿主契约](https://github.com/LuaSkills/luaskills/blob/v0.7.2/docs/integration/package-configuration.md)
- [LuaSkills v0.7.2 Release](https://github.com/LuaSkills/luaskills/releases/tag/v0.7.2)
