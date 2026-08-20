-- Validate cross-field package configuration in the isolated configuration sandbox.
-- 在隔离配置沙箱中校验跨字段技能包配置。
--
-- The values parameter contains typed effective values from declarations and defaults.
-- values 参数包含来自声明与默认值的类型化有效值。
--
-- The return value is an array of optional-key issues and this function performs no I/O or mutation.
-- 返回值是可选关联键的问题数组，并且此函数不执行 I/O 或修改。
-- @param values table
-- @return table
return function(values)
  -- Local providers intentionally use a conservative temperature limit in this example.
  -- 本示例有意为本地提供方使用更保守的温度上限。
  if values.provider == "local" and values.temperature > 1.0 then
    return {
      {
        key = "temperature",
        code = "local_temperature_too_high",
        message = "Local provider requires temperature at or below 1.0",
      },
    }
  end
  return {}
end
