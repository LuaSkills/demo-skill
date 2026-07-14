# AI 调用调试说明书

## 目录

- [目标](#目标)
- [首次初始化](#首次初始化)
- [标准调试顺序](#标准调试顺序)
- [调用参数](#调用参数)
- [输出模式](#输出模式)
- [故障定位](#故障定位)
- [发布前闭环](#发布前闭环)

## 目标

使用与正式宿主相同的 `load_from_roots -> call_skill` 链路验证当前仓库。仓库封装会先按正式包白名单暂存到 `.luaskills-debug/source/<skill-id>`，官方调试器再将其同步到 `.luaskills-debug/runtime/skills/<skill-id>` 并从隔离运行根加载调用。不能把仓库根直接传给调试器，也不能用直接执行 Lua 文件替代。

## 首次初始化

Windows：

```powershell
.\scripts\setup_debug.ps1
```

Linux/macOS：

```bash
bash ./scripts/setup_debug.sh
```

初始化脚本必须完成以下检查：

1. 从 `.luaskills-version` 读取固定版本。
2. 按当前系统与 CPU 架构选择正式 Release 资产。
3. 同时下载 `.tar.gz` 与 `.sha256`。
4. 校验 SHA-256 后才解压。
5. 把完整调试工作区写入被 Git 忽略的 `.luaskills-debug/`。
6. 运行官方 `setup_runtime`，拉取匹配版本的 Lua runtime packages。
7. 下载 v0.5.2 官方 managed-runtime 拉取脚本并验证固定 SHA-256，再安装 Node.js `24.18.0` 与 pnpm `11.11.0`。

需要强制重建时传入 `-Force` 或 `--force`。仅验证调试器本体时，同时传入 `-SkipRuntimeSetup -SkipManagedNodeSetup` 或 `--skip-runtime-setup --skip-managed-node-setup`。

## 标准调试顺序

每次修改入口或清单后按固定顺序执行：

1. `inspect`：验证清单、目录绑定、入口文件与正式引擎加载。
2. `list-tools`：确认公开工具名和 canonical 工具名。
3. `call`：使用真实参数调用目标工具；包含 `node_runtime` 时必须实际调用受管 Node.js 入口。
4. `verify_skill`：执行负向安全测试，重新校验、加载、枚举，真实调用全部示例工具并生成发布包。

每个调试命令都会在仓库级互斥锁内重建白名单暂存目录，保证被调试文件与 Action 最终打包文件一致，并避免 `.git/` 或 `.luaskills-debug/` 被递归同步；同一仓库的并发调试命令会安全串行执行。

Windows：

```powershell
.\scripts\debug_skill.ps1 -Command inspect
.\scripts\debug_skill.ps1 -Command list-tools
.\scripts\debug_skill.ps1 -Command call -Tool demo-status -ArgsFile .\examples\debug\demo-status.args.json
.\scripts\debug_skill.ps1 -Command call -Tool node-runtime-demo -ArgsFile .\examples\debug\node-runtime-demo.args.json -Output json
.\scripts\verify_skill.ps1
```

Linux/macOS：

```bash
bash ./scripts/debug_skill.sh inspect
bash ./scripts/debug_skill.sh list-tools
bash ./scripts/debug_skill.sh call --tool demo-status --args-file ./examples/debug/demo-status.args.json
bash ./scripts/debug_skill.sh call --tool node-runtime-demo --args-file ./examples/debug/node-runtime-demo.args.json --output json
bash ./scripts/verify_skill.sh
```

## 调用参数

- 小型参数使用 `ArgsJson` / `--args-json`。
- 大型或包含复杂转义的参数写入 JSON 文件，再使用 `ArgsFile` / `--args-file`。
- `call` 必须使用 `list-tools` 已确认的工具名，不要猜测入口名称。
- 需要验证 `host_result` 桥接时显式传入 `EnableHostResult` / `--enable-host-result`；普通调用不要默认开启。

参数文件示例：

```json
{
  "name": "ai-debug",
  "include_context": true
}
```

## 输出模式

- `pretty`：默认的人类可读诊断，适合交互排查。
- `json`：完整结构化结果，适合 AI 精确核对字段和自动化断言。
- `content`：只输出工具内容，适合验证最终用户可见文本。

AI 在判断返回字段、错误类型或上下文归属时应使用 `json`，不得依靠 `pretty` 文本猜测内部结构。

## 故障定位

### 下载或校验失败

确认 `.luaskills-version` 对应的 Release 确实包含当前平台资产。不得跳过 checksum；删除 `.luaskills-debug/` 后使用强制重建重新下载。

### inspect 失败

先检查错误中给出的真实 `skill.yaml`、入口文件和同步目标路径，再核对清单字段。不要通过新增可选字段 fallback 绕过错误。

### list-tools 缺少入口

核对 `skill.yaml.entries[].name`、`lua_entry` 和物理文件，随后重新执行 `inspect`。工具 canonical 名由调试器输出确认。

### call 参数错误

读取 `skill.yaml.entries[].parameters` 与目标 Lua 入口，确认必填字段、类型和返回契约。复杂参数改用 JSON 文件，避免 shell 转义改变载荷。

### 依赖不可用

区分 Lua runtime packages、skill 自有 `dependencies.yaml` 和宿主管理能力。只根据调试器真实错误修复对应层，不要把依赖路径写死到源码。

## 发布前闭环

`verify_skill` 成功后检查 `dist/`：

- zip 名为 `<skill-id>-v<version>-skill.zip`。
- checksum 名为 `<skill-id>-v<version>-checksums.txt`。
- zip 只有一个名为 `<skill-id>/` 的顶层目录。
- AI 提示、下载调试器、Action、脚本和缓存不在 zip 内。
- `git status --short --ignored` 显示 `.luaskills-debug/` 被忽略。

最后推送与 `skill.yaml.version` 完全一致的 `v<version>` 标签，由 Release Action 重新执行同一套校验与打包逻辑。
