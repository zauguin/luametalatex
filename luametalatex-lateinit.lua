luametalatex = luametalatex or {}
local lmlt = luametalatex
local initex = status.ini_version

if initex then
  lua.prepared_code = {false}
end

bit32 = require'luametalatex-bit32' -- Why? And why so early?
status.init_kpse = 1 -- Why?
status.safer_option = 0 -- compat
status.shell_escape = 0 -- compat -- This is currently a lie.
-- require'module' -- ???
pdf = {
  variable = {},
}
require'luametalatex-font-resolve' -- Replace font.define. Must be loaded before callbacks
require'luametalatex-basecallbacks'
require'luametalatex-oldnames'
local callbacks = require'luametalatex-callbacks'

local function swap_table(t)
  local s = {}
  for k, v in next, t do
    s[v] = k
  end
  return s
end

local primitives = {}
do
  local token_primitives = token.getprimitives()
  local token_new = token.new
  for i=1,#token_primitives do
    local prim = token_primitives[i]
    primitives[prim[3]] = token_new(prim[2], prim[1])
  end
end
lmlt.primitive_tokens = primitives

do
  local command_id = swap_table(token.getcommandvalues())
  function token.command_id(name) return command_id[name] end
end
lmlt.value = swap_table(token.getfunctionvalues())
lmlt.flag = swap_table(tex.getflagvalues())

local functions = lua.getfunctionstable()
-- I am not sure why this is necessary, but otherwise LuaMetaTeX resets
-- the functions table every time the getter is called
function lua.get_functions_table() return functions end
local set_lua = token.set_lua

local if_offset do
  local _
  _, _, if_offset, _ = token.getrange(token.new('if_test', 0))
end

-- There are two approaches to manage luafunctions ids without triggering
-- issues with ltluatex assigned numbers: Originally we assigned numbers
-- starting with 1, then switched to luatexbase ASAP and synchronised both
-- numbering schemes. But there is a useful quirk in ltluatex's luafunction
-- allocator: It only uses numbers upto 65535, so we can just use bigger
-- numbers. (This might have negative repercussins on performance because it
-- probably doesn't store the function in the array part of the Lua table.
-- Let's reconsider if this ever becomes a problem.
-- local new_luafunction = luatexbase.new_luafunction
local predefined_luafunctions = initex and 65536 -- 1<<16  -- We start with 1<<16 + 1 (1<<16=65536 is reserved for luametalatex-local)
local new_luafunction
function new_luafunction(name)
  if predefined_luafunctions then
    predefined_luafunctions = predefined_luafunctions + 1
    return predefined_luafunctions
  else
    error[[Here only preexisting luafunctions should be set]]
  end
end
local undefined_cmd = token.command_id'undefined_cs'
local lua_call_cmd = token.command_id'lua_call'
local lua_value_cmd = token.command_id'lua_value'
local lua_protected_call_cmd = token.command_id'lua_protected_call'
local if_test_cmd = token.command_id'if_test'
function lmlt.luacmd(name, func, ...)
  local idx
  local tok = token.create(name)
  local cmd = tok.command
  if cmd == lua_value_cmd then
    idx = tok.index
  elseif cmd == lua_call_cmd then
    idx = tok.index
  elseif cmd == lua_protected_call_cmd then
    idx = tok.index
  elseif cmd == if_test_cmd and tok.index > if_offset then
    idx = tok.index - if_offset
  elseif ... == 'force' then
    idx = new_luafunction(name)
    set_lua(name, idx, select(2, ...))
  elseif cmd == undefined_cmd then
    idx = new_luafunction(name)
    set_lua(name, idx, ...)
  else
    error(tok.cmdname)
  end
  if functions[idx] then
    error[[Already defined]]
  end
  functions[idx] = func
  return idx
end

if initex then
  local build_bytecode = nil -- To be filled
  local output_directory = arg['output-directory']
  function callbacks.pre_dump()
    local user_callback = callbacks.pre_dump
    if user_callback then user_callback() end

    local prepared = lua.prepared_code
    prepared[1] = string.format("fixupluafunctions(%i)", predefined_luafunctions)
    for i=0,status.languagestate.ptr do
      local l = language.new(i)
      local str = string.format("do \z
        local l = language.new(%i)\z
        l:hyphenationmin(%i)\z
        l:prehyphenchar(%i)\z
        l:posthyphenchar(%i)\z
        l:preexhyphenchar(%i)\z
        l:postexhyphenchar(%i)",
        i,
        l:hyphenationmin(),
        l:prehyphenchar(),
        l:posthyphenchar(),
        l:preexhyphenchar(),
        l:postexhyphenchar())
      local patterns = l:patterns()
      local exceptions = l:hyphenation()
      if patterns and exceptions then
        str = string.format("%sl:patterns(%q)l:hyphenation(%q)end", str, patterns, exceptions)
      elseif patterns then
        str = string.format("%sl:patterns(%q)end", str, patterns)
      elseif exceptions then
        str = string.format("%sl:hyphenation(%q)end", str, exceptions)
      else
        str = str .. 'end'
      end
      prepared[#prepared+1] = str
    end
    for i=2,#prepared do
      if type(prepared[i]) ~= 'string' then
        prepared[i] = assert(prepared[i]())
      end
    end
    lua.bytecode[tex.count[262]+1] = build_bytecode(table.concat(prepared, '\n'))
    if output_directory then
      lfs.chdir(output_directory) -- We can't change the location TeX writes it's format to, so we change the current directory instead
    end
  end
  callbacks.__freeze('pre_dump', true)
  return function(f)
    build_bytecode = f
    return require'luametalatex-firstcode'
  end
else
  function fixupluafunctions(i)
    predefined_luafunctions = i
    fixupluafunctions = nil
  end
  return function(f)
    f()
    return require'luametalatex-firstcode'
  end
end
