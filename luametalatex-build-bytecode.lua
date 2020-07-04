local concat = table.concat
local format = string.format
local ioopen = io.open
local assert = assert
local ipairs = ipairs

local _ENV = {}

local first, later =
  'local __hidden_local__package_preload__=package.preload',
  '\n__hidden_local__package_preload__[%q]=function(...)%s\nend'

first = first .. later

local list = {}

return function(t)
  local length = #t
  local tmpl = first
  for i, mod in ipairs(t) do
    local name, f = mod[1], assert(ioopen(mod[2], 'r'))
    local data = f:read'a'
    f:close()
    list[i] = format(tmpl, name, data)
    tmpl = later
  end
  return concat(list, nil, 1, length)
end
