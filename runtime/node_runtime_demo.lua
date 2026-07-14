-- Invoke one managed Node.js ESM handler through the official runtime bridge.
-- 通过官方运行时桥接调用一个受管 Node.js ESM 处理器。

--- Resolve the optional invocation text according to the manifest parameter contract.
--- 根据清单参数契约解析可选调用文本。
--- @param args table|nil Invocation arguments supplied by the LuaSkills host.
--- @param args table|nil LuaSkills 宿主提供的调用参数。
--- @return string text Text forwarded to the managed Node.js handler.
--- @return string text 转发给受管 Node.js 处理器的文本。
local function resolve_text(args)
  if type(args) == "table" and type(args.text) == "string" then
    return args.text
  end
  return "lua"
end

--- Resolve the optional integer according to the manifest parameter contract.
--- 根据清单参数契约解析可选整数。
--- @param args table|nil Invocation arguments supplied by the LuaSkills host.
--- @param args table|nil LuaSkills 宿主提供的调用参数。
--- @return integer number Integer forwarded to the managed Node.js handler.
--- @return integer number 转发给受管 Node.js 处理器的整数。
local function resolve_number(args)
  if type(args) == "table" and type(args.number) == "number" then
    return math.floor(args.number)
  end
  return 40
end

--- Require one successful managed Node.js invocation with the expected dependency result.
--- 要求一次受管 Node.js 调用成功并返回预期依赖结果。
--- @param result table Managed runtime invocation result.
--- @param result table 受管运行时调用结果。
--- @param label string Stable invocation label used in diagnostics.
--- @param label string 诊断信息使用的稳定调用标签。
--- @return nil
local function require_success(result, label)
  if result.ok ~= true then
    error(label .. " failed: " .. tostring(result.error))
  end
  if type(result.value) ~= "table" then
    error(label .. " returned a non-object value")
  end
  if result.value.dependency ~= "is-odd" then
    error(label .. " did not load the declared is-odd dependency")
  end
end

--- Run the managed Node.js demo twice and return structured runtime diagnostics.
--- 连续运行两次受管 Node.js 示例并返回结构化运行时诊断。
--- @param args table|nil Invocation arguments supplied by the LuaSkills host.
--- @param args table|nil LuaSkills 宿主提供的调用参数。
--- @return string json Encoded Node.js status and invocation results.
--- @return string json 编码后的 Node.js 状态与调用结果。
return function(args)
  -- StatusBefore captures the declared runtime state before environment creation.
  -- StatusBefore 记录环境创建前已声明运行时的状态。
  local status_before = vulcan.runtime.node.status()
  -- FirstResult creates or reuses the declared pnpm environment and invokes the ESM handler.
  -- FirstResult 创建或复用已声明的 pnpm 环境并调用 ESM 处理器。
  local first_result = vulcan.runtime.node.invoke({
    file = "node/echo.mjs",
    handler = "main",
    timeout_ms = 30000,
    args = {
      text = resolve_text(args),
      number = resolve_number(args),
    },
  })
  require_success(first_result, "first managed Node.js invocation")

  -- SecondResult proves that a subsequent call uses the same declared package environment.
  -- SecondResult 用于证明后续调用使用相同的已声明包环境。
  local second_result = vulcan.runtime.node.invoke({
    file = "node/echo.mjs",
    handler = "main",
    timeout_ms = 30000,
    args = {
      text = "warm-node",
      number = 41,
    },
  })
  require_success(second_result, "second managed Node.js invocation")

  -- StatusAfter captures the ready environment hash and executable paths after invocation.
  -- StatusAfter 记录调用完成后的就绪环境哈希与可执行文件路径。
  local status_after = vulcan.runtime.node.status()
  return vulcan.json.encode({
    status_before = status_before,
    first = first_result,
    second = second_result,
    status_after = status_after,
  })
end
