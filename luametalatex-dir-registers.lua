-- local names = {}
local setters = {
}
local getters = {
}
local value_values = token.values'value'
for i=0,#value_values do
  value_values[value_values[i]] = i
end
function tex.gettextdir() return tex.textdirection end
function tex.getlinedir() return tex.linedirection end
function tex.getmathdir() return tex.mathdirection end
function tex.getpardir()  return tex.pardirection  end
-- local integer_code = value_values.none
local integer_code = value_values.integer
local functions = lua.get_functions_table()
local lua_call_cmd = token.command_id'lua_call'
local function set_xdir(id, scanning)
  -- local name = names[id]
  if scanning then
    return integer_code, getters[id]()
    -- return integer_code, tex[name .. 'ection']
  end
  local value
  if token.scan_keyword'tlt' then
    value = 0
  elseif token.scan_keyword'trt' then
    value = 1
  else
    value = token.scan_int()
  end
  setters[id](value)
  -- tex["set" .. name](value)
end
return function(name)
  local getter = tex["get" .. name]
  local setter = tex["set" .. name]
  assert(getter and setter, "direction parameter undefined")
  local idx = token.luacmd(name, set_xdir, "protected", "global", "value")
  -- names[idx] = name
  getters[idx] = getter
  setters[idx] = setter
  return idx
end
