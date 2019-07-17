local writer = require'luametalatex-nodewriter'
local newpdf = require'luametalatex-pdf'
local pfile = newpdf.open(tex.jobname .. '.pdf')
local fontdirs = setmetatable({}, {__index=function(t, k)t[k] = pfile:getobj() return t[k] end})
local usedglyphs = {}
token.luacmd("shipout", function()
  local voff = node.new'kern'
  voff.kern = tex.voffset + tex.sp'1in'
  voff.next = token.scan_list()
  voff.next.shift = tex.hoffset + tex.sp'1in'
  local list = node.vpack(voff)
  list.height = tex.pageheight
  list.width = tex.pagewidth
  local out, resources, annots = writer(pfile, list, fontdirs, usedglyphs)
  local page, parent = pfile:newpage()
  local content = pfile:stream(nil, '', out)
  pfile:indirect(page, string.format([[<</Type/Page/Parent %i 0 R/Contents %i 0 R/MediaBox[0 %i %i %i]/Resources%s%s>>]], parent, content, -math.ceil(list.depth/65781.76), math.ceil(list.width/65781.76), math.ceil(list.height/65781.76), resources, annots))
  token.put_next(token.create'immediateassignment', token.create'global', token.create'deadcycles', token.create(0x30), token.create'relax')
  token.scan_token()
end, 'protected')
callback.register("stop_run", function()
  for fid, id in pairs(fontdirs) do
    local f = font.getfont(fid)
    local psname = f.psname or f.fullname
    local sorted = {}
    for k,v in pairs(usedglyphs[fid]) do
    sorted[#sorted+1] = v
    end
    table.sort(sorted, function(a,b) return a[1] < b[1] end)
    pfile:indirect(id, require'luametalatex-pdf-font'(pfile, f, sorted))
  end
  pfile.root = pfile:getobj()
  pfile:indirect(pfile.root, string.format([[<</Type/Catalog/Version/1.7/Pages %i 0 R>>]], pfile:writepages()))
  pfile:close()
end, "Finish PDF file")
