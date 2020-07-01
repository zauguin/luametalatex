local functions = lua.getfunctionstable()
-- I am not sure why this is necessary, but otherwise LuaMetaTeX resets
-- the functions table every time the getter is called
function lua.get_functions_table() return functions end
local set_lua = token.set_lua
-- There are two approaches to manage luafunctions ids without triggering
-- issues with ltluatex assigned numbers: Originally we assigned numbers
-- starting with 1, then switched to luatexbase ASAP and synchronised both
-- numbering schemes. But there is a useful quirk in ltluatex's luafunction
-- allocator: It only uses numbers upto 65535, so we can just use bigger
-- numbers. (This might have negative repercussins on performance because it
-- probably doesn't store the function in the array part of the Lua table.
-- Let's reconsider if this ever becomes a problem.
-- local new_luafunction = luatexbase.new_luafunction
local predefined_luafunctions = status.ini_version and 65536 -- 1<<16  -- We start with 1<<16 + 1 (1<<16=65536 is reserved for luametalatex-local)
local function new_luafunction(name)
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
local lua_expandable_call_cmd = token.command_id'lua_expandable_call'
function token.luacmd(name, func, ...)
  local idx
  local tok = token.create(name)
  local cmd = tok.command
  if cmd == lua_value_cmd then
    idx = tok.mode
  elseif cmd == lua_call_cmd then
    idx = tok.mode
  elseif cmd == lua_expandable_call_cmd then
    idx = tok.mode
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
local properties = node.direct.get_properties_table()
node.direct.properties = properties
function node.direct.get_properties_table()
  return properties
end
-- setmetatable(node.direct.get_properties_table(), {
--     __index = function(t, id)
--       local new = {}
--       t[id] = new
--       return new
--     end
--   })

local new_whatsit = require'luametalatex-whatsits'.new
local whatsit_id = node.id'whatsit'
local spacer_cmd, relax_cmd = token.command_id'spacer', token.command_id'relax'
local function scan_filename()
  local name = {}
  local quoted = false
  local tok, cmd
  repeat
    tok = token.scan_token()
    cmd = tok.command
  until cmd ~= spacer_cmd and cmd ~= relax_cmd
  while (tok.command <= 12 and tok.mode <= token.biggest_char()
          or (token.put_next(tok) and false))
      and (quoted or tok.mode ~= string.byte' ') do
    if tok.mode == string.byte'"' then
      quoted = not quoted
    else
      name[#name+1] = tok.mode
    end
    tok = token.scan_token()
  end
  return utf8.char(table.unpack(name))
end

local ofiles = {}
local function do_openout(p)
  if ofiles[p.file] then
    error[[Existing file]]
  else
    local msg
    ofiles[p.file], msg = io.open(p.name, 'w')
    if not ofiles[p.file] then
      error(msg)
    end
  end
end
local open_whatsit = new_whatsit('open', do_openout)
token.luacmd("openout", function(_, immediate) -- \openout
  local file = token.scan_int()
  token.scan_keyword'='
  local name = scan_filename()
  local props = {file = file, name = name}
  if immediate == "immediate" then
    do_openout(props)
  else
    local whatsit = node.direct.new(whatsit_id, open_whatsit)
    properties[whatsit] = props
    node.direct.write(whatsit)
  end
end, "protected")
local function do_closeout(p)
  if ofiles[p.file] then
    ofiles[p.file]:close()
    ofiles[p.file] = nil
  end
end
local close_whatsit = new_whatsit('close', do_closeout)
token.luacmd("closeout", function(_, immediate) -- \closeout
  local file = token.scan_int()
  local props = {file = file}
  if immediate == "immediate" then
    do_closeout(props)
  else
    local whatsit = node.direct.new(whatsit_id, close_whatsit)
    properties[whatsit] = props
    node.direct.write(whatsit)
  end
end, "protected")
local function do_write(p)
  local content = token.to_string(p.data) .. '\n'
  local file = ofiles[p.file]
  if file then
    file:write(content)
  else
    texio.write_nl(p.file < 0 and "log" or "term and log", content)
  end
end
local write_whatsit = new_whatsit('write', do_write)
token.luacmd("write", function(_, immediate) -- \write
  local file = token.scan_int()
  local content = token.scan_tokenlist()
  local props = {file = file, data = content}
  if immediate == "immediate" then
    do_write(props)
  else
    local whatsit = node.direct.new(whatsit_id, write_whatsit)
    properties[whatsit] = props
    node.direct.write(whatsit)
  end
end, "protected")

token.luacmd("immediate", function() -- \immediate
  local next_tok = token.scan_token()
  if next_tok.command ~= lua_call_cmd then
    return token.put_next(next_tok)
  end
  local function_id = next_tok.mode
  return functions[function_id](function_id, 'immediate')
end, "protected")
-- functions[43] = function() -- \pdfvariable
--   local name = token.scan_string()
--   print('Missing \\pdf' .. name)
-- end
if status.ini_version then
  function fixupluafunctions()
    return predefined_luafunctions
  end
else
  function fixupluafunctions(i)
    predefined_luafunctions = i
  end
  local prepared_code = lua.bytecode[1]
  prepared_code()
  lua.bytecode[1] = nil
  -- function fixupluafunctions()
    -- new_luafunction = luatexbase.new_luafunction
    -- fixupluafunctions = nil
  -- end
end
require'luametalatex-baseregisters'
require'luametalatex-back-pdf'
require'luametalatex-node-luaotfload'

local integer_code do
  local value_values = token.values'value'
  for i=0,#value_values do
    if value_values[i] == "integer" then
      integer_code = i
      break
    end
  end
end
token.luacmd("Umathcodenum", function(_, scanning)
  if scanning then
    local class, family, char = tex.getmathcodes (token.scan_int())
    return integer_code, char | (class | family << 3) << 21
  else
    local char = token.scan_int()
    local mathcode = token.scan_int()
    tex.setmathcodes(char, (mathcode >> 21) & 7, mathcode >> 24, mathcode & 0x1FFFFF)
  end
end, "force", "global", "value")
