-- Report the bundled demo-native library path and call it through LuaJIT FFI when it exists.
-- 报告内置 demo-native 库的路径，并在库存在时通过 LuaJIT FFI 调用它。

--- Declared dependency name from dependencies.yaml.
--- dependencies.yaml 中声明的依赖名称。
local DEPENDENCY_NAME = "demo-native"

--- Declared dependency version from dependencies.yaml.
--- dependencies.yaml 中声明的依赖版本。
local DEPENDENCY_VERSION = "1.0.0"

--- Largest accepted absolute addend, which keeps every sum inside a 32-bit C int.
--- 允许的最大加数绝对值，保证所有求和结果都在 32 位 C int 范围内。
local MAX_ABS_ADDEND = 1000000000

--- C declarations exported by native/demo_native.c.
--- native/demo_native.c 导出的 C 声明。
local NATIVE_CDEF = [[
const char *demo_native_version(void);
int demo_native_add(int a, int b);
]]

--- Return the current runtime path separator.
--- 返回当前运行时使用的路径分隔符。
--- @return string
local function path_separator()
  return package.config and package.config:sub(1, 1) or "/"
end

--- Join path fragments with the host runtime helper when available.
--- 在可用时使用宿主运行时辅助函数拼接路径片段。
--- @param ...
--- @return string
local function join_path(...)
  local join = vulcan and vulcan.path and vulcan.path.join
  if type(join) == "function" then
    return join(...)
  end

  local parts = { ... }
  return table.concat(parts, path_separator())
end

--- Return the normalized LuaSkills platform key used by the demo manifest.
--- 返回当前演示清单使用的标准 LuaSkills 平台键。
--- @return string
local function current_platform_key()
  local separator = path_separator()
  local is_windows = separator == "\\"
  local jit_os = type(jit) == "table" and jit.os or nil
  local jit_arch = type(jit) == "table" and jit.arch or nil

  if is_windows then
    if jit_arch == "arm64" then
      return "windows-arm64"
    end
    return "windows-x64"
  end

  if jit_os == "OSX" then
    if jit_arch == "arm64" then
      return "macos-arm64"
    end
    return "macos-x64"
  end

  if jit_arch == "arm64" then
    return "linux-arm64"
  end
  return "linux-x64"
end

--- Return the library file name exported for one platform key.
--- 返回某个平台键导出的库文件名。
--- @param platform_key string
--- @return string
local function library_file_name(platform_key)
  if platform_key:match("^windows") then
    return "demo_native.dll"
  end
  if platform_key:match("^macos") then
    return "libdemo_native.dylib"
  end
  return "libdemo_native.so"
end

--- Build the expected installed library path from the injected FFI dependency root.
--- 基于注入的 FFI 依赖根路径构造预期的已安装库路径。
--- @param platform_key string
--- @return string
local function expected_library_path(platform_key)
  local ffi_path = vulcan and vulcan.deps and vulcan.deps.ffi_path or ""

  return join_path(
    ffi_path,
    DEPENDENCY_NAME,
    DEPENDENCY_VERSION,
    platform_key,
    "lib",
    library_file_name(platform_key)
  )
end

--- Read one optional integer addend and enforce the documented range.
--- 读取一个可选整数加数，并强制执行文档约定的范围。
--- @param args table|nil
--- @param key string
--- @param default_value integer
--- @return integer
local function read_addend(args, key, default_value)
  local raw_value = type(args) == "table" and args[key] or nil
  if raw_value == nil then
    return default_value
  end

  local value = tonumber(raw_value)
  if value == nil or value ~= math.floor(value) then
    error("native-demo argument '" .. key .. "' must be an integer")
  end
  if value < -MAX_ABS_ADDEND or value > MAX_ABS_ADDEND then
    error("native-demo argument '" .. key .. "' must be between -1000000000 and 1000000000")
  end
  return value
end

--- Declare the native functions once; a reused VM keeps earlier declarations, so redefinition is ignored.
--- 声明一次原生函数；复用的虚拟机会保留先前声明，因此忽略重复定义错误。
--- @param ffi table
local function declare_native_functions(ffi)
  pcall(ffi.cdef, NATIVE_CDEF)
end

--- Load the library and call both exported functions.
--- 加载库并调用两个导出函数。
--- @param library_path string
--- @param a integer
--- @param b integer
--- @return table
local function call_native_library(library_path, a, b)
  local ffi_loaded, ffi = pcall(require, "ffi")
  if not ffi_loaded then
    return { loaded = false, error = "LuaJIT ffi module is unavailable: " .. tostring(ffi) }
  end

  declare_native_functions(ffi)
  local library_loaded, library = pcall(ffi.load, library_path)
  if not library_loaded then
    return { loaded = false, error = tostring(library) }
  end

  return {
    loaded = true,
    native_version = ffi.string(library.demo_native_version()),
    sum = tonumber(library.demo_native_add(a, b)),
  }
end

--- Main tool entry for the bundled native library demonstration.
--- 内置原生库演示工具的主入口。
--- @param args table|nil
--- @return string
return function(args)
  local a = read_addend(args, "a", 40)
  local b = read_addend(args, "b", 2)
  local platform_key = current_platform_key()
  local library_path = expected_library_path(platform_key)
  local exists = vulcan.fs.exists(library_path)

  local payload = {
    ok = true,
    dependency = DEPENDENCY_NAME,
    declared_version = DEPENDENCY_VERSION,
    source_type = "bundled",
    platform = platform_key,
    expected_path = library_path,
    exists = exists,
    inputs = { a = a, b = b },
    note = "The library is built by scripts/build_native.py and shipped inside the skill package.",
  }

  if exists then
    local result = call_native_library(library_path, a, b)
    payload.ok = result.loaded
    payload.loaded = result.loaded
    payload.native_version = result.native_version
    payload.sum = result.sum
    payload.error = result.error
  end

  return vulcan.json.encode(payload)
end
