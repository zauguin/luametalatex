local strip_floats = require'luametalatex-pdf-utils'.strip_floats

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
function parse.sRGB(buf, i, after, ctxt)
  assert(i+1 == after)
  ctxt.sRGB = buf:char(i)
end
function parse.iCCP(buf, i, after, ctxt)
  local j = buf:find('\0', i, true)
  assert(j+1<after)
  -- local name = buf:sub(i, j-1)
  -- print('ICC Profile name: ' .. name)
  assert(buf:byte(j+1) == 0) -- The only known compression mode
  ctxt.iCCP = buf:sub(j+2, after-1)
  -- ctxt.iCCP = xzip.decompress(buf:sub(j+2, after-1))
end
function parse.gAMA(buf, i, after, ctxt)
  local gamma, i = string.unpack(">I4", buf, i)
  assert(after == i)
  ctxt.gAMA = 100000/gamma
end
function parse.cHRM(buf, i, after, ctxt)
  local x_W, y_W, x_R, y_R, x_G, y_G, x_B, y_B, i = string.unpack(">I4I4I4I4I4I4I4I4", buf, i)
  assert(after == i)
  x_W, y_W, x_R, y_R, x_G, y_G, x_B, y_B = x_W/100000, y_W/100000, x_R/100000, y_R/100000,
                                           x_G/100000, y_G/100000, x_B/100000, y_B/100000
  local z = y_W*((x_G-x_B)*y_R-(x_R-x_B)*y_G+(x_R-x_G)*y_B)
  z = 1/z
  local Y_A = y_R*((x_G-x_B)*y_W-(x_W-x_B)*y_G+(x_W-x_G)*y_B) * z
  local X_A, Z_A = Y_A*x_R/y_R, Y_A*((1-x_R)/y_R-1)
  local Y_B = -y_G*((x_R-x_B)*y_W-(x_W-x_B)*y_R+(x_W-x_R)*y_B) * z
  local X_B, Z_B = Y_B*x_G/y_G, Y_B*((1-x_G)/y_G-1)
  local Y_C = y_B*((x_R-x_G)*y_W-(x_W-x_G)*y_R+(x_W-x_R)*y_G) * z
  local X_C, Z_C = Y_C*x_B/y_B, Y_C*((1-x_B)/y_B-1)

  local X_W, Y_W, Z_W = X_A+X_B+X_C, Y_A+Y_B+Y_C, Z_A+Z_B+Z_C
  ctxt.cHRM = strip_floats(string.format("/WhitePoint[%f %f %f]/Matrix[%f %f %f %f %f %f %f %f %f]",
      X_W, Y_W, Z_W,
      X_A, Y_A, Z_A,
      X_B, Y_B, Z_B,
      X_C, Y_C, Z_C))
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

local srgb_colorspace
local intents = {[0]=
  '/Intent/Perceptual',
  '/Intent/RelativeColorimetric',
  '/Intent/Saturation',
  '/Intent/AbsoluteColorimetric',
}
local function srgb_lookup(pfile, intent)
  if not srgb_colorspace then
    local f = io.open(kpse.find_file'sRGB.icc.zlib')
    local profile = f:read'a'
    f:close()
    local objnum = pfile:stream(nil, '/Filter/FlateDecode/N ' .. tostring(colortype & 2 == 2 and '3' or '1'), t.iCCP, nil, true)
    srgb_colorspace = string.format('[/ICCBased %i 0 R]', objnum)
  end
  return objnum, intents[intent] or ''
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
  local intent = ''
  local colortype = t.colortype
  if img.colorspace then
    colorspace = string.format(' %i 0 R', img.colorspace)
  elseif t.iCCP then
    local icc_ref = pfile:stream(nil, '/Filter/FlateDecode/N ' .. tostring(colortype & 2 == 2 and '3' or '1'), t.iCCP, nil, true)
    colorspace = string.format('[/ICCBased %i 0 R]', icc_ref)
  elseif t.sRGB then
    colorspace, intent = srgb_lookup(pfile, t.sRGB)
  elseif colortype & 2 == 2 then -- RGB
    if t.cHRM then
      local gamma = t.gAMA or 2.2
      gamma = gamma and strip_floats(string.format("/Gamma[%f %f %f]", gamma, gamma, gamma)) or ''
      colorspace = string.format("[/CalRGB<<%s%s>>]", t.cHRM, gamma)
    else
      if t.gAMA then
        texio.write_nl'Warning: (PNG) Gamma correction without chromaticity information is unsupported. Gamma value will be ignored.'
      end
      colorspace = '/DeviceRGB'
    end
  else -- Gray
    if t.gAMA or t.cHRM then
      texio.write_nl'Warning: (PNG) Gamma correction and chromaticity specifications are only supported for RGB images.'
    end
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
