local pk_global_resolution, pk_resolution_is_fixed
local pdfvariable = pdf.variable

local read_pk = require'luametalatex-font-pk'
local strip_floats = require'luametalatex-pdf-utils'.strip_floats
return function(pdf, fontdir, usedcids)
  if not pk_global_resolution then
    pk_global_resolution = pdfvariable.pkresolution
    if not pk_global_resolution or pk_global_resolution == 0 then
      pk_global_resolution = kpse.var_value'pk_dpi' or 72
    end
    local mode = pdfvariable.pkmode
    pk_resolution_is_fixed = pdfvariable.pkfixeddpi ~= 0
    kpse.init_prog("LUATEX", pk_global_resolution, pkmode ~= '' and pkmode or nil, nil) -- ?
  end
  local pk = read_pk(kpse.find_file(fontdir.name, 'pk', pk_resolution_is_fixed and pk_global_resolution or (pk_global_resolution*fontdir.size/fontdir.designsize+.5)//1))
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
