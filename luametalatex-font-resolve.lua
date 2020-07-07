font.read_tfm = require'luametalatex-font-tfm'
local read_vf = require'luametalatex-font-vf'
font.read_vf = read_vf
local fontmap = require'luametalatex-pdf-font-map'.fontmap
local callback_find = callback.find

local old_font_define = font.define
local old_addcharacters = font.addcharacters

require'luametalatex-pdf-font-map'.mapfile(kpse.find_file('pdftex.map', 'map', true))

local all_fonts = {}
font.fonts = all_fonts
function font.getfont(id)
  return all_fonts[id]
end

local fontextensions = {
  ttf = {"truetype", "truetype fonts",},
  otf = {"opentype", "opentype fonts",},
  pfb = {"type1", "type1 fonts",},
}
fontextensions.cff = fontextensions.otf
local fontformats = {
  fontextensions.pfb, fontextensions.otf, fontextensions.ttf,
}

local special_parser do
  local l = lpeg or require'lpeg'
  local space = l.S' '^0
  local name = (1-l.P' ')^1
  local reencode = name * space * 'ReEncodeFont'
  local digit = l.R'09'
  local number = digit^1 * ('.' * digit^0) + '.' * digit^1/tonumber
  local milli_stmt = number * space * ('SlantFont' * l.Cc'slant' + 'ExtendFont' * l.Cc'extend') / function(n, k)
    return k, (n*1000 + .5)//1
  end
  special_parser = l.Cf(l.Carg(1) * (space * (reencode + milli_stmt))^0 * space * -1, rawset)
end

function font.define(f)
  if (f.type or "unknown") == "unknown" then
    local vf = read_vf(f.name, f.size)
    if vf then
      f.type = 'virtual'
      f.fonts = vf.fonts
      local realchars = f.characters
      for cp, char in next, vf.characters do
        assert(realchars[cp]).commands = char.commands
      end
    else
      f.type = 'real'
    end
  end
  local format = f.format or "unknown"
  local encodingbytes = f.encodingbytes or (f.format:sub(5) == "type" and 2 or 1)
  f.encodingbytes = encodingbytes
  if encodingbytes == 1 and f.type ~= 'virtual' then
    -- map file lookup
    local entry = fontmap[f.name]
    if entry then
      local filename = entry[3]
      local format = filename and filename:sub(-4, -4) == '.' and fontextensions[filename:sub(-3, -1)]
      if format then
        f.format = format[1]
        f.filename = kpse.find_file(filename, format[2])
        local encoding = entry[4]
        if encoding then
          f.encoding = kpse.find_file(encoding, 'enc files')
        end
        if entry[5] then
          assert(special_parser:match(entry[5], 1, f))
        end
      else
        local done = false
        for _, format in ipairs(fontformats) do
          local filename = kpse.find_file(filename, format[2])
          if filename then
            f.filename = filename
            f.format = format[1]
            local encoding = entry[4]
            if encoding then
              f.encoding = kpse.find_file(encoding, 'enc files')
            end
            if entry[5] then
              assert(special_parser:match(entry[5], 1, f))
            end
            done = true
            break
          end
        end
        if not done then
          print('!', 'type3', require'inspect'(entry))
          f.format = "type3"
        end
      end
    else
      f.format = "type3"
    end
  end
  local id = old_font_define(f)
  all_fonts[id] = f
  if f.fonts then
    for i, f in next, f.fonts do
      if not f.id then
        f.id = assert(callback_find'define_font'(f.name, f.size or -1000))
      elseif f.id == 0 then
        f.id = id
      end
    end
  end
  return id
end

function font.addcharacters(fid, newdir)
  old_addcharacters(fid, newdir) -- The easy part, the remaining stuff gets crazy
  local fontdir = assert(all_fonts[fid], 'addcharacters expects an existing font')
  local fonts_map
  if newdir.fonts then -- FIXME: Handle default fonts table
    if fontdir.fonts then
      fonts_map = {}
      for i,f in next, newdir.fonts do
        if not f.id then
          f.id = assert(callback_find'define_font'(f.name, f.size or -1000))
        elseif f.id == 0 then
          f.id = fid
        end
        for j,ff in next, fontdir.fonts do
          if ff.id == f.id then
            fonts_map[i] = j
            goto FONT_MAPPING_SET -- A typical for ... do ... else ... end implemented using goto.
          end
        end
        -- NOT FOUND, so add it
        local new_f = #fontdir.fonts + 1
        fontdir.fonts[new_f] = f
        fonts_map[i] = f
        ::FONT_MAPPING_SET::
      end
    else
      fontdir.fonts = newdir.fonts
    end
  end
  for cp, glyph in next, newdir do
    local existing = fontdir[cp]
    if existing ~= glyph then
      if existing then
        texio.write_nl'Overwriting existing character. Here be dragons'
      end
    end
    if glyph.commands then
      local font_seen
      for _, cmd in ipairs(glyph.commands) do
        if cmd[1] == 'font' then
          font_seen = true
          cmd[2] = fonts_map[cmd[2]]
        elseif cmd[1] == 'slot' then
          font_seen = true
          cmd[2] = fonts_map[cmd[2]]
        elseif not font_seen and cmd[1] == 'char' then
          font_seen = true
          cmd[1], cmd[2], cmd[3] = 'slot', fonts_map[1], cmd[2]
        end
      end
    end
  end
end
