local scan_int = token.scan_integer
token.scan_int = scan_int -- For compatibility with LuaTeX packages
local scan_token = token.scan_token
local scan_tokenlist = token.scan_tokenlist
local scan_keyword = token.scan_keyword
local scan_csname = token.scan_csname
local set_macro = token.set_macro

local callback_find = callback.find

local constants = status.getconstants()

local lua_call_cmd = token.command_id'lua_call'
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
    tok = scan_token()
    cmd = tok.command
  until cmd ~= spacer_cmd and cmd ~= relax_cmd
  while (tok.command <= 12 and tok.command > 0 and tok.command ~= 9 and tok.index <= constants.max_character_code
          or (token.put_next(tok) and false))
      and (quoted or tok.index ~= string.byte' ') do
    if tok.index == string.byte'"' then
      quoted = not quoted
    else
      name[#name+1] = tok.index
    end
    tok = scan_token()
  end
  return utf8.char(table.unpack(name))
end

-- These are chosen to coincide with ltluatex's default catcodetables.
-- In expl-hook, we check that the values are as expected.
local initex_catcodetable = 1
local string_catcodetable = 2
if status.ini_version then
  tex.runlocal(function()tex.sprint[[\initcatcodetable 1\initcatcodetable 2]]end)
  local setcatcode = tex.setcatcode
  for i=0,127 do
    setcatcode('global', 2, i, 12)
  end
  setcatcode('global', 2, 32, 10)
end

local l = lpeg or require'lpeg'
local add_file_extension = l.Cs((1-('.' * (1-l.S'./\\')^0) * -1)^0 * (l.P(1)^1+l.Cc'.tex'))
local ofiles, ifiles = {}, {}
local function do_openout(p)
  if ofiles[p.file] then
    ofiles[p.file]:close()
  end
  local msg
  ofiles[p.file], msg = io.open(add_file_extension:match(p.name), 'w')
  if not ofiles[p.file] then
    error(msg)
  end
end
local open_whatsit = new_whatsit('open', do_openout)
token.luacmd("openout", function(_, immediate) -- \openout
  if immediate == "value" then return end
  if immediate and immediate & 0x7 ~= 0 then
    immediate = immediate & 0x8
    tex.error("Unexpected prefix", "You used \\openout with a prefix that doesn't belong there. I will ignore it for now.")
  end
  local file = scan_int()
  scan_keyword'='
  local name = scan_filename()
  local props = {file = file, name = name}
  if immediate and immediate == 8 then
    do_openout(props)
  else
    local whatsit = node.direct.new(whatsit_id, open_whatsit)
    properties[whatsit] = props
    node.direct.write(whatsit)
  end
end, "value")
token.luacmd("openin", function(_, prefix)
  if prefix == "value" then return end
  local file = scan_int()
  scan_keyword'='
  local name = scan_filename()
  if ifiles[file] then
    ifiles[file]:close()
  end
  local msg
  ifiles[file] = callback_find('open_data_file', true)(name) -- raw to pick up our wrapper which handles defaults and finding the file
end, "value")

local function do_closeout(p)
  if ofiles[p.file] then
    ofiles[p.file]:close()
    ofiles[p.file] = nil
  end
end
local close_whatsit = new_whatsit('close', do_closeout)
token.luacmd("closeout", function(_, immediate) -- \closeout
  if immediate == "value" then return end
  if immediate and immediate & 0x7 ~= 0 then
    immediate = immediate & 0x8
    tex.error("Unexpected prefix", "You used \\closeout with a prefix that doesn't belong there. I will ignore it for now.")
  end
  local file = scan_int()
  local props = {file = file}
  if immediate == 8 then
    do_closeout(props)
  else
    local whatsit = node.direct.new(whatsit_id, close_whatsit)
    properties[whatsit] = props
    node.direct.write(whatsit)
  end
end, "value")
token.luacmd("closein", function(_, prefix)
  if prefix == "value" then return end
  local file = scan_int()
  if ifiles[file] then
    ifiles[file]:close()
    ifiles[file] = nil
  end
end, "value")

local function do_write(p)
  local data = token.serialize(p.data)
  local content = data and data .. '\n' or '\n'
  local file = ofiles[p.file]
  if file then
    file:write(content)
  else
    texio.write_nl(p.file < 0 and "log" or "term and log", content)
  end
end
local write_whatsit = new_whatsit('write', do_write)
token.luacmd("write", function(_, immediate) -- \write
  if immediate == "value" then return end
  if immediate and immediate & 0x7 ~= 0 then
    immediate = immediate & 0x8
    tex.error("Unexpected prefix", "You used \\write with a prefix that doesn't belong there. I will ignore it for now.")
  end
  local file = scan_int()
  local content = scan_tokenlist()
  local props = {file = file, data = content}
  if immediate == 8 then
    do_write(props)
  else
    local whatsit = node.direct.new(whatsit_id, write_whatsit)
    properties[whatsit] = props
    node.direct.write(whatsit)
  end
end, "value")

local undefined_tok = token.new(0, token.command_id'undefined_cs')
local prefix_cmd = token.command_id'prefix'
local function prefix_to_tokens(prefix)
  if not prefix then return end
  for i=2, 0, -1 do
    if prefix & (1<<i) ~= 0 then
      token.put_next(token.new(i, prefix_cmd))
    end
  end
end
local expand_after = token.primitive_tokens.expandafter
local input_tok = token.primitive_tokens.input
local endlocalcontrol = token.primitive_tokens.endlocalcontrol
local afterassignment = token.primitive_tokens.afterassignment
local lbrace = token.new(0, 1)
local rbrace = token.new(0, 2)
token.luacmd("read", function(_, prefix)
  if immediate == "value" then return end
  local id = scan_int()
  if not scan_keyword'to' then
    tex.error("Missing `to' inserted", "You should have said `\\read<number> to \\cs'.\nI'm going to look for the \\cs now.")
  end
  local macro = scan_csname(true)
  local file = ifiles[id]
  local tokens = {}
  local balance = 0
  repeat
    local line
    if file then
      line = file:reader()
      if not line then
        file:close()
        ifiles[id] = nil
      end
    else
      line = io.stdin:read()
    end
    local endlocal
    tex.runlocal(function()
      endlocal = token.scan_next()
      tex.sprint(endlocal)
      tex.print(line and line ~= "" and line or " ")
      tex.print(endlocal)
    end)
    while true do
      local tok = token.scan_next()
      if tok == endlocal then break end
      if tok.command == 1 then
        balance = balance + 1
      elseif tok.command == 2 then
        balance = balance - 1
      end
      tokens[#tokens+1] = tok
    end
  until balance == 0
  tex.runlocal(function()
    tokens[#tokens+1] = rbrace
    token.put_next(tokens)
    token.put_next(token.primitive_tokens.def, token.create(macro), lbrace)
    prefix_to_tokens(prefix)
  end)
end, "value")

token.luacmd("readline", function(_, prefix)
  if immediate == "value" then return end
  local id = scan_int()
  if not scan_keyword'to' then
    tex.error("Missing `to' inserted", "You should have said `\\read<number> to \\cs'.\nI'm going to look for the \\cs now.")
  end
  local macro = scan_csname(true)
  local file = ifiles[id]
  local line
  if file then
    line = file:reader()
    if not line then
      file:close()
      ifiles[id] = nil
    end
  else
    error[[FIXME: Ask the user for input]]
  end
  line =  line and line:match"^(.*[^ ])[ ]*$"
  local endlinechar = tex.endlinechar
  if endlinechar >= 0 and endlinechar < 0x80 then
    line = (line or '') .. string.char(endlinechar)
  end
  set_macro(string_catcodetable, macro, line or '', prefix)
end, "value")

local integer_code, boolean_code do
  local value_values = token.getfunctionvalues()
  for i=0,#value_values do
    if value_values[i] == "integer" then
      integer_code = i
    elseif value_values[i] == "boolean" then
      boolean_code = i
    end
  end
end

token.luacmd("ifeof", function(_)
  local id = scan_int()
  return boolean_code, not ifiles[id]
end, "condition")

local late_lua_whatsit = new_whatsit('late_lua', function(p, pfile, n, x, y)
  local code = p.data
  if not code then
    code = token.serialize(p.token)
  end
  if type(code) == 'string' then
    code = assert(load(code, nil, 't'))
  elseif not code then
    error[[Missing code in latelua]]
  end
  return pdf._latelua(pfile, x, y, code)
end)
token.luacmd("latelua", function() -- \latelua
  local content = scan_tokenlist()
  local props = {token = content}
  local whatsit = node.direct.new(whatsit_id, late_lua_whatsit)
  properties[whatsit] = props
  node.direct.write(whatsit)
end, "protected")

local functions = lua.get_functions_table()

require'luametalatex-meaning'
require'luametalatex-baseregisters'
require'luametalatex-back-pdf'
require'luametalatex-node-luaotfload'

token.luacmd("Umathcodenum", function(_, scanning)
  if scanning then
    local class, family, char = tex.getmathcodes (scan_int())
    return integer_code, char | (class | family << 3) << 21
  else
    local char = scan_int()
    local mathcode = scan_int()
    tex.setmathcodes(char, (mathcode >> 21) & 7, mathcode >> 24, mathcode & 0x1FFFFF)
  end
end, "force", "global", "value")

-- This is effectivly the last line before we hand over to normal TeX.
require'luametalatex-callbacks'.__freeze = nil
