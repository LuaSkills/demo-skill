/*
 * Tiny native library shipped inside the skill package as a bundled FFI dependency.
 * 作为内置 FFI 依赖随 skill 包一起分发的最小原生库。
 *
 * Build it for the current platform with `python scripts/build_native.py`.
 * 使用 `python scripts/build_native.py` 为当前平台构建该库。
 */

/*
 * DEMO_NATIVE_API exports one symbol from the shared library on every supported compiler.
 * DEMO_NATIVE_API 在所有受支持的编译器上把单个符号从共享库导出。
 */
#if defined(_WIN32)
#define DEMO_NATIVE_API __declspec(dllexport)
#elif defined(__GNUC__) || defined(__clang__)
#define DEMO_NATIVE_API __attribute__((visibility("default")))
#else
#define DEMO_NATIVE_API
#endif

/*
 * Return the library version so callers can prove which payload was loaded.
 * 返回库版本，便于调用方确认加载的是哪一个载荷。
 *
 * Returns: a static NUL-terminated string owned by the library; callers must not free it.
 * 返回：由库持有的静态 NUL 结尾字符串；调用方不得释放。
 */
DEMO_NATIVE_API const char *demo_native_version(void)
{
    return "demo-native 1.0.0";
}

/*
 * Add two integers; the Lua caller keeps both inputs within +/-1000000000 so the sum fits in int.
 * 计算两个整数之和；Lua 调用方把两个输入限制在 +/-1000000000 内，保证结果可放入 int。
 *
 * Parameters: a is the first addend and b is the second addend.
 * 参数：a 为第一个加数，b 为第二个加数。
 * Returns: the arithmetic sum of a and b.
 * 返回：a 与 b 的算术和。
 */
DEMO_NATIVE_API int demo_native_add(int a, int b)
{
    return a + b;
}
