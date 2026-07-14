-- Return stable runtime diagnostics for install, update, and uninstall tests.
-- 返回用于安装、更新和卸载测试的稳定运行时诊断信息。

--- Build one stable UTC timestamp string for demo responses.
--- 构造一条稳定的 UTC 时间戳字符串，用于演示返回值。
--- @return string
local function utc_timestamp()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

--- Return the current skill directory path exposed by the host runtime.
--- 返回宿主运行时暴露的当前技能目录路径。
--- @return string
local function current_skill_dir()
  local context = vulcan and vulcan.context
  if type(context) ~= "table" then
    return ""
  end

  local skill_dir = context.skill_dir
  if type(skill_dir) == "string" then
    return skill_dir
  end

  return ""
end

--- Return the current request context table only when explicitly requested.
--- 仅在显式请求时返回当前请求上下文表。
--- @param args table|nil
--- @return table|nil
local function maybe_request_context(args)
  if type(args) ~= "table" or args.include_context ~= true then
    return nil
  end

  local context = vulcan and vulcan.context
  if type(context) ~= "table" then
    return nil
  end

  if type(context.request) == "table" then
    return context.request
  end

  return nil
end

--- Build the structured demo status payload.
--- 构造结构化的演示状态载荷。
--- @param args table|nil
--- @return table
local function build_status_payload(args)
  local display_name = "demo-caller"
  if type(args) == "table" and args.name ~= nil and tostring(args.name) ~= "" then
    display_name = tostring(args.name)
  end

  return {
    ok = true,
    skill_id = "demo-skill",
    skill_name = "LuaSkills Demo Skill",
    skill_version = "0.2.0",
    timestamp = utc_timestamp(),
    caller = display_name,
    skill_dir = current_skill_dir(),
    dependency_demo = {
      name = "rg",
      required = false,
      purpose = "This dependency is intentionally optional and exists only for install or uninstall demonstrations.",
    },
    request_context = maybe_request_context(args),
  }
end

--- Main tool entry for the runtime status demo.
--- 运行时状态演示工具的主入口。
--- @param args table|nil
--- @return string
return function(args)
  return vulcan.json.encode(build_status_payload(args))
end
