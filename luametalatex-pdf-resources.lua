local format = string.format
local concat = table.concat
local next = next

local temp_table = {}
local resources_meta = {
  __index = function(t, k)
    local v = {}
    t[k] = v
    return v
  end,
  __call = function(t, additional)
    local temp_table = temp_table
    local i=1
    local next_init = '<</%s<<'
    for kind, entries in next, t do
      temp_table[i] = format(next_init, kind)
      next_init = '>>/%s<<'
      i = i+1
      for name, entry in next, entries do
        temp_table[i] = format('/%s %i 0 R', name, entry)
        i = i+1
      end
    end
    if i == 1 then return format('<<%s>>', additional or '') end
    temp_table[i] = format('>>%s>>', additional or '')
    local result = concat(temp_table)
    for j=1,i do
      temp_table[j] = nil
    end
    return result
  end,
}

return function(t)
  return setmetatable(t or {}, resources_meta)
end
