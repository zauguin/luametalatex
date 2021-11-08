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
    local stash = ''
    if peeked.protected then
      if token.scankeywordcs'protected' then
        token.skipnext()
        token.skipnext()
        stash = stash .. '\\protected '
      end
    end
    token.scankeyword'macro:'
    tex.sprint(-2, stash)
    tex.sprint(-2, 'macro:->')
  end
end, "force", "global")
