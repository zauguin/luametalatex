-- Implement support for local variables.

local stack = {}

local restore_func = 65536 -- Reserved in firstcode
lua.get_functions_table()[restore_func] = function()
  local level = assert(stack[tex.currentgrouplevel], 'Out of sync')
  stack[tex.currentgrouplevel] = nil
  for t,entries in next, level do
    for k,v in next, entries do
      t[k] = v
    end
  end
end
local restore_toks = {luametalatex.primitive_tokens.atendofgroup , token.new(restore_func, token.command_id'lua_call')}
local put_next = token.put_next
local runlocal = tex.runlocal
local function put_restore_toks()
  put_next(restore_toks)
end

return function(t, k, v, global)
  local l = tex.currentgrouplevel
  if global then
    for i=1,l do
      local level = stack[i]
      if level then
        local saved = level[t]
        if saved then
          saved[k] = nil
        end
      end
    end
  elseif l > 0 then
    local level = stack[l]
    if not level then
      level = {}
      runlocal(put_restore_toks)
      stack[l] = level
    end

    local saved = level[t]
    if not saved then
      saved = {}
      level[t] = saved
    end

    saved[k] = saved[k] or t[k]
  end

  t[k] = v
end
