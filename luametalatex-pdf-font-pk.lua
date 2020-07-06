local read_pk = require'luametalatex-font-pk'
local strip_floats = require'luametalatex-pdf-utils'.strip_floats
return function(pdf, fontdir, usedcids)
  local pk = read_pk(fontdir.name)
  local designsize = pk.designsize/1044654.326 -- 1044654.326=2^20*72/72.27 -- designsize in bp
  local hscale = 65536/pk.hppp / designsize -- 65291.158=2^16*72/72.27
  local vscale = 65536/pk.vppp / designsize -- 65291.158=2^16*72/72.27
  local bbox = {0, 0, 0, 0}
  local matrix = {hscale, 0, 0, vscale, 0, 0}
  local widths = {}
  local first_cid = usedcids[1][1]-1
  local charprocs = {}
  local prev = 0
  for i=1,#usedcids do
    local used = usedcids[i]
    local glyph = pk[used[1]]
    for j=prev+1,used[1]-first_cid-1 do
      widths[j] = 0
    end
    prev = used[1]-first_cid
    widths[prev] = glyph.dx/2^16
    local lower, left, upper, right = glyph.voff - glyph.h, -glyph.hoff, glyph.voff, -glyph.hoff + glyph.w
    bbox[1], bbox[2], bbox[3], bbox[4] = math.min(bbox[1], left), math.min(bbox[2], lower), math.max(bbox[3], right), math.max(bbox[4], upper)
    charprocs[i] = string.format("/G%i %i 0 R", used[1], pdf:stream(nil, "", string.format("%i %i %i %i %i %i d1 %i 0 0 %i %i %i cm BI /W %i/H %i/IM true/BPC 1/D[1 0] ID %s EI",
        glyph.dx/2^16, glyph.dy, left, lower, right, upper, glyph.w, glyph.h, left, lower, glyph.w, glyph.h, glyph.data
    )))
  end
  return bbox, matrix, pdf:indirect(nil, strip_floats('[' .. table.concat(widths, ' ') .. ']')), '<<' .. table.concat(charprocs) .. '>>'
end
