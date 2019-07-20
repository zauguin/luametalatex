local var_value = kpse.var_value
local texconfig = texconfig
-- These are special in two ways: They are strings and I think they are ignored
-- We set them anyway because they should be emulated at some point
for _, name in ipairs{
    "shell_escape",
    "shell_escape_commands",
  } do
  local value = var_value(name)
  texconfig[name] = value
end
for _, name in ipairs{
    "string_vacancies",
    "pool_free",
    "max_strings",
    "strings_free",
    "nest_size",
    "max_in_open",
    "param_size",
    "save_size",
    "stack_size",
    "dvi_buf_size",
    "error_line",
    "half_error_line",
    "max_print_line",
    "hash_extra",
    "pk_dpi",
    "trace_file_names",
    "file_line_error",
    "halt_on_error",
  } do
  local value = var_value(name)
  texconfig[name] = tonumber(value) or value or nil
end
