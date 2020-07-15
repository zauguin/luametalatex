local readfile = require'luametalatex-readfile'

local sfnt = require'luametalatex-font-sfnt'
local stdnames = require'luametalatex-font-ttf-data'
local function round(x)
  local i, f = math.modf(x)
  if f < 0 then
    return i - (f<=-0.5 and 1 or 0)
  else
    return i + (f>=-0.5 and 1 or 0)
  end
end
local function addglyph(glyph, usedcids, cidtogid)
  if string.unpack(">i2", glyph) < 0 then -- We have a composite glyph.
    -- This is a mess. Disaster will follow.
    local offset = 11
    while offset do
      local flags, component = string.unpack(">I2I2", glyph, offset)
      local gid = cidtogid[component]
      if not gid then
        gid = #usedcids
        usedcids[gid+1] = {component}
        cidtogid[component] = gid
      end
      glyph = glyph:sub(1, offset+1) .. string.pack(">I2", gid).. glyph:sub(offset+4)
      offset = flags&32==32 and offset + 4 + (flags&1==1 and 4 or 2) + (flags&8==8 and 2 or (flags&64==64 and 4 or (flags&128==128 and 8 or 0)))
    end
  end
  return glyph
end
local function readpostnames(buf, i, usedcids, encoding)
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
      local new = {}
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
return function(filename, fontid, reencode)
  local file <close> = readfile('truetype', filename)
  local buf = file()
  local magic, tables = sfnt.parse(buf, 1, fontid)
  if magic ~= "\0\1\0\0" then error[[Invalid TTF font]] end
  -- TODO: Parse post table and add reencoding support
  -- if tables.post and string.unpack(">I4", buf, tables.post[1]) == 0x00020000 and reencode then
  --   local encoding = require'parseEnc'(reencode)
  --   if encoding then
  --     local names = {}
  --     local off = tables.post[1] + 4
  --     for i = 1,string.unpack(">I2", buf, tables.maxp[1] + 4) do

  return function(fontdir, usedcids)
    if reencode and string.unpack(">I4", buf, tables.post[1]) == 0x00020000 then
      usedcids = readpostnames(buf, tables.post[1] + 32, usedcids, require'luametalatex-font-enc'(reencode))
    else
      usedcids = table.move(usedcids, 1, #usedcids, 1, {})
    end
    table.insert(usedcids, 1, {0})
    local newtables = {}
    newtables.head = buf:sub(tables.head[1], tables.head[1]+tables.head[2]-1)
    local bbox1, bbox2, bbox3, bbox4, scale, _
    scale, _, _, bbox1, bbox2, bbox3, bbox4 = string.unpack(">I2I8I8i2i2i2i2", buf, tables.head[1]+18)
    scale = 1000/scale
    fontdir.bbox = {math.floor(bbox1*scale), math.floor(bbox2*scale), math.ceil(bbox3*scale), math.ceil(bbox4*scale)}
    local cidtogid = {}
    for i=1,#usedcids do
      cidtogid[usedcids[i][1]] = i
    end
    local loca, glyf, locaOff, glyfOff = {}, {}, tables.loca[1], tables.glyf[1]
    hmtx = nil
    if string.unpack(">i2", buf, tables.head[1]+50) == 0 then -- short offsets
      local s, i = 0, 1
      while i <= #usedcids do
        local from, til = string.unpack(">I2I2", buf, locaOff+2*usedcids[i][1])
        loca[i] = string.pack(">I2", s)
        s = s+til-from
        glyf[i] = from ~= til and addglyph(buf:sub(glyfOff+from*2, glyfOff+til*2-1), usedcids, cidtogid) or ""
        i = i+1
      end
      loca[#usedcids+1] = string.pack(">I2", s)
    else -- long offsets
      local s, i = 0, 1
      while i <= #usedcids do
        local from, til = string.unpack(">I4I4", buf, locaOff+4*usedcids[i][1])
        loca[i] = string.pack(">I4", s)
        s = s+til-from
        glyf[i] = til == from and "" or addglyph(buf:sub(glyfOff+from, glyfOff+til-1), usedcids, cidtogid)
        i = i+1
      end
      loca[#usedcids+1] = string.pack(">I4", s)
    end
    newtables.loca = table.concat(loca)
    loca = nil
    newtables.glyf = table.concat(glyf)
    local hmtx = glyf
    glyf = nil
    for i = 1,#hmtx do hmtx[i] = nil end
    assert(tables.hhea[2] == 36)
    local numhmetrics = string.unpack(">I2", buf, tables.hhea[1]+34)
    newtables.hhea = buf:sub(tables.hhea[1], tables.hhea[1]+33) .. string.pack(">I2", #usedcids)
    local off = tables.hmtx[1]
    local finaladv, off2 = buf:sub(off+(numhmetrics-1)*4, off+numhmetrics*4-3), off+2*numhmetrics
    for i=1,#usedcids do
      if usedcids[i][1] < numhmetrics then
        hmtx[i] = buf:sub(off+usedcids[i][1]*4, off+usedcids[i][1]*4+3)
      else
        hmtx[i] = finaladv .. buf:sub(off2+usedcids[i][1]*2, off2+usedcids[i][1]*2+1)
      end
    end
    newtables.hmtx = table.concat(hmtx)
    newtables.maxp = buf:sub(tables.maxp[1], tables.maxp[1]+3) .. string.pack(">I2", #usedcids) .. buf:sub(tables.maxp[1]+6, tables.maxp[1]+tables.maxp[2]-1)
    if tables.fpgm then
      newtables.fpgm = buf:sub(tables.fpgm[1], tables.fpgm[1]+tables.fpgm[2]-1)
    end
    if tables.prep then
      newtables.prep = buf:sub(tables.prep[1], tables.prep[1]+tables.prep[2]-1)
    end
    if tables['cvt '] then
      newtables['cvt '] = buf:sub(tables['cvt '][1], tables['cvt '][1]+tables['cvt '][2]-1)
    end
    return sfnt.write(magic, newtables)
  end
end
