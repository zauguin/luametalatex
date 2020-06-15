local upper_mask = (1<<20)-1<<44
local shifted_sign = 1<<43
local function scale(factor1, factor2)
  local result = factor1*factor2 >> 20
  if result & shifted_sign == shifted_sign then
    return result | upper_mask
  else
    return result
  end
end
local function read_scaled(buf, i, count, factor)
  local result = {}
  for j = 1, count do
    result[j] = scale(factor, string.unpack(">i4", buf, i + (j-1)*4))
  end
  return result,  i + count * 4
end
local function parse_ligkern(buf, offset, r_boundary, kerns)
  local kerning, ligatures, done = {}, {}, {}
  repeat
    local skip, next, op, rem
    skip, next, op, rem, offset = string.unpack("BBBB", buf, offset)
    if skip > 128 then break end
    if next == r_boundary then next = "right_boundary" end
    if not done[next] then
      done[next] = true
      if op >= 128 then
        kerning[next] = kerns[(op - 128 << 8) + rem + 1]
      else
        ligatures[next] = {
          type = op,
          char = rem,
        }
      end
    end
  until skip == 128
  return next(kerning) and kerning or nil, next(ligatures) and ligatures or nil
end
local function parse_tfm(buf, i, size)
  local lf, lh, bc, ec, nw, nh, nd, ni, nl, nk, ne, np
  lf, lh, bc, ec, nw, nh, nd, ni, nl, nk, ne, np, i =
      string.unpack(">HHHHHHHHHHHH", buf, i)
  assert(bc-1 <= ec and ec <= 255)
  assert(lf == 6 + lh + (ec - bc + 1) + nw + nh + nd + ni + nl + nk + ne + np)
  assert(lh >= 2)
  local checksum, designsize
  checksum, designsize = string.unpack(">I4i4", buf, i)
  i = i + 4*lh
  designsize = designsize>>4 -- Adjust TFM sizes to sp
  if size < 0 then
    size = math.floor(-size*designsize/1000+.5)
  end
  -- In contrast to TeX, we will assume that multiplication of two 32 bit
  -- integers never overflows. This is safe if Lua integers have 64 bit,
  -- which is the default.
  local ligatureoffset, r_boundary
  local widths, heights, depths, italics, kerns, parameters
  local extensibles = {}
  do
    local i = i + (ec - bc + 1) * 4
    widths, i = read_scaled(buf, i, nw, size)
    heights, i = read_scaled(buf, i, nh, size)
    depths, i = read_scaled(buf, i, nd, size)
    italics, i = read_scaled(buf, i, ni, size)
    for k,v in ipairs(italics) do if v == 0 then italics[k] = nil end end
    ligatureoffset = i
    if nl ~= 0 and string.byte(buf, i, i) == 255 then
      r_boundary = string.byte(buf, i+1, i+1)
    end
    i = i + nl * 4
    kerns, i = read_scaled(buf, i, nk, size)
    for j = 1, ne do
      local ext = {}
      ext.top, ext.mid, ext.bot, ext.rep, i = string.unpack("BBBB", buf, i)
      for k,v in pairs(ext) do
        if v == 0 then ext[k] = nil end
      end
      extensibles[j] = ext
    end
    local slant = np ~= 0 and string.unpack(">i4", buf, i) >> 4 or nil
    parameters = read_scaled(buf, i, np, size)
    parameters[1] = slant
  end
  local characters = {}
  for cc = bc,ec do
    local charinfo
    charinfo, i = string.unpack(">I4", buf, i)
    if (charinfo >> 24) & 0xFF ~= 0 then
      local char = {
        width = widths[((charinfo >> 24) & 0xFF) + 1],
        height = heights[((charinfo >> 20) & 0xF) + 1],
        depth = depths[((charinfo >> 16) & 0xF) + 1],
        italic = italics[((charinfo >> 10) & 0xF) + 1],
      }
      local tag = (charinfo >> 8) & 0x3
      if tag == 0 then
      elseif tag == 1 then
        local offset = (charinfo & 0xFF) * 4 + ligatureoffset
        if string.byte(buf, offset, offset) > 128 then
          offset = string.unpack(">H", buf, offset + 2) * 4 + ligatureoffset
        end
        char.kerns, char.ligatures = parse_ligkern(buf, offset, r_boundary, kerns)
      elseif tag == 2 then
        char.next = charinfo & 0xFF
      elseif tag == 3 then
        char.extensible = extensibles[(charinfo & 0xFF) + 1]
      end
      characters[cc] = char
    end
  end
  if nl ~= 0 and string.byte(buf, ligatureoffset + (nl-1) * 4) == 255 then
    local char = {}
    characters.left_boundary = char
    local offset = string.unpack(">H", buf, ligatureoffset + nl * 4 - 2) * 4 + ligatureoffset
    char.kerns, char.ligatures = parse_ligkern(buf, offset, r_boundary, kerns)
  end
  return {
    checksum = checksum,
    direction = 0,
    embedding = "unknown",
    -- encodingbytes = 0,
    extend = 1000,
    format = "unknown",
    identity = "unknown",
    mode = 0,
    slant = 0,
    squeeze = 1000,
    oldmath = false,
    streamprovider = 0,
    tounicode = 0,
    type = "unknown",
    units_per_em = 0,
    used = false,
    width = 0,
    writingmode = "unknown",
    size = size,
    designsize = designsize,
    parameters = parameters,
    characters = characters,
  }
end
local basename = ((1-lpeg.S'\\/')^0*lpeg.S'\\/')^0*lpeg.C((1-lpeg.P'.tfm'*-1)^0)
return function(name, size)
  local filename = kpse.find_file(name, 'tfm', true)
  if not filename then return end
  local f = io.open(filename)
  if not f then return end
  local buf = f:read'*a'
  f:close()
  local result = parse_tfm(buf, 1, size)
  result.name = basename:match(name)
  return result
end
