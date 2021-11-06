-- Compatibility layer for \meaning
-- This reverts a change rearding the \meaning of user macros:
-- LuaMetaTeX does not prefix prefixes in the meaning with a backslash.

-- Necessary especially for etoolbox's patching commands

local lmlt = luametalatex
local primitive_meaning = {
  lmlt.primitive_tokens.expandafter,
  lmlt.primitive_tokens.relax,
  lmlt.primitive_tokens.meaning,
}
lmlt.luacmd("meaning", function()
  local peeked = token.peeknext()
  token.put_next(primitive_meaning)
  token.skipnextexpanded()
  if peeked.parameters == 0 then
    tex.sprint'->'
  end
  --[[
  if peeked.frozen then
    assert(token.scan_keyword'frozen' and token.scan_code(0x400))
    tex.sprint(-2, '\\frozen ')
  end
  if peeked.protected then
    assert(token.scan_keyword'protected' and token.scan_code(0x400))
    tex.sprint(-2, '\\protected ')
  end
  ]]
end, "force", "global")
