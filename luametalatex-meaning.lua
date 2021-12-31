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
-- local call_cmd = token.command_id'call'
-- local protected_call_cmd = token.command_id'protected_call'
lmlt.luacmd("meaning", function()
  local peeked = token.peeknext()
  token.put_next(primitive_meaning)
  token.skipnextexpanded()
  local cmd = peeked.cmdname -- Not .command since protected_call does not have a unique id?!?
  if cmd == 'protected_call' then
    token.scankeywordcs'protected'
    token.skipnext() -- Space
    token.skipnext() -- Another space
    tex.sprint(-2, '\\protected ')
  end
  if peeked.parameters == 0 or (cmd == 'call' and not peeked.parameters) then
    token.scankeyword'macro:'
    tex.sprint(-2, 'macro:->')
  end
end, "force", "global")
