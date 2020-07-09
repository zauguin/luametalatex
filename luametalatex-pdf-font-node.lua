local writer = require'luametalatex-nodewriter'
local utils = require'luametalatex-pdf-utils'
local to_bp, strip_floats = utils.to_bp, utils.strip_floats
local prepared = {}
return {
  buildfont = function(pdf, fontdir, usedcids)
    local designsize = fontdir.designsize
    local scale = 1/to_bp(designsize)
    local bbox = {0, 0, 0, 0}
    local matrix = {scale, 0, 0, scale, 0, 0}
    local widths = {}
    local first_cid = usedcids[1][1]-1
    local charprocs = {}
    local prev = 0
    local characters = fontdir.characters
    local prepared = assert(prepared[fontdir])
    for i=1,#usedcids do
      local used = usedcids[i]
      local glyph = characters[used[1]]
      for j=prev+1,used[1]-first_cid-1 do
        widths[j] = 0
      end
      prev = used[1]-first_cid
      widths[prev] = to_bp(glyph.width)
      charprocs[i] = string.format("/G%i %i 0 R", used[1], prepared[used[1]])
    end
    return bbox, matrix, pdf:indirect(nil, strip_floats('[' .. table.concat(widths, ' ') .. ']')), '<<' .. table.concat(charprocs) .. '>>'
  end,
  prepare = function(fontdir, usedglyphs, pdf, fontdirs, allusedglyphs)
    local state = prepared[fontdir]
    if not state then
      state = {}
      prepared[fontdir] = state
    end
    for gid in next, usedglyphs do if tonumber(gid) and not state[gid] then
        local stream, annots
        stream, state.resources, annots = writer(pdf, fontdir.characters[gid].node, fontdirs, allusedglyphs, nil, state.resources)
        state[gid] = pdf:stream(nil, '', stream)
        assert(annots == '')
    end end
  end,
}
