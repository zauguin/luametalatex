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
local function encodingtype3(pdf)
  if not pdf.encodingtype3 then
    pdf.encodingtype3 = string.format(" %i 0 R", pdf:indirect(nil, "\z
      <</Differences[\z
        0/G0/G1/G2/G3/G4/G5/G6/G7/G8/G9/G10/G11/G12/G13/G14/G15/G16\z
        /G17/G18/G19/G20/G21/G22/G23/G24/G25/G26/G27/G28/G29/G30/G31\z
        /G32/G33/G34/G35/G36/G37/G38/G39/G40/G41/G42/G43/G44/G45/G46\z
        /G47/G48/G49/G50/G51/G52/G53/G54/G55/G56/G57/G58/G59/G60/G61\z
        /G62/G63/G64/G65/G66/G67/G68/G69/G70/G71/G72/G73/G74/G75/G76\z
        /G77/G78/G79/G80/G81/G82/G83/G84/G85/G86/G87/G88/G89/G90/G91\z
        /G92/G93/G94/G95/G96/G97/G98/G99/G100/G101/G102/G103/G104/G105/G106\z
        /G107/G108/G109/G110/G111/G112/G113/G114/G115/G116/G117/G118/G119/G120/G121\z
        /G122/G123/G124/G125/G126/G127/G128/G129/G130/G131/G132/G133/G134/G135/G136\z
        /G137/G138/G139/G140/G141/G142/G143/G144/G145/G146/G147/G148/G149/G150/G151\z
        /G152/G153/G154/G155/G156/G157/G158/G159/G160/G161/G162/G163/G164/G165/G166\z
        /G167/G168/G169/G170/G171/G172/G173/G174/G175/G176/G177/G178/G179/G180/G181\z
        /G182/G183/G184/G185/G186/G187/G188/G189/G190/G191/G192/G193/G194/G195/G196\z
        /G197/G198/G199/G200/G201/G202/G203/G204/G205/G206/G207/G208/G209/G210/G211\z
        /G212/G213/G214/G215/G216/G217/G218/G219/G220/G221/G222/G223/G224/G225/G226\z
        /G227/G228/G229/G230/G231/G232/G233/G234/G235/G236/G237/G238/G239/G240/G241\z
        /G242/G243/G244/G245/G246/G247/G248/G249/G250/G251/G252/G253/G254/G255]>>"
    ))
  end
  return pdf.encodingtype3
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
  elseif false then -- FIXME: This should only be used for encodingbyzes == -3 (variable, max 3)
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
local buildfontpk = require'luametalatex-pdf-font-pk'
local function buildfont3(pdf, fontdir, usedcids)
  usedcids = usedcids or allcids(fontdir)
  table.sort(usedcids, function(a,b) return a[1]<b[1] end)
  local enc = cidmap1byte(pdf)
  local bbox, matrix, widths, charprocs = buildfontpk(pdf, fontdir, usedcids) -- TOOD
  local touni = pdf:stream(nil, "", tounicode[1](fontdir, usedcids)) -- Done late to allow for defaults set from the font file
  return string.format(
    "<</Type/Font/Subtype/Type3/FontBBox[%f %f %f %f]/FontMatrix[%f %f %f %f %f %f]/CharProcs%s/Encoding%s/FirstChar %i/LastChar %i/Widths%s/ToUnicode %i 0 R>>",
    -- "<</Type/Font/Subtype/Type3/FontBBox[%f %f %f %f]/FontMatrix[%f %f %f %f %f %f]/CharProcs%s/Encoding%s/FirstChar %i/LastChar %i/Widths[%s]/ToUnicode %i 0 R/FontDescriptor %i 0 R>>",
    bbox[1], bbox[2], bbox[3], bbox[4],
    matrix[1], matrix[2], matrix[3], matrix[4], matrix[5], matrix[6],
    charprocs,
    encodingtype3(pdf),
    usedcids[1][1],
    usedcids[#usedcids][1],
    widths,
    touni
    ) -- , descriptor) -- TODO
end
return function(pdf, fontdir, usedcids)
  if fontdir.format == "type3" then
    return buildfont3(pdf, fontdir, usedcids)
  else
    return buildfont0(pdf, fontdir, usedcids)
  end
end
