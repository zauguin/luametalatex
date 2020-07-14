-- Some helpers:
-- A kpse wrapper
local serialize_cff = require'luametalatex-font-cff'
local serializet2 = require'luametalatex-font-t2'
local parseT1 = require'luametalatex-font-t1'
local t1tot2 = require'luametalatex-font-t1tot2'
return function(filename, reencode)
  local parsed_t1 = parseT1(filename)
  return function(f, usedcids)
    f.bbox = parsed_t1.FontBBox
    local fonttable = {
      version = parsed_t1.FontInfo.version,
      Notice = parsed_t1.FontInfo.Notice,
      FullName = parsed_t1.FontInfo.FullName,
      FamilyName = parsed_t1.FontInfo.FamilyName,
      Weight = parsed_t1.FontInfo.Weight,
      ItalicAngle = parsed_t1.FontInfo.ItalicAngle,
      isFixedPitch = parsed_t1.FontInfo.isFixedPitch,
      UnderlinePosition = parsed_t1.FontInfo.UnderlinePosition,
      UnderlineThickness = parsed_t1.FontInfo.UnderlineThickness,
      FontName = parsed_t1.FontName,
      FontMatrix = parsed_t1.FontMatrix,
      FontBBox = parsed_t1.FontBBox,
      -- UniqueID = parsed_t1.UniqueID,
      -- ? = parsed_t1.Metrics,
      ---- PRIVATE ----
      BlueValues = parsed_t1.Private.BlueValues,
      OtherBlues = parsed_t1.Private.OtherBlues,
      -- FamilyBlues?
      BlueScale = parsed_t1.Private.BlueScale,
      BlueShift = parsed_t1.Private.BlueShift,
      BlueFuzz = parsed_t1.Private.BlueFuzz,
      StdHW = (parsed_t1.Private.StdHW or {})[1], -- Why are these arrays in T1?
      StdVW = (parsed_t1.Private.StdVW or {})[1], -- They are also undocumented in the spec...
      StemSnapH = parsed_t1.Private.StemSnapH,
      StemSnapV = parsed_t1.Private.StemSnapV,
      ForceBold = parsed_t1.Private.ForceBold,
      -- LanguageGroup = parsed_t1.Private.LanguageGroup,
    }
    if not reencode and parsed_t1.Encoding == "StandardEncoding" then
      reencode = kpse.find_file("8a.enc", "enc files")
    end
    if reencode then
      parsed_t1.Encoding = require'luametalatex-font-enc'(reencode)
    end
    -- parsed_t1.Encoding[0] = ".notdef"
    local glyphs = {}
    fonttable.glyphs = glyphs
    for i=1,#usedcids do
      local name = parsed_t1.Encoding[usedcids[i][1]] -- TODO: Reencoding and StandardEncoding
      glyphs[#glyphs + 1] = {index = usedcids[i][1], name = name, cs = serializet2(t1tot2(parsed_t1.CharStrings[name], parsed_t1.Private.Subrs))} -- TODO: Missing glyphs
    end
    return serialize_cff(fonttable)
  end
end
