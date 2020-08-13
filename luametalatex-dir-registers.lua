local scan_int = token.scan_integer
local scan_keyword = token.scan_keyword

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
local integer_code = value_values.integer
local function set_xdir(id, scanning)
  if scanning == 'value' then
    return integer_code, getters[id]()
  end
  -- local global = scanning == 'global'
  local value
  if scan_keyword'tlt' then
    value = 0
  elseif scan_keyword'trt' then
    value = 1
  else
    value = scan_int()
  end
  setters[id](value, scanning)
end
return function(name)
  local getter = tex["get" .. name]
  local setter = tex["set" .. name]
  assert(getter and setter, "direction parameter undefined")
  local idx = token.luacmd(name, set_xdir, "protected", "global", "value")
  getters[idx] = getter
  setters[idx] = setter
  return idx
end
