local functions = lua.getfunctionstable()
-- I am not sure why this is necessary, but otherwise LuaMetaTeX resets
-- the functions table every time the getter is called
function lua.get_functions_table() return functions end
local set_lua = token.set_lua
-- local new_luafunction = luatexbase.new_luafunction
local predefined_luafunctions = 0
local function new_luafunction(name)
  predefined_luafunctions = predefined_luafunctions + 1
  return predefined_luafunctions
end
function token.luacmd(name, func, ...)
  local idx = new_luafunction(name)
  set_lua(name, idx, ...)
  functions[idx] = func
  return idx
end
local properties = node.get_properties_table()
-- setmetatable(node.direct.get_properties_table(), {
--     __index = function(t, id)
--       local new = {}
--       t[id] = new
--       return new
--     end
--   })

local whatsit_id = node.id'whatsit'
local whatsits = {
  [0] = "open",
        "write",
        "close",
        "special",
        nil,
        nil,
        "save_pos",
        "late_lua",
        "user_defined",
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        "pdf_literal",
        "pdf_refobj",
        "pdf_annot",
        "pdf_start_link",
        "pdf_end_link",
        "pdf_dest",
        "pdf_action",
        "pdf_thread",
        "pdf_start_thread",
        "pdf_end_thread",
        "pdf_thread_data",
        "pdf_link_data",
        "pdf_colorstack",
        "pdf_setmatrix",
        "pdf_save",
        "pdf_restore",
}
whatsits[whatsits[0]] = 0
for i = 0,#whatsits do
  local v = whatsits[i]
  if v then
    whatsits[v] = i
  end
end
function node.whatsits() return whatsits end
function node.subtype(s) return type(s) == "string" and whatsits[s] or nil end
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
token.luacmd("openout", function(_, immediate) -- \openout
  local file = token.scan_int()
  token.scan_keyword'='
  local name = scan_filename()
  local props = {file = file, name = name, handle = do_openout}
  if immediate == "immediate" then
    do_openout(props)
  else
    local whatsit = node.new(whatsit_id, whatsits.open)
    properties[whatsit] = props
    node.write(whatsit)
  end
end, "protected")
local function do_closeout(p)
  if ofiles[p.file] then
    ofiles[p.file]:close()
    ofiles[p.file] = nil
  end
end
token.luacmd("closeout", function(_, immediate) -- \closeout
  local file = token.scan_int()
  local props = {file = file, handle = do_closeout}
  if immediate == "immediate" then
    do_closeout(props)
  else
    local whatsit = node.new(whatsit_id, whatsits.close)
    properties[whatsit] = props
    node.write(whatsit)
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
token.luacmd("write", function(_, immediate) -- \write
  local file = token.scan_int()
  local content = token.scan_tokenlist()
  local props = {file = file, data = content, handle = do_write}
  if immediate == "immediate" then
    do_write(props)
  else
    local whatsit = node.new(whatsit_id, whatsits.write)
    properties[whatsit] = props
    node.write(whatsit)
  end
end, "protected")
local lua_call_cmd = token.command_id'lua_call'
token.luacmd("immediate", function() -- \immediate
  local next_tok = token.scan_token()
  if next_tok.command ~= lua_call_cmd then
    return token.put_next(next_tok)
  end
  local function_id = next_tok.index
  functions[function_id](function_id, 'immediate')
end, "protected")
-- functions[43] = function() -- \pdfvariable
--   local name = token.scan_string()
--   print('Missing \\pdf' .. name)
-- end
local prepared_code = lua.bytecode[1]
if prepared_code then
  prepared_code()
  prepared_code, lua.bytecode[1] = nil, nil
  function fixupluafunctions()
    new_luafunction = luatexbase.new_luafunction
    fixupluafunctions = nil
  end
else
  function fixupluafunctions()
    tex.setcount("global", "e@alloc@luafunction@count", predefined_luafunctions)
  end
end
require'luametalatex-back-pdf'
