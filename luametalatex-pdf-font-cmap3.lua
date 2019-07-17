local template = [[%%!PS-Adobe-3.0 Resource-CMap
%%%%DocumentNeededResources: ProcSet (CIDInit)
%%%%IncludeResource: ProcSet (CIDInit)
%%%%BeginResource: CMap (TeX-%s-0)
%%%%Title: (TeX-%s-0 TeX %s 0)
%%%%Version: 1.000
%%%%EndComments
/CIDInit /ProcSet findresource begin
12 dict begin
begincmap
/CIDSystemInfo
<< /Registry (TeX)
/Ordering (%s)
/Supplement 0
>> def
/CMapName /TeX-%s-0 def
/CMapType 2 def
3 begincodespacerange
<00> <7F>
<8000> <FEFF>
<FF0000> <FF807F>
endcodespacerange
]]
local separator = [[endbfrange
%i beginbfchar
]]
local betweenchars = [[endbfchar
%i beginbfchar
]]
local trailer = [[endbfchar
endcmap
CMapName currentdict /CMap defineresource pop
end
end
%%EndResource
%%EOF
]]
return function(f, usedcids)
  local name = 'XXXstuffXXX-' .. f.name
  local text = template:format(name, name, name, name, name)
  text = text .. "0 beginbfrange\n"
  local count, chars = 0, ""
  local next_head = separator
  for _, cid in ipairs(usedcids) do
    if cid[3] then
      count = count + 1
      if cid[1] < 0x80 then
        chars = chars .. (type(cid[3]) == 'string' and "<%02X> <%s>\n" or "<%02X> <%04X>\n"):format(cid[1], cid[3])
      elseif cid[1] < 0x7F80 then
        chars = chars .. (type(cid[3]) == 'string' and "<%04X> <%s>\n" or "<%04X> <%04X>\n"):format(cid[1]+0x7F80, cid[3])
      else
        chars = chars .. (type(cid[3]) == 'string' and "<%06X> <%s>\n" or "<%06X> <%04X>\n"):format(cid[1]-0x7F80, cid[3])
      end
      if count == 100 then
        text = text .. next_head:format(100) .. chars
        next_head = betweenchars
      end
    end
  end
  text = text .. next_head:format(count) .. chars .. trailer
  return text
end
