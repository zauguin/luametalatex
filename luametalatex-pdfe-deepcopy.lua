local format = string.format
local strip_floats = require'luametalatex-pdf-utils'.strip_floats
local pdfe = pdfe
local l = lpeg
local regularchar = 1-l.S'\0\t\n\r\f ()<>[]{}/%#'
local byte = string.byte
local escapednamechar = l.P(1)/function(s)
  return format("#%02X", byte(s))
end
local nameescape = l.Cs(l.Cc'/' * (regularchar + escapednamechar)^0)
local deepcopy_lookup deepcopy_lookup = {
  function(_, pdf) -- 1: null
    return 'null'
  end,
  function(_, pdf, b) -- 2: boolean
    return b == 1 and 'true' or 'false'
  end,
  function(_, pdf, i) -- 3: integer
    return format("%d", i)
  end,
  function(_, pdf, f) -- 4: number
    return strip_floats(format("%f", f), "%.?0+[ %]]", "")
  end,
  function(_, pdf, name) -- 5: name
    return nameescape:match(name)
  end,
  function(_, pdf, string, hex) -- 6: string
    return hex and format("<%s>", string) or format("(%s)", string)
  end,
  function(references, pdf, array, size) -- 7: array
    local a = {}
    for i=1,size do
      local type, value, detail = pdfe.getfromarray(array, i)
      a[i] = deepcopy_lookup[type](references, pdf, value, detail)
    end
    return '[' .. table.concat(a, ' ') .. ']'
  end,
  function(references, pdf, dict, size) -- 8: dict
    local a = {}
    for i=1,size do
      local key, type, value, detail = pdfe.getfromdictionary(dict, i)
      a[2*i-1] = nameescape:match(key)
      a[2*i] = deepcopy_lookup[type](references, pdf, value, detail)
    end
    return '<<' .. table.concat(a, ' ') .. '>>'
  end,
  nil, -- 9: stream (can only appear as a reference
  function(references, pdf, ref, num)
    local new = references[-num]
    if not new then
      new = pdf:getobj()
      references[-num] = new
      references[#references+1] = {ref, num}
    end
    return format("%i 0 R", new)
  end,
}

local references = setmetatable({}, {__index = function(t, n)
  local v = {}
  t[n] = v
  return v
end})

return function(file, id, pdf, type, value, detail)
  local references = references[id]
  local res = deepcopy_lookup[type](references, pdf, value, detail)
  local i, r = 1, references[1]
  while r do
    local type, value, detail, more = pdfe.getfromreference(r[1])
    if type == 9 then
      local a,j = {}, 0
      for i=1,more do
        local key, type, value, detail = pdfe.getfromdictionary(detail, i)
        if key == 'Length' then
          j=2
        else
          a[2*i-1-j] = nameescape:match(key)
          a[2*i-j] = deepcopy_lookup[type](references, pdf, value, detail)
        end
      end
      pdf:stream(references[-r[2]], table.concat(a, ' '), value(false), false, true)
    else
      pdf:indirect(references[-r[2]], deepcopy_lookup[type](references, pdf, value, detail))
    end
    i = i+1
    r = references[i]
  end
  for i=1,#references do references[i] = nil end
  return res
end
