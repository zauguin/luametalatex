local loaded = package.loaded
local findtable = lpeg.Cf(lpeg.Cc(_G) * (lpeg.C((1-lpeg.P'.')^0) * '.')^0 * lpeg.C((1-lpeg.P'.')^0) * -1,
  function(t, name)
    local subtable = t[name]
    if subtable == nil then
      subtable = {}
      t[name] = subtable
    elseif type(subtable) ~= "table" then
      error("Naming conflict for (sub)module " .. name)
    end
    return subtable
  end)
local package_patt = lpeg.C(((1-lpeg.P'.')^0 * '.')^0) * (1-lpeg.P'.')^0 * -1
function module(name, ...)
  local modtable = loaded[name]
  if type(modtable) ~= "table" then
    modtable = findtable:match(name)
    loaded[name] = modtable
  end
  if modtable._NAME == nil then
    modtable._M = modtable
    modtable._NAME = name
    modtable._PACKAGE = package_patt:match(name)
  end
  local info = debug.getinfo(2, "fS")
  if not info or info.what == "C" then
    error[['module' should only be called from Lua functions]]
  end
  debug.setupvalue(info.func, 1, modtable)
  for i = 1, select('#', ...) do
    local opt = select(i, ...) if type(opt) == "function" then
      opt(modtable)
    end
  end
  return modtable
end
function package.seeall(modtable)
  local meta = getmetatable(modtable)
  if not meta then
    meta = {}
    setmetatable(modtable, meta)
  end
  meta.__index = _G
end
