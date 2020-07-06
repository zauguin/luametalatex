require'luametalatex-font-resolve' -- Ensure that font.fonts exists

local keymap = {}

-- There are multiple criteria for sharing backend fonts:
--  * Obviously encodingbytes have to be the same.
--  * The filename better is the same too.
--  * Similarly the index must be the same.
--  * Specifically in the PK font case *without* fixed DPI,
--    The size must be the same too.
--  * For fontmap based fonts, compare the name field instead,
--    of the normal filename, especially to capture encoding differences.
--    An alternative might be to only take the encoding into account.
--    This is also required for other fonts which might not be backed by
--    traditional files
local function build_sharekey(fontdir)
  local encodingbytes = assert(fontdir.encodingbytes)
  local key = string.format("%i:%s:", fontdir.encodingbytes, fontdir.format)
  if encodingbytes == 1 then
    if fontdir.format == "type3" then
      return string.format("%s%i:%s", key, fontdir.size, fontdir.name)
    end
    key = string.format("%s%s:", key, fontdir.encoding or '')
  end
  key = string.format("%s%i:%s", key, fontdir.subfont or 1, fontdir.filename)
  return key
end

local fonts = font.fonts
local fontmap = setmetatable({}, {
  __index = function(t, fid)
    local key = build_sharekey(assert(fonts[fid]))
    local mapped = keymap[key]
    local share_parent = mapped and t[mapped] or fid
    t[fid] = share_parent
    return share_parent
  end,
})

function pdf.getfontname(fid)
  return fontmap[fid]
end

return fontmap
