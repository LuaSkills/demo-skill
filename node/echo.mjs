// Import the exact third-party dependency locked by pnpm-lock.yaml.
// 导入由 pnpm-lock.yaml 锁定的精确第三方依赖。
import isOdd from "is-odd";

/**
 * Handle one managed Node.js invocation from the Lua runtime bridge.
 * 处理一次来自 Lua 运行时桥接的受管 Node.js 调用。
 *
 * @param {{text?: string, number?: number}} args JSON-compatible invocation arguments.
 * @param {{text?: string, number?: number}} args JSON 兼容的调用参数。
 * @param {Record<string, unknown>} ctx Managed invocation context supplied by LuaSkills.
 * @param {Record<string, unknown>} ctx LuaSkills 提供的受管调用上下文。
 * @returns {Promise<Record<string, unknown>>} Structured runtime and dependency diagnostics.
 * @returns {Promise<Record<string, unknown>>} 结构化运行时与依赖诊断。
 */
export async function main(args, ctx) {
  // Text preserves the optional string contract declared by skill.yaml.
  // Text 保留 skill.yaml 声明的可选字符串契约。
  const text = typeof args.text === "string" ? args.text : "";
  // NumberValue preserves only finite numeric inputs before applying the demo increment.
  // NumberValue 仅保留有限数值输入，再执行示例增量计算。
  const numberValue = Number.isFinite(args.number) ? args.number : 0;
  // DependencyMarker proves that pnpm installed and Node resolved the declared bare import.
  // DependencyMarker 用于证明 pnpm 已安装并且 Node 已解析声明的裸导入。
  const dependencyMarker = isOdd(3) ? "is-odd" : "unexpected";

  console.log("managed node handler ready");
  return {
    runtime: "node",
    dependency: dependencyMarker,
    text,
    number: numberValue + 2,
    ctxIsObject: ctx !== null && typeof ctx === "object",
  };
}
