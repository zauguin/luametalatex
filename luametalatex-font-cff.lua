local pack = string.pack
local strings = require'luametalatex-font-cff-data'

local function getstring(cff, str)
  local i = strings[str] or cff.strings[str]
  if not i then
    i = #strings + #cff.strings + 1
    cff.strings[str] = i
    cff.strings[i - #strings] = str
  end
  return i
end
local function serialize_index(index, element_serializer)
  local sizes = {1}
  local length = 1
  local data = {}
  for i=1,#index do
    data[i] = element_serializer(index[i])
    length = length + #data[i]
    sizes[#sizes+1] = length
  end
  data = table.concat(data)
  if data == "" then return "\0\0" end
  local offSize = length < 2^8 and 1 or length < 2^16 and 2 or length < 2^24 and 3 or 4
  local offsetfmt = string.format(">I%i", offSize)
  local offsets = ""
  for i = #sizes,1,-1 do
    sizes[i+1] = pack(offsetfmt, sizes[i])
  end
  sizes[1] = pack(">I2B", #index, offSize)
  sizes[#sizes+1] = data
  return table.concat(sizes)
end
local function ident(...)
  return ...
end
local real_lookup = {
  ['0'] = 0, ['1'] = 1, ['2'] = 2, ['3'] = 3, ['4'] = 4, ['5'] = 5, ['6'] = 6, ['7'] = 7, ['8'] = 8, ['9'] = 9,
  ['.'] = 0xa, ['-'] = 0xe
}
local function dictInt(n)
  local num = math.floor(n)
  if num ~= n then
    num = tostring(n)
    local i, result, tmp = 1, string.char(0x1e)
    while i <= #num do
      local c = real_lookup[num:sub(i, i)]
      if not c then -- We got an 'e'
        c = num:sub(i+1, i+1) == '+' and 0xb or 0xc
        repeat
          i = i + 1
        until num:sub(i+1, i+1) ~= '0'
      end
      if tmp then
        result = result .. string.char(tmp * 16 + c)
        tmp = nil
      else
        tmp = c
      end
      i = i + 1
    end
    return result .. string.char((tmp or 0xf) * 16 + 0xf)
  elseif num >= -107 and num <= 107 then
    return string.char(num + 139)
  elseif num >= 108 and num <= 1131 then
    num = num - 108
    return string.char(247 + ((num >> 8) & 0xFF), num & 0xFF)
  elseif num >= -1131 and num <= -108 then
    num = -num - 108
    return string.char(251 + ((num >> 8) & 0xFF), num & 0xFF)
  elseif num >= -32768 and num <= 32767 then
    return string.char(28, (num >> 8) & 0xFF, num & 0xFF)
  else
    return string.char(29, (num >> 24) & 0xFF, (num >> 16) & 0xFF,
                           (num >> 8) & 0xFF, num & 0xFF)
  end
end
local function serialize_top(cff)
  local data = dictInt(getstring(cff, cff.registry or 'Adobe'))
            .. dictInt(getstring(cff, cff.ordering or 'Identity'))
            .. dictInt(               cff.supplement or 0)
            .. string.char(12, 30)
  if cff.version then
    data = data .. dictInt(getstring(cff, cff.version)) .. string.char(0)
  end
  if cff.Notice then
    data = data .. dictInt(getstring(cff, cff.Notice)) .. string.char(1)
  end
  if cff.FullName then
    data = data .. dictInt(getstring(cff, cff.FullName)) .. string.char(2)
  end
  if cff.FamilyName then
    data = data .. dictInt(getstring(cff, cff.FamilyName)) .. string.char(3)
  end
  if cff.Weight then
    data = data .. dictInt(getstring(cff, cff.Weight)) .. string.char(4)
  end
  if cff.isFixedPitch then
    data = data .. dictInt(1) .. string.char(12, 1)
  end
  if cff.ItalicAngle and cff.ItalicAngle ~= 0 then
    data = data .. dictInt(cff.ItalicAngle) .. string.char(12, 2)
  end
  if cff.UnderlinePosition then
    data = data .. dictInt(cff.UnderlinePosition) .. string.char(12, 3)
  end
  if cff.UnderlineThickness then
    data = data .. dictInt(cff.UnderlineThickness) .. string.char(12, 4)
  end
  if cff.FontMatrix then
    data = data .. dictInt(cff.FontMatrix[1]) .. dictInt(cff.FontMatrix[2])
                .. dictInt(cff.FontMatrix[3]) .. dictInt(cff.FontMatrix[4])
                .. dictInt(cff.FontMatrix[5]) .. dictInt(cff.FontMatrix[6])
                .. string.char(12, 7)
  end
  if cff.FontBBox then
    data = data .. dictInt(cff.FontBBox[1]) .. dictInt(cff.FontBBox[2])
                .. dictInt(cff.FontBBox[3]) .. dictInt(cff.FontBBox[4])
                .. string.char(5)
  end
  if cff.PostScript then
    data = data .. dictInt(getstring(cff, cff.PostScript)) .. string.char(12, 21)
  end
  data = data .. dictInt(cff.charset_offset) .. string.char(15)
  data = data .. dictInt(cff.charstrings_offset) .. string.char(17)
  data = data .. dictInt(cff.fdarray_offset) .. string.char(12, 36)
  data = data .. dictInt(cff.fdselect_offset) .. string.char(12, 37)
  -- data = data .. dictInt(cff.private_size) .. dictInt(cff.private_offset) .. string.char(18)
  return data
end
local function serialize_font(cff, offset0) return function(private)
    local data = dictInt(private[3]) .. string.char(12, 38)
    data = data .. dictInt(private[2]) .. dictInt(offset0 + private[1]) .. string.char(18)
    return data
end end
local function va_minone(...)
  if select('#', ...) ~= 0 then
    return (...+1), select(2, ...)
  end
end
-- local function serialize_fdselect(cff)
--   local fdselect = cff.FDSelect or {format=3, {0,1}}
--   if not fdselect then
--     return '\3\0\1\0\0\0' .. string.pack('>I2', #cff.glyphs)
--   end
--   if fdselect.format == 0 then
--     return string.char(0, va_minone(table.unpack(fdselect)))
--   elseif fdselect.format == 3 then
--     local fdparts = {string.pack(">BI2", 3, #fdselect)}
--     for i=1,#fdselect do
--       fdparts[i+1] = string.pack(">I2B", fdselect[i][1], fdselect[i][2]-1)
--     end
--     fdparts[#fdselect+2] = string.pack(">I2", #cff.glyphs)
--     return table.concat(fdparts)
--   else
--     error[[Confusion]]
--   end
-- end
local function serialize_fdselect(cff)
  local fdselect = {""}
  local lastfont = -1
  for i, g in ipairs(cff.glyphs) do
    local font = g.cidfont or 1
    if font ~= lastfont then
      fdselect[#fdselect+1] = string.pack(">I2B", i-1, font-1)
      lastfont = font
    end
  end
  if #fdselect*3+2 > #cff.glyphs+1 then
    fdselect[1] = string.pack("B", 0)
    for i, g in ipairs(cff.glyphs) do
      local font = g.cidfont or 1
      fdselect[i+1] = string.pack("B", font-1)
    end
  else
    fdselect[1] = string.pack(">BI2", 3, #fdselect-1)
    fdselect[#fdselect+1] = string.pack(">I2", #cff.glyphs)
  end
  return table.concat(fdselect)
end
local function serialize_private(private, subrsoffset)
  local data = ""
  if private.BlueValues and #private.BlueValues ~= 0 then
    local last = 0
    for _, v in ipairs(private.BlueValues) do
      data = data .. dictInt(v - last)
      last = v
    end
    data = data .. '\6'
  end
  if private.OtherBlues and #private.OtherBlues ~= 0 then
    local last = 0
    for _, v in ipairs(private.OtherBlues) do
      data = data .. dictInt(v - last)
      last = v
    end
    data = data .. '\7'
  end
  if private.BlueScale then
    data = data .. dictInt(private.BlueScale) .. '\12\9'
  end
  if private.BlueShift then
    data = data .. dictInt(private.BlueShift) .. '\12\10'
  end
  if private.BlueFuzz then
    data = data .. dictInt(private.BlueFuzz) .. '\12\11'
  end
  if private.ForceBold then
    data = data .. dictInt(1) .. '\12\14'
  end
  if private.StdHW then
    data = data .. dictInt(private.StdHW) .. '\10'
  end
  if private.StdVW then
    data = data .. dictInt(private.StdVW) .. '\11'
  end
  if private.StemSnapH and #private.StemSnapH ~= 0 then
    local last = 0
    for _, v in ipairs(private.StemSnapH) do
      data = data .. dictInt(v - last)
      last = v
    end
    data = data .. '\12\12'
  end
  if private.StemSnapV and #private.StemSnapV ~= 0 then
    local last = 0
    for _, v in ipairs(private.StemSnapV) do
      data = data .. dictInt(v - last)
      last = v
    end
    data = data .. '\12\13'
  end
  if subrsoffset and subrsoffset ~= 0 then
    data = data .. dictInt(subrsoffset) .. '\19'
  end
  if private.defaultWidthX then
    data = data .. dictInt(private.defaultWidthX) .. '\20'
  end
  if private.nominalWidthX then
    data = data .. dictInt(private.nominalWidthX) .. '\21'
  end
  return data
end
local function serialize_charset(cff)
  local data = string.char(2)
  local last, count = -42, -1
  for _, glyph in ipairs(cff.glyphs) do
    if not glyph.cid then glyph.cid = glyph.index end
    if glyph.cid ~= 0 then
      if glyph.cid ~= last + 1 or count == 0xFFFF then
        if count >= 0 then
          data = data .. string.pack(">I2", count)
          count = -1
        end
        data = data .. string.pack(">I2", glyph.cid)
      end
      last = glyph.cid
      count = count + 1
    end
  end
  if count >= 0 then
    data = data .. string.pack(">I2", count)
    count = -1
  end
  return data
end
return function(cff)
  cff.strings = {}
  cff.private_offset = 0
  cff.charstrings_offset = 0
  cff.fdarray_offset = 0
  cff.fdselect_offset = 0
  cff.charset_offset = 0
  local top = serialize_index({serialize_top(cff)}, ident)
  local data = string.char(1, 0, 4, 2) -- Assuming 16Bit offsets (Where are they used?)
  local name = serialize_index({cff.FontName}, ident)
  local globalsubrs = serialize_index(cff.GlobalSubrs or {}, ident)
  local private_offsets, privates = {}, {}
  local privates_size = 0 -- These include the localsubrs sizes
  for i, p in ipairs(cff.Privates or {cff}) do
    local subrs = p.Subrs
    if not subrs or subrs and #subrs == 0 then
      subrs = ""
    else
      subrs = serialize_index(subrs, ident)
    end
    local serialized = ""
    if subrs ~= "" then
      local last_size = 0
      repeat
        last_size = #serialized
        serialized = serialize_private(p, last_size)
      until last_size == #serialized
    else
      serialized = serialize_private(p)
    end
        -- serialized = serialize_private(p, -#subrs)
    privates[i] = serialized .. subrs
    private_offsets[i] = {privates_size + 0*#subrs, #serialized, getstring(cff, p.FontName or (cff.FontName .. '-' .. i))}
    privates_size = privates_size + #subrs + #serialized
  end
  if cff.glyphs[1].index ~= 0 then
    table.insert(cff.glyphs, 1, {index = 0, cs = string.char(14), cidfont = cff.glyphs[1].cidfont})
  end
  local strings = serialize_index(cff.strings, ident)
  local charset = serialize_charset(cff)
  local fdselect = serialize_fdselect(cff)
  local charstrings = serialize_index(cff.glyphs, function(g) return g.cs end)
  local pre_private, top_size = #data + #name + #strings + #globalsubrs
  repeat
    top_size = #top
    cff.charstrings_offset = pre_private + top_size + privates_size
    cff.charset_offset = cff.charstrings_offset + #charstrings
    cff.fdselect_offset = cff.charset_offset + #charset
    cff.fdarray_offset = cff.fdselect_offset + #fdselect
    top = serialize_index({serialize_top(cff)}, ident)
  until top_size == #top
  local fdarray = serialize_index(private_offsets, serialize_font(cff, top_size + pre_private), ident)
  return data .. name .. top .. strings .. globalsubrs .. table.concat(privates) .. charstrings .. charset .. fdselect .. fdarray
end
