-- Compatibility layer for \meaning
-- This reverts a change rearding the \meaning of user macros:
-- LuaMetaTeX does not prefix prefixes in the meaning with a backslash.

-- Necessary especially for etoolbox's patching commands

local primitive_meaning = {
  token.primitive_tokens.expandafter,
  token.primitive_tokens.relax,
  token.primitive_tokens.meaning,
}
token.luacmd("meaning", function()
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
