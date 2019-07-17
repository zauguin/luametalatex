local mapping = require'luametalatex-pdf-font-map'
mapping.mapfile'/usr/local/texlive/2019/texmf-var/fonts/map/pdftex/updmap/pdftex.map'
local tounicode = {
  [-3] = require'luametalatex-pdf-font-cmap3',
         require'luametalatex-pdf-font-cmap1',
         require'luametalatex-pdf-font-cmap2',
}
local function allcids(fontdir)
  local cids = {}
  local scale = 1000/fontdir.size
  for i,v in pairs(fontdir.characters) do
    v.used = true
    cids[#cids+1] = {v.index or i, math.floor(v.width*scale+.5), v.tounicode}
  end
  return cids
end
local function buildW(f, usedcids)
  local used = #usedcids
  if used == 0 then return "" end
  local result = {}
  local index = 1
  while index <= used do
    local width = usedcids[index][2]
    local last = index
    while last ~= used and usedcids[last+1][2] == width do
      last = last + 1
    end
    if index == last then
      local span = {width}
      width = (usedcids[last+1] or {})[2]
      while (last + 2 <= used
            and usedcids[last+2][2] ~= width
            or last + 1 == used)
          and usedcids[last+1][1]-usedcids[last][1] <= 2 do
        for i=usedcids[last][1]+1,usedcids[last+1][1]-1 do
          span[#span+1] = 0
        end
        last = last + 1
        span[#span+1] = width
        width = (usedcids[last + 1] or {})[2]
      end
      result[#result+1] = string.format("%i[%s]", usedcids[index][1], table.concat(span, ' '))
    else
      result[#result+1] = string.format("%i %i %i ", usedcids[index][1], usedcids[last][1], width)
    end
    index = last + 1
  end
  return table.concat(result)
end
local function fontdescriptor(pdf, basefont, fontdir, stream, kind)
  local scale = 1000/fontdir.size
  return string.format(
    "<</Type/FontDescriptor/FontName/%s/Flags %i/FontBBox[%i %i %i %i]/ItalicAngle %i/Ascent %i/Descent %i/CapHeight %i/StemV %i/FontFile%s %i 0 R>>",
    basefont,
    4,-- FIXME: Flags ??? (4 means "symbolic")
    fontdir.bbox[1], fontdir.bbox[2], fontdir.bbox[3], fontdir.bbox[4], -- FIXME: How to determine BBox? 
    math.floor(math.atan(fontdir.parameters.slant or fontdir.parameters[1] or 0, 0x10000)+.5),
    fontdir.bbox[4], fontdir.bbox[2],
    fontdir.parameters[8] and math.floor(fontdir.parameters[8]*scale+0.5) or fontdir.bbox[4],
    fontdir.StemV or 100, -- FIXME: How to determine StemV?
    kind, stream)
end
local function cidmap1byte(pdf)
  if not pdf.cidmap1byte then
    pdf.cidmap1byte = string.format(" %i 0 R", pdf:stream(nil, [[/Type/CMap/CMapName/Identity-8-H/CIDSystemInfo<</Registry(Adobe)/Ordering(Identity)/Supplement 0>>]],
    [[%!PS-Adobe-3.0 Resource-CMap
%%DocumentNeededResources : ProcSet (CIDInit)
%%IncludeResource : ProcSet (CIDInit)
%%BeginResource : CMap (Identity-8-H)
%%Title: (Custom 8bit Identity CMap)
%%Version: 1.000
%%EndComments
/CIDInit /ProcSet findresource begin
12 dict begin
begincmap
/CIDSystemInfo
3 dict dup begin
/Registry (Adobe) def
/Ordering (Identity) def
/Supplement 0 def
end def
/CMapName /Identity-8-H def
/CMapVersion 1.000 def
/CMapType 1 def
/WMode 0 def
1 begincodespacerange
<00> <FF>
endcodespacerange
1 begincidrange
<00> <FF> 0
endcidrange
endcmap
CMapName currentdict /CMap defineresource pop
end
end
%%EndResource
%%EOF]]))
  end
  return pdf.cidmap1byte
end
local function cidmap3byte(pdf)
  if not pdf.cidmap3byte then
    pdf.cidmap3byte = string.format(" %i 0 R", pdf:stream(nil, [[/Type/CMap/CMapName/Identity-Var-H/CIDSystemInfo<</Registry(Adobe)/Ordering(Identity)/Supplement 0>>]],
    [[%!PS-Adobe-3.0 Resource-CMap
%%DocumentNeededResources : ProcSet (CIDInit)
%%IncludeResource : ProcSet (CIDInit)
%%BeginResource : CMap (Identity-Var-H)
%%Title: (Custom 8-24bit variable size Identity CMap)
%%Version: 1.000
%%EndComments
/CIDInit /ProcSet findresource begin
12 dict begin
begincmap
/CIDSystemInfo
3 dict dup begin
/Registry (Adobe) def
/Ordering (Identity) def
/Supplement 0 def
end def
/CMapName /Identity-Var-H def
/CMapVersion 1.000 def
/CMapType 1 def
/WMode 0 def
3 begincodespacerange
<FF0000> <FF807F>
<00> <7F>
<8000> <FEFF>
endcodespacerange
3 begincidrange
<00> <7F> 0
<8000> <FEFF> 128
<FF0000> <FF807F> 32640
endcidrange
endcmap
CMapName currentdict /CMap defineresource pop
end
end
%%EndResource
%%EOF]]))
  end
  return pdf.cidmap3byte
end
local capitals = {string.byte("ABCDEFGHIJKLMNOPQRSTUVWXYZ", 1, -1)}
local function gen_subsettagchar(i, left, ...)
  if left == 0 then return ... end
  return gen_subsettagchar(i//#capitals, left-1, capitals[i%#capitals+1], ...)
end
local function gen_subsettag(ident)
  local i = string.unpack("j", sha2.digest256(ident))
  return string.char(gen_subsettagchar(i, 7, 43))
end
local function buildfont0cff(pdf, fontdir, usedcids)
  local basefont = fontdir.psname or fontdir.fullname or fontdir.name -- FIXME: Subset-tag(?), Name-Escaping(?), fallback
  if fontdir.cff then
    cff = fontdir:cff(usedcids)
  else
    if fontdir.filename then
      if fontdir.format == "type1" then
        cff = require'luametalatex-pdf-font-t1'(fontdir.filename, fontdir.encoding)(fontdir, usedcids)
      elseif fontdir.format == "opentype" then
        cff = require'luametalatex-pdf-font-cff'(fontdir.filename, fontdir.encodingbytes == 1 and (fontdir.encoding or true))(fontdir, usedcids)
      else
        error[[Unsupported format]]
      end
    else
      return string.format("<</Type/Font/Subtype/Type1/BaseFont/%s/FontDescriptor %i 0 R/FirstChar %i/LastChar %i>>", basefont, -42, usedcids[1][1], usedcids[#usedcids][1])
    end
  end
  local widths = buildW(fontdir, usedcids) -- Do this after generating the CFF to allow for extracting the widths from the font file
  basefont = gen_subsettag(widths)..basefont
  local cidfont = pdf:indirect(nil, string.format(
      "<</Type/Font/Subtype/CIDFontType0/BaseFont/%s/CIDSystemInfo<</Registry(Adobe)/Ordering(Identity)/Supplement 0>>/FontDescriptor %i 0 R/W[%s]>>",
      basefont,
      pdf:indirect(nil, fontdescriptor(pdf, basefont, fontdir, pdf:stream(nil, '/Subtype/CIDFontType0C', cff), 3)),
      widths
    ))
  return basefont, cidfont
end
local function buildfont0ttf(pdf, fontdir, usedcids)
  local basefont = fontdir.psname or fontdir.fullname or fontdir.name -- FIXME: Subset-tag(?), Name-Escaping(?), fallback
  local ttf
  if fontdir.ttf then
    ttf = fontdir:ttf(usedcids) -- WARNING: If you implement this: You always have to add a .notdef glyph at index 0. This one is *not* included in usedcids
  else
    ttf = require'luametalatex-pdf-font-ttf'(fontdir.filename, 1, fontdir.encoding)(fontdir, usedcids)
  end
  local lastcid = -1
  local cidtogid = {}
  for i=1,#usedcids do
    cidtogid[2*i-1] = string.rep("\0\0", usedcids[i][1]-lastcid-1)
    cidtogid[2*i] = string.pack(">I2", i)
    lastcid = usedcids[i][1]
  end
  cidtogid = pdf:stream(nil, "", table.concat(cidtogid))
  local widths = buildW(fontdir, usedcids)
  basefont = gen_subsettag(widths)..basefont
  local cidfont = pdf:indirect(nil, string.format(
      "<</Type/Font/Subtype/CIDFontType2/BaseFont/%s/CIDSystemInfo<</Registry(Adobe)/Ordering(Identity)/Supplement 0>>/FontDescriptor %i 0 R/W[%s]/CIDToGIDMap %i 0 R>>",
      basefont,
      pdf:indirect(nil, fontdescriptor(pdf, basefont, fontdir, pdf:stream(nil, string.format('/Length1 %i', #ttf), ttf), 2)),
      widths,
      cidtogid
    ))
  return basefont, cidfont
end
local function buildfont0(pdf, fontdir, usedcids)
  usedcids = usedcids or allcids(fontdir)
  table.sort(usedcids, function(a,b) return a[1]<b[1] end)
  local enc
  if fontdir.encodingbytes == 1 then
    enc = cidmap1byte(pdf)
  elseif true then -- FIXME: This should only be used for encodingbyzes == -3 (variable, max 3)
    fontdir.encodingbytes = -3 -- FIXME
    enc = cidmap3byte(pdf)
  else
    enc = "/Identity-H"
  end
  local basefont, cidfont = (fontdir.format == "truetype" and buildfont0ttf or buildfont0cff)(pdf, fontdir, usedcids)
  local touni = pdf:stream(nil, "", tounicode[fontdir.encodingbytes](fontdir, usedcids)) -- Done late to allow for defaults set from the font file
  return string.format(
    "<</Type/Font/Subtype/Type0/BaseFont/%s/Encoding%s/ToUnicode %i 0 R/DescendantFonts[%i 0 R]>>",
    basefont,
    enc,
    touni,
    cidfont)
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
return function(pdf, fontdir, usedcids)
  if fontdir.encodingbytes == 0 then fontdir.encodingbytes = nil end
  if fontdir.format == "unknown" or not fontdir.format or fontdir.encodingbytes == 1 then -- TODO: How to check this?
    fontdir.encodingbytes = fontdir.encodingbytes or 1
    local mapentry = mapping.fontmap[fontdir.name]
    if mapentry then
      local format = mapentry[3] and mapentry[3]:sub(-4, -4) == '.' and fontextensions[mapentry[3]:sub(-3, -1)]
      if format then
        fontdir.format = format[1]
        fontdir.filename = kpse.find_file(mapentry[3], format[2])
        if mapentry[4] then
          fontdir.encoding = kpse.find_file(mapentry[4], 'enc files')
        end
        goto format_set
      else
        for _, format in ipairs(fontformats) do
          local font = kpse.find_file(mapentry[3],format[2])
          if font then
            fontdir.format = "type1"
            fontdir.filename = font
            if mapentry[4] then
              fontdir.encoding = kpse.find_file(mapentry[4], 'enc files')
            end
            goto format_set
          end
        end
      end
    end
    fontdir.format = "type3"
    ::format_set::
  else
    fontdir.encodingbytes = fontdir.encodingbytes or 2
  end
  if fontdir.format == "type3" then
    error[[Currently unsupported]] -- TODO
  else
    return buildfont0(pdf, fontdir, usedcids)
  end
end
