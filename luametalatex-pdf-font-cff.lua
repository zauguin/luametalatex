local sfnt = require'luametalatex-font-sfnt'
local stdStrings = require'luametalatex-font-cff-data'
local offsetfmt = ">I%i"
local function parse_index(buf, i)
  local count, offsize
  count, offsize, i = string.unpack(">I2B", buf, i)
  if count == 0 then return {}, i-1 end
  local fmt = offsetfmt:format(offsize)
  local offsets = {}
  local dataoffset = i + offsize*count - 1
  for j=1,count+1 do
    offsets[j], i = string.unpack(fmt, buf, i)
  end
  for j=1,count+1 do
    offsets[j] = offsets[j] + i - 1
  end
  return offsets, offsets[#offsets]
end
local real_mapping = { [0] = '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
  '.', 'E', 'E-', nil, '-', nil}
local function parse_real(cs, offset)
  local c = cs:byte(offset)
  if not c then return offset end
  local c1, c2 = real_mapping[c>>4], real_mapping[c&0xF]
  if not c1 or not c2 then
    return c1 or offset, c1 and offset
  else
    return c1, c2, parse_real(cs, offset+1) --Warning: This is not a tail-call,
    -- so we are affected by the stack limit. On the other hand, as long as
    -- there are less than ~50 bytes we should be safe.
  end
end
local function get_number(result)
  if #result ~= 1 then
    print(require'inspect'(result))
  end
  assert(#result == 1)
  local num = result[1]
  result[1] = nil
  return num
end
local function get_bool(result)
  return get_number(result) == 1
end
local function get_string(result, strings)
  local sid = get_number(result)
  return stdStrings[sid] or strings[sid-#stdStrings]
end
local function get_array(result)
  local arr = table.move(result, 1, #result, 1, {})
  for i=1,#result do result[i] = nil end
  return arr
end
local function get_delta(result)
  local arr = get_array(result)
  local last = 0
  for i=1,#arr do
    arr[i] = arr[i]+last
    last = arr[i]
  end
  return arr
end
local function get_private(result)
  local arr = get_array(result)
  assert(#arr == 2)
  return arr
end
local function get_ros(result, strings)
  local arr = get_array(result)
  assert(#arr == 3)
  result[1] = arr[1] arr[1] = get_string(result, strings)
  result[1] = arr[2] arr[2] = get_string(result, strings)
  return arr
end
local function apply_matrix(m, x, y)
  return (m[1] * x + m[3] * y + m[5])*1000, (m[2] * x + m[4] * y + m[6])*1000
end
local operators = {
  [0] = {'version', get_string},
        {'Notice', get_string},
        {'FullName', get_string},
        {'FamilyName', get_string},
        {'Weight', get_string},
        {'FontBBox', get_array},
        {'BlueValues', get_delta},
        {'OtherBlues', get_delta},
        {'FamilyBlues', get_delta},
        {'FamilyOtherBlues', get_delta},
        {'StdHW', get_number},
        {'StdVW', get_number},
        nil, -- 12, escape
        {'UniqueID', get_number},
        {'XUID', get_array},
        {'charset', get_number},
        {'Encoding', get_number},
        {'CharStrings', get_number},
        {'Private', get_private},
        {'Subrs', get_number},
        {'defaultWidthX', get_number},
        {'nominalWidthX', get_number},
 [-1] = {'Copyright', get_string},
 [-2] = {'isFixedPitch', get_bool},
 [-3] = {'ItalicAngle', get_number},
 [-4] = {'UnderlinePosition', get_number},
 [-5] = {'UnderlineThickness', get_number},
 [-6] = {'PaintType', get_number},
 [-7] = {'CharstringType', get_number},
 [-8] = {'FontMatrix', get_array},
 [-9] = {'StrokeWidth', get_number},
[-10] = {'BlueScale', get_number},
[-11] = {'BlueShift', get_number},
[-12] = {'BlueFuzz', get_number},
[-13] = {'StemSnapH', get_delta},
[-14] = {'StemSnapV', get_delta},
[-15] = {'ForceBold', get_bool},
[-18] = {'LanguageGroup', get_number},
[-19] = {'ExpansionFactor', get_number},
[-20] = {'initialRandomSeed', get_number},
[-21] = {'SyntheticBase', get_number},
[-22] = {'PostScript', get_string},
[-23] = {'BaseFontName', get_string},
[-24] = {'BaseFontBlend', get_delta},
[-31] = {'ROS', get_ros},
[-32] = {'CIDFontVersion', get_number},
[-33] = {'CIDFontRevision', get_number},
[-34] = {'CIDFontType', get_number},
[-35] = {'CIDCount', get_number},
[-36] = {'UIDBase', get_number},
[-37] = {'FDArray', get_number},
[-38] = {'FDSelect', get_number},
[-39] = {'FontName', get_string},
}
local function parse_dict(buf, i, j, strings)
  result = {}
  while i<=j do
    local cmd = buf:byte(i)
    if cmd == 29 then
      result[#result+1] = string.unpack(">i4", buf:sub(i+1, i+4))
      i = i+4
    elseif cmd == 28 then
      result[#result+1] = string.unpack(">i2", buf:sub(i+1, i+2))
      i = i+2
    elseif cmd >= 251 then -- Actually "and cmd ~= 255", but 255 is reserved
      result[#result+1] = -((cmd-251)*256)-string.byte(buf, i+1)-108
      i = i+1
    elseif cmd >= 247 then
      result[#result+1] = (cmd-247)*256+string.byte(buf, i+1)+108
      i = i+1
    elseif cmd >= 32 then
      result[#result+1] = cmd-139
    elseif cmd == 30 then -- 31 is reserved again
      local real = {parse_real(buf, i+1)}
      i = real[#real]
      real[#real] = nil
      result[#result+1] = tonumber(table.concat(real))
    else
      if cmd == 12 then
        i = i+1
        cmd = -buf:byte(i)-1
      end
      local op = operators[cmd]
      if not op then error[[Unknown CFF operator]] end
      result[op[1]] = op[2](result, strings)
    end
    i = i+1
  end
  return result
end
local function parse_charstring(cs, globalsubrs, subrs, result)
  result = result or {{false}, stemcount = 0}
  local lastresult = result[#result]
  local i = 1
  while i~=#cs+1 do
    local cmd = cs:byte(i)
    if cmd == 28 then
      lastresult[#lastresult+1] = string.unpack(">i2", cs:sub(i+1, i+2))
      i = i+2
    elseif cmd == 255 then
      lastresult[#lastresult+1] = string.unpack(">i4", cs:sub(i+1, i+4))/0x10000
      i = i+4
    elseif cmd >= 251 then
      lastresult[#lastresult+1] = -((cmd-251)*256)-string.byte(cs, i+1)-108
      i = i+1
    elseif cmd >= 247 then
      lastresult[#lastresult+1] = (cmd-247)*256+string.byte(cs, i+1)+108
      i = i+1
    elseif cmd >= 32 then
      lastresult[#lastresult+1] = cmd-139
    elseif cmd == 10 then
      local idx = lastresult[#lastresult]+subrs.bias
      local subr = subrs[idx]
      subrs.used[idx] = true
      lastresult[#lastresult] = nil
      parse_charstring(subr, globalsubrs, subrs, result)
      lastresult = result[#result]
    elseif cmd == 29 then
      local idx = lastresult[#lastresult]+globalsubrs.bias
      local subr = globalsubrs[idx]
      globalsubrs.used[idx] = true
      lastresult[#lastresult] = nil
      parse_charstring(subr, globalsubrs, subrs, result)
      lastresult = result[#result]
    elseif cmd == 11 then
      break -- We do not keep subroutines, so drop returns and continue with the outer commands
    elseif cmd == 12 then
      i = i+1
      cmd = cs:byte(i)
      lastresult[1] = -cmd-1
      lastresult = {false}
      result[#result+1] = lastresult
    elseif cmd == 19 or cmd == 20 then
      if #result == 1 then
        lastresult = {}
        result[#result+1] = lastresult
      end
      lastresult[1] = cmd
      local newi = i+(result.stemcount+7)//8
      lastresult[2] = cs:sub(i+1, newi)
      i = newi
    else
      if cmd == 21 and #result == 1 then
        table.insert(result, 1, {false})
        if #lastresult == 4 then
          result[1][2] = lastresult[2]
          table.remove(lastresult, 2)
        end
      elseif (cmd == 4 or cmd == 22) and #result == 1 then
        table.insert(result, 1, {false})
        if #lastresult == 3 then
          result[1][2] = lastresult[2]
          table.remove(lastresult, 2)
        end
      elseif cmd == 14 and #result == 1 then
        table.insert(result, 1, {false})
        if #lastresult == 2 or #lastresult == 6 then
          result[1][2] = lastresult[2]
          table.remove(lastresult, 2)
        end
      elseif cmd == 1 or cmd == 3 or cmd == 18 or cmd == 23 then
        if #result == 1 then
          table.insert(result, 1, {false})
          if #lastresult % 2 == 0 then
            result[1][2] = lastresult[2]
            table.remove(lastresult, 2)
          end
        end
        result.stemcount = result.stemcount + #lastresult//2
      end
      lastresult[1] = cmd
      lastresult =  {false}
      result[#result+1] = lastresult
    end
    i = i+1
  end
  return result
end
local function parse_charset(buf, i0, offset, strings, num)
  if not offset then offset = 0 end
  if offset == 0 then
    return ISOAdobe
  elseif offset == 1 then
    return Expert
  elseif offset == 2 then
    return ExpertSubset
  else offset = i0+offset end
  local format
  format, offset = string.unpack(">B", buf, offset)
  local charset = {[0] = 0}
  if format == 0 then
    for i=1,num-1 do
      charset[i], offset = string.unpack(">I2", buf, offset)
    end
  elseif format == 1 then
    local i = 1
    while i < num do
      local first, nLeft
      first, nLeft, offset = string.unpack(">I2I1", buf, offset)
      for j=0,nLeft do
        charset[i+j] = first+j
      end
      i = i+1+nLeft
    end
  elseif format == 2 then
    local i = 1
    while i < num do
      local first, nLeft
      first, nLeft, offset = string.unpack(">I2I2", buf, offset)
      for j=0,nLeft do
        charset[i+j] = first+j
      end
      i = i+1+nLeft
    end
  else
    error[[Invalid Charset format]]
  end
  if strings then -- We are not CID-keyed, so we should use strings instead of numbers
    local string_charset = {}
    for i=#charset,0,-1 do
      local sid = charset[i]
      charset[i] = nil
      string_charset[i] = stdStrings[sid] or strings[sid-#stdStrings]
    end
    charset = string_charset
  end
  return charset
end
local function parse_encoding(buf, i0, offset, CharStrings)
  if not offset then offset = 0 end
  if offset == 0 then
    error[[TODO]]
    return "StandardEncoding"
  elseif offset == 1 then
    error[[TODO]]
    return "ExpertEncoding"
  else offset = i0+offset end
  local format, num
  format, num, offset = string.unpack(">BB", buf, offset)
  local encoding = {}
  if format == 0 then
    for i=1,num do
      local code
      code, offset = string.unpack(">B", buf, offset)
      encoding[code] = CharStrings[i]
    end
  elseif format == 1 then
    local i = 1
    while i <= num do
      local first, nLeft
      first, nLeft, offset = string.unpack(">BB", buf, offset)
      for j=0,nLeft do
        encoding[first + j] = CharStrings[i + j]
      end
      i = i+1+nLeft
    end
  else
    error[[Invalid Encoding format]]
  end
  return encoding
end
local function parse_fdselect(buf, offset, CharStrings)
  local format
  format, offset = string.unpack(">B", buf, offset)
  if format == 0 then
    for i=1,#CharStrings-1 do
      local code
      code, offset = string.unpack(">B", buf, offset)
      CharStrings[i][3] = code + 1
    end -- Reimplement with string.byte
  elseif format == 3 then
    local count, last
    count, offset = string.unpack(">I2", buf, offset)
    for i=1,count do
      local first, code, after = string.unpack(">I2BI2", buf, offset)
      for j=first, after-1 do
        CharStrings[j][3] = code + 1
      end
      offset = offset + 3
    end
  else
    error[[Invalid FDSelect format]]
  end
end
local function applyencoding(buf, i, usedcids, encoding)
  local usednames = {}
  local numglyphs
  numglyphs, i = string.unpack(">I2", buf, i)
  local stroffset = 2*numglyphs + i
  local names = setmetatable({}, {__index = function(t, i)
    for j=#t+1,i do
      t[j], stroffset = string.unpack("s1", buf, stroffset)
    end
    return t[i]
  end})
  local newusedcids = {}
  for j=1,#usedcids do
    local name = encoding[usedcids[j][1]]
    if name then
      local new = {old = usedcids[j]}
      usednames[name], newusedcids[j] = new, new
    else
      newusedcids[j] = {j} -- FIXME: Someone used a character which does not exists in the encoding.
      -- This should probably at least trigger a warning.
    end
  end
  for j=1,numglyphs do
    local name
    name, i = string.unpack(">I2", buf, i)
    if name < 258 then
      name = stdnames[name]
    else
      name = names[name-257]
    end
    if usednames[name] then
      usednames[name][1] = j-1
      usednames[name] = nil
    end
  end
  if next(usednames) then
    error[[Missing character]]
  end
  return newusedcids
end
-- The encoding parameter might be:
-- an encoding dictionary - Use the supplied encoding
-- true - Use the build-in encoding
-- false - Use GIDs
-- nil - Use CIDs, falling back to GIDs in name.based fonts
function myfunc(buf, i0, fontid, usedcids, encoding, trust_widths)
-- return function(filename, fontid)
  fontid = fontid or 1
  local major, minor, hdrSize, offSize = string.unpack(">BBBB", buf, i0)
  if major ~= 1 then error[[Unsupported CFF version]] end
  -- local offfmt = offsetfmt:format(offSize)
  local nameoffsets, topoffsets, stringoffsets, globalsubrs
  local i = i0+hdrSize
  nameoffsets, i = parse_index(buf, i)
  topoffsets, i = parse_index(buf, i)
  stringoffsets, i = parse_index(buf, i)
  globalsubrs, i = parse_index(buf, i)
  local strings = {}
  for j=1,#stringoffsets-1 do
    strings[j] = buf:sub(stringoffsets[j], stringoffsets[j+1]-1)
  end
  if #nameoffsets ~= #topoffsets then error[[Inconsistant size of FontSet]] end
  if fontid >= #nameoffsets then error[[Invalid font id]] end
  local top = parse_dict(buf, topoffsets[fontid], topoffsets[fontid+1]-1, strings)
  top.FontName = buf:sub(nameoffsets[fontid], nameoffsets[fontid+1]-1)
  local gsubrsdict = {}
  for i=1,#globalsubrs-1 do
    gsubrsdict[i] = buf:sub(globalsubrs[i], globalsubrs[i+1]-1)
  end
  gsubrsdict.used = {}
  gsubrsdict.bias = #gsubrsdict < 1240 and 108 or #gsubrsdict < 33900 and 1132 or 32769
  top.GlobalSubrs = gsubrsdict
  local CharStrings = parse_index(buf, i0+top.CharStrings)
  if not not encoding ~= encoding and (encoding or top.ROS) then -- If we use the build-in encoding *or* GIDs, we do not need to waste our time making sense of the charset
    local charset = parse_charset(buf, i0, top.charset, not top.ROS and strings, #CharStrings-1)
    named_charstrings = {}
    for i=1,#CharStrings-1 do
      named_charstrings[charset[i-1]] = {CharStrings[i], CharStrings[i+1]-1}
    end
    CharStrings = named_charstrings
  else
    for i=1,#CharStrings-1 do
      CharStrings[i-1] = {CharStrings[i], CharStrings[i+1]-1}
    end
    CharStrings[#CharStrings] = nil
    CharStrings[#CharStrings] = nil
  end
  -- top.CharStrings = named_charstrings
  if not top.ROS then
    -- if encoding == true and top.Encoding < 3 then
      -- if not reencode and parsed_t1.Encoding == "StandardEncoding" then
      --   reencode = kpse.find_file("8a.enc", "enc files")
      -- end
    -- end
    if encoding == true then -- Use the built-in encoding
      CharStrings = parse_encoding(buf, i0, top.Encoding, CharStrings)
    elseif encoding then
      encoding = require'luametalatex-font-enc'(encoding)
      local encoded = {}
      for i, n in pairs(encoding) do
        encoded[i] = CharStrings[n]
      end
      CharStrings = encoded
    end -- else: Use GIDs
    top.Privates = {parse_dict(buf, i0+top.Private[2], i0+top.Private[2]+top.Private[1]-1, strings)}
    local subrs = top.Privates[1].Subrs
    if subrs then
      subrs = parse_index(buf, i0+top.Private[2]+subrs)
      local subrsdict ={}
      for j=1,#subrs-1 do
        subrsdict[j] = buf:sub(subrs[j], subrs[j+1]-1)
      end
      subrsdict.used = {}
      subrsdict.bias = #subrsdict < 1240 and 108 or #subrsdict < 33900 and 1132 or 32769
      top.Privates[1].Subrs = subrsdict
    end
    top.Private = nil
  else
    assert(not encoding) -- FIXME: If we actually get these from OpenType, the glyph names might be hidden there...
                                -- Would that even be allowed?
    local fonts = parse_index(buf, i0+top.FDArray)
    local privates = {}
    top.Privates = privates
    for i=1,#fonts-1 do
      local font = fonts[i]
      local fontdir = parse_dict(buf, fonts[i], fonts[i+1]-1, strings)
      privates[i] = parse_dict(buf, i0+fontdir.Private[2], i0+fontdir.Private[2]+fontdir.Private[1]-1, strings)
      privates[i].FontName = fontdir.FontName
      local subrs = privates[i].Subrs
      if subrs then
        subrs = parse_index(buf, i0+fontdir.Private[2]+subrs)
        local subrsdict ={}
        for j=1,#subrs-1 do
          subrsdict[j] = buf:sub(subrs[j], subrs[j+1]-1)
        end
        subrsdict.used = {}
        subrsdict.bias = #subrsdict < 1240 and 108 or #subrsdict < 33900 and 1132 or 32769
        privates[i].Subrs = subrsdict
      end
    end
    top.FDArray = nil
    parse_fdselect(buf, i0+top.FDSelect, CharStrings)
  end
  local glyphs = {}
  -- if false and usedcids then -- Subsetting FIXME: Disabled, because other tables have to be fixed up first
  if usedcids then -- Subsetting FIXME: Should be Disabled, because other tables have to be fixed up first -- Actually seems to work now, let's test it a bit more
    local usedfonts = {}
    for i=1,#usedcids do
      local cid = usedcids[i][1]
      local cs = CharStrings[cid]
      glyphs[i] = {cs = buf:sub(cs[1], cs[2]), index = cid, cidfont = cs[3], usedcid = usedcids[i]}
      usedfonts[CharStrings[cid][3] or 1] = true
    end
    local lastfont = 0
    for i=1,#top.Privates do
      if usedfonts[i] then
        lastfont = lastfont + 1
        usedfonts[i] = lastfont
        top.Privates[lastfont] = top.Privates[i]
      end
    end
    for i=lastfont+1,#top.Privates do
      top.Privates[i] = nil
    end
    for i=1,#glyphs do
      glyphs[i].cidfont = usedfonts[glyphs[i].cidfont]
    end
    -- TODO: CIDFont / Privates subsetting... DONE(?)
    -- TODO: Subrs subsetting... Instead of deleting unused SubRs, we only make them empty.
    --       This avoids problems with renumberings whiuch would have to be consitant across
    --       Fonts in some odd way, because they might be used by globalsubrs.
    for i=1,#glyphs do
      local g = glyphs[i]
      local private = top.Privates[g.cidfont or 1]
      local parsed = parse_charstring(g.cs, top.GlobalSubrs, private.Subrs) -- TODO: Implement
      local width = parsed[1][2]
      if width then
        width = width + (private.nominalWidthX or 0)
      else
        width = private.defaultWidthX or 0
      end
      local m = top.FontMatrix or {.001, 0, 0, .001, 0, 0}
      width = width * m[1] + m[3] -- I really have no idea why m[3] /= 0 might happen, but why not?
      width = math.floor(width*1000+.5) -- Thats rescale into "PDF glyph space"
      if g.usedcid[2] ~= width then print("MISMATCH:", g.usedcid[1], g.usedcid[2], width) end
      g.usedcid[2] = width
    end
    for i=1,#top.GlobalSubrs do
      if not top.GlobalSubrs.used[i] then
        top.GlobalSubrs[i] = ""
      end
    end
    for _, priv in ipairs(top.Privates) do if priv.Subrs then
      for i=1,#priv.Subrs do
        if not priv.Subrs.used[i] then
          priv.Subrs[i] = ""
        end
      end
    end end
  else
    for i, cs in pairs(CharStrings) do -- Not subsetting
      glyphs[#glyphs+1] = {cs = buf:sub(cs[1], cs[2]), index = i, cidfont = cs.font}
    end
  end
  top.glyphs = glyphs
  table.sort(glyphs, function(a,b)return a.index<b.index end)
  local bbox
  if top.FontMatrix then
    local x0, y0 = apply_matrix(top.FontMatrix, top.FontBBox[1], top.FontBBox[2])
    local x1, y1 = apply_matrix(top.FontMatrix, top.FontBBox[3], top.FontBBox[4])
    bbox = {x0, y0, x1, y1}
  else
    bbox = top.FontBBox
  end
  return require'luametalatex-font-cff'(top), bbox
end
-- local file = io.open(arg[1])
-- local buf = file:read'a'
-- file:close()
-- io.open(arg[3], 'w'):write(myfunc(buf, 1, 1, nil, {{3}, {200}, {1000}, {1329}, {1330}, {1331}})):close()
return function(filename, encoding) return function(fontdir, usedcids)
  local file = io.open(filename)
  local buf = file:read'a'
  local i = 1
  file:close()
  local magic = buf:sub(1, 4)
  if magic == "ttcf" or magic == "OTTO" then
    -- assert(not encoding) -- nil or false
    encoding = encoding or false
    local magic, tables = sfnt.parse(buf, 1) -- TODO: Interpret widths etc, they might differ from the CFF ones.
    assert(magic == "OTTO")
    -- Also CFF2 would be nice to have
    i = tables['CFF '][1]
  end
  local content, bbox = myfunc(buf, i, 1, usedcids, encoding)
  fontdir.bbox = bbox
  return content
end end
-- io.open(arg[3], 'w'):write(myfunc(buf, 1, 1, require'parseEnc'(arg[2]), {{string.byte'a'}, {string.byte'b'}, {string.byte'-'}})):close()
