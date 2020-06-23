local function ignore() end
local parse = setmetatable({
  -- IHDR = below,
  -- PLTE = below,
  -- IDAT = below,
  -- IEND = below,
  -- I'm not yet sure what to do about the following four color management chunks:
  -- These two will probably be ignored (if you care about this stuff, you probably
  -- prefer an ICC profile anyway. Also especially cHRM requires some weird computations.)
  -- cHRM = TODO, -- ignore?
  -- gAMA = TODO, -- ignore?
  -- iCCP is implemented, but profiles are not cached, so it might include the
  -- same profile many times
  -- iCCP = below,
  -- I would expect sRGB to be the most common, but it is a bit complicated because
  -- PDF seems to require us to ship an actual ICC profile to support sRGB. Maybe later.
  -- sRGB = TODO,
  sBIT = ignore,
  bKGD = ignore, -- Background color. Ignored since we support transparency
  hIST = ignore, -- Color histogram
  -- tRNS = below,
  -- pHYs = below, -- resolution information
  sPLT = ignore, -- Suggested palette but we support full truetype
  tIME = ignore, -- The following only store metadata
  iTXt = ignore,
  tEXt = ignore,
  zTXt = ignore,
}, {
    __index = function(_, n)
      print("Table " .. n .. " unsupported") -- FIXME: Handle extensions by detecing if they are critical etc.
      return ignore
    end
  })
function parse.IHDR(buf, i, after, ctxt)
  if next(ctxt) then
    error[[The header should come first]]
  end
  local compression, filter
  ctxt.width, ctxt.height,
  ctxt.bitdepth, ctxt.colortype,
  compression, filter,
  ctxt.interlace, i = string.unpack(">I4I4I1I1I1I1I1", buf, i)
  if i ~= after then
    return [[Invalid header size]]
  end
  if compression ~= 0 then
    error [[Unsupported compression mode]]
  end
  if filter ~= 0 then
    error [[Unsupported filter mode]]
  end
end
function parse.PLTE(buf, i, after, ctxt)
  if ctxt.PLTE then
    error[[Multiple palettes detected]]
  end
  if (after-i)%3 ~= 0 then
    error[[Invalid palette lenght]]
  end
  ctxt.PLTE_len = (after-i) // 3
  ctxt.PLTE = string.sub(buf, i, after-1)
end
function parse.tRNS(buf, i, after, ctxt)
  if ctxt.colortype == 3 then
    local count = assert(ctxt.PLTE_len)
    local patt = lpeg.P(1) * lpeg.Cc'\xff'
    for j=0,after-i-1 do
      local off = i+j
      patt = lpeg.P(string.char(j)) * lpeg.Cc(buf:sub(off, off)) + patt
    end
    ctxt.tRNS = lpeg.Cs(lpeg.Cg(patt)^0)
  elseif ctxt.colortype == 0 then
    local color
    color, i = string.unpack(">I2", buf, i)
    assert(i == after)
    ctxt.tRNS = string.format('%i %i', color, color)
  elseif ctxt.colortype == 2 then
    local r, g, b
    r, g, b, i = string.unpack(">I2I2I2", buf, i)
    assert(i == after)
    ctxt.tRNS = string.format('%i %i %i %i %i %i', r, r, g, g, b, b)
  end
end
local meterperinch = 0.0254
function parse.pHYs(buf, i, after, ctxt)
  local xres, yres, unit
  xres, yres, unit, i = string.unpack('>I4I4I1', buf, i)
  if unit == 0 then
    if xres > yres then
      ctxt.xres, ctxt.yres = xres/yres, 0
    elseif xres < yres then
      ctxt.xres, ctxt.yres = 0, yres/xres
    end
  elseif unit == 1 then
    ctxt.xres, ctxt.yres = xres * meterperinch, yres * meterperinch
  else
    error[[Invalid unit]]
  end
  assert(i == after)
end
function parse.iCCP(buf, i, after, ctxt)
  local j = buf:find('\0', i, true)
  assert(j+1<after)
  local name = buf:sub(i, j-1)
  print('ICC Profile name: ' .. name)
  assert(buf:byte(j+1) == 0) -- The only known compression mode
  ctxt.iCCP = xzip.decompress(buf:sub(j+2, after-1))
end
function parse.IDAT(buf, i, after, ctxt)
  ctxt.IDAT = ctxt.IDAT or {}
  table.insert(ctxt.IDAT, buf:sub(i, after-1))
end
function parse.IEND(buf, i, after)
  if i ~= after then
    error[[Unexpected data in end chunk]]
  end
end

local function run(buf, i, len, limit)
  i = i or 1
  len = i+(len or #buf)
  if buf:sub(i,i+7) ~= "\x89PNG\x0D\x0A\x1A\x0A" then
    error[[You lied. This isn't a PNG file.]]
  end
  i = i+8
  local chunks = {}
  while i < len do
    local length, tp, off = string.unpack(">I4c4", buf, i)
    if tp == limit then break end
    parse[tp](buf, off, off + length, chunks)
    i = off + length + 4
  end
  return chunks, i
end
local function passes(buf, width, height, bitdepth, colortype)
  local stride = (bitdepth == 16 and 2 or 1) * (1 + (colortype&3 == 2 and 2 or 0) + (colortype&4)/4)
  local passes = {
    {(width+7)//8, (height+7)//8},
    {(width+3)//8, (height+7)//8},
    {(width+3)//4, (height+3)//8},
    {(width+1)//4, (height+3)//4},
    {(width+1)//2, (height+1)//4},
    { width   //2, (height+1)//2},
    { width      ,  height   //2},
  }
  local off = 1
  local result
  for i=1,#passes do
    local xsize, ysize = passes[i][1], passes[i][2]
    if xsize ~= 0 and ysize ~= 0 then
      if bitdepth < 8 then
        xsize = (xsize * bitdepth + 7) // 8
      end
      local after = off + (xsize+1) * stride * ysize
      local pass = pngdecode.applyfilter(
        buf:sub(off, after-1),
        xsize,
        ysize,
        stride)
      if bitdepth < 8 then
        pass = pngdecode.expand(pass, passes[i][1], ysize, bitdepth, xsize)
      end
      result = pngdecode.interlace(width, height, stride, i, pass, result)
      off = after
    end
  end
  assert(off == #buf+1)
  return result
end

local png_functions = {}

function png_functions.scan(img)
  local file = io.open(img.filepath)
  if not file then
    error[[PDF image could not be opened.]]
  end
  local buf = file:read'a'
  file:close()
  local t = run(buf, 1, #buf, 'IDAT')
  img.pages = 1
  img.page = 1
  img.rotation = 0
  img.xsize, img.ysize = t.width, t.height
  img.xres, img.yres = t.xres or 0, t.yres or 0
  img.colordepth = t.bitdepth
end

local pdf_escape = require'luametalatex-pdf-escape'.escape_bytes

local function rawimage(t, content)
  content = xzip.decompress(content)
  if t.interlace == 1 then
    content = passes(content, t.width, t.height, t.bitdepth, t.colortype)
  else
    local xsize = t.width
    if t.bitdepth < 8 then
      xsize = (xsize * t.bitdepth + 7) // 8
    end
    local colortype = t.colortype
    content = pngdecode.applyfilter(
      content,
      xsize,
      t.height,
      (t.bitdepth == 16 and 2 or 1) * (1 + (colortype&3 == 2 and 2 or 0) + (colortype&4)/4))
  end
  return content
end

function png_functions.write(pfile, img)
  local file = io.open(img.filepath)
  if not file then
    error[[PDF image could not be opened.]]
  end
  local buf = file:read'a'
  file:close()
  local t = run(buf, 1, #buf, 'IEND')
  local colorspace
  local colortype = t.colortype
  if img.colorspace then
    colorspace = string.format(' %i 0 R', img.colorspace)
  elseif t.iCCP then
    local icc_ref = pfile:stream(nil, '/N ' .. tostring(colortype & 2 == 2 and '3' or '1'), t.iCCP)
    colorspace = string.format('[/ICCBased %i 0 R]', icc_ref)
  elseif colortype & 2 == 2 then -- RGB
    colorspace = '/DeviceRGB'
  else -- Gray
    colorspace = '/DeviceGray'
  end
  if colortype & 1 == 1 then -- Indexed
    colorspace = string.format('[/Indexed%s %i%s]', colorspace, t.PLTE_len-1, pdf_escape(t.PLTE))
  end
  local colordepth = t.interlace == 1 and 8 or img.colordepth
  local dict = string.format("/Subtype/Image/Width %i/Height %i/BitsPerComponent %i/ColorSpace%s", img.xsize, img.ysize, colordepth, colorspace)

  local content = table.concat(t.IDAT)
  local copy -- = true
  if copy and (t.interlace == 1 or colortype & 4 == 4) then -- TODO: Add additional conditions
    copy = false
  end

  if copy then
    -- In this case we never have to deal with an alpha component
    dict = string.format(
        '%s/Filter/FlateDecode/DecodeParms<</Colors %i/Columns %i/BitsPerComponent %i/Predictor 10>>',
        dict, colortype == 2 and 3 or 1, img.xsize, colordepth)
  else
    content = rawimage(t, content)
    if colortype & 4 == 4 then -- Alpha channel present
      local mask
      content, mask = pngdecode.splitmask(
        content,
        img.xsize,
        img.ysize,
        1 + (colortype&2),
        colordepth//8) -- colordepth must be 8 or 16 if alpha is present
      local mask_dict = string.format("/Subtype/Image/Width %i/Height %i/BitsPerComponent %i/ColorSpace/DeviceGray", img.xsize, img.ysize, colordepth)
      local objnum = pfile:stream(nil, mask_dict, mask)
      dict = string.format('%s/SMask %i 0 R', dict, objnum)
    end
  end

  if t.tRNS then
    if colortype == 3 then
      local unpacked = copy and rawimage(t, content) or content
      if colordepth ~= 8 then
        unpacked = pngdecode.expand(unpacked, img.xsize, img.ysize, colordepth, (img.xsize*colordepth+7)//8)
      end
      unpacked = t.tRNS:match(unpacked)
      local mask_dict = string.format("/Subtype/Image/Width %i/Height %i/BitsPerComponent 8/ColorSpace/DeviceGray", img.xsize, img.ysize)
      local objnum = pfile:stream(nil, mask_dict, unpacked)
      dict = string.format('%s/SMask %i 0 R', dict, objnum)
    else
      dict = string.format('%s/Mask[%s]', dict, t.tRNS)
    end
  end

  local attr = img.attr
  if attr then
    dict = dict .. attr
  end
  pfile:stream(img.objnum, dict, content, nil, copy)
end

return png_functions
