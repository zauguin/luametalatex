do
  local ourpath = arg[0]:match('^%-%-lua=(.*[/\\])[^/\\]*%.lua$')
  kpse = assert(package.loadlib(ourpath .. 'kpse.so', 'luaopen_kpse'))()
end
do
  local arg0, progname
  for _, a in ipairs(arg) do
    if a:sub(1,11) == "--progname=" then
      progname = a:sub(12)
    elseif a:sub(1,7) == "--arg0=" then
      arg0 = a:sub(8)
    end
  end
  kpse.set_program_name(arg0, progname)
end
package.searchers[2] = function(modname)
  local filename = kpse.find_file(modname, "lua", true)
  if not filename then
    return string.format("\n\tno file located through kpse for %s", modname)
  end
  local mod, msg = loadfile(filename)
  if msg then
    error(string.format("error loading module '%s' from file '%s':\n\t%s", modname, filename, msg))
  end
  return mod, filename
end
-- kpse.set_maketex("kpse_fmt_format", true)
bit32 = require'luametalatex-bit32'
kpse.init_prog("LUATEX", 400, "nexthi", nil)
status.init_kpse = 1
require'luametalatex-init-config'
status.safer_option = 0
status.shell_escape = 0
local read_tfm = require'luametalatex-font-tfm'
local read_vf = require'luametalatex-font-vf'
font.read_tfm = read_tfm
font.read_vf = read_vf
local callback_register = callback.register
require'module'
font.fonts = {}
function font.getfont(id)
  return font.fonts[id]
end
pdf = {
  getfontname = function(id) -- No font sharing
    return id
  end,
}
local olddefinefont = font.define
function font.define(f)
  local i = olddefinefont(f)
  font.fonts[i] = f
  return i
end
callback_register('define_font', function(name, size)
  local f = read_tfm(name, size)
  local id = font.define(f)
  if status.ini_version then
    lua.prepared_code[#lua.prepared_code+1] = string.format("assert(%i == font.define(font.read_tfm(%q, %i)))", id, name, size)
  end
  return id
end)
callback_register('find_log_file', function(name) return name end)
do
  local function normal_find_data_file(name)
    return kpse.find_file(name, 'tex', true)
  end
  if status.ini_version then
    callback_register('find_data_file', function(name)
      if name == 'ltexpl.ltx' then
        callback_register('find_data_file', normal_find_data_file)
        name = 'luametalatex-ltexpl-hook'
      end
      return normal_find_data_file(name)
    end)
  else
    callback_register('find_data_file', normal_find_data_file)
  end
end
callback_register('read_data_file', function(name) error[[TODO]]return kpse.find_file(name, 'tex', true) end)
-- local file_meta = {\
callback_register('open_data_file', function(name)
  local f = io.open(name)
  return setmetatable({
    reader = function() return f:read() end,
    close = function()error[[1]] return f:close() end,
  }, {
    __gc = function()f:close()end,
  })
end)
callback_register('find_format_file', function(name) return kpse.find_file(name, 'fmt', true) end)
callback_register('handle_error_hook', function()
  repeat
    texio.write_nl'? '
    local line = io.read()
    if not line then
      tex.fatalerror'End of line encountered on terminal'
    end
    if line == "" then return 3 end
    local first = line:sub(1,1):upper()
    if first == 'H' then
      texio.write(tex.gethelptext())
    elseif first == 'I' then
      line = line:sub(2)
      tex.runtoks(function()
        tex.sprint(token.scan_token(), line)
      end)
      return 3
    elseif first == 'Q' then texio.write'OK, entering \\batchmode...\n' return 0
    elseif first == 'R' then texio.write'OK, entering \\nonstopmode...\n' return 1
    elseif first == 'S' then texio.write'OK, entering \\scrollmode...\n' return 2
    elseif first == 'X' then return -1
    else
      texio.write'Type <return> to proceed, S to scroll future error messages,\
\z      R to run without stopping, Q to run quietly,\
\z      I to insert something,\
\z      H for help, X to quit.'
    end
  until false
  return 3
end)
callback_register('pre_dump', function()
  lua.prepared_code[1] = string.format("fixupluafunctions(%i)", fixupluafunctions())
  lua.bytecode[1] = assert(load(table.concat(lua.prepared_code, ' ')))
end)
function texconfig.init()
  lua.bytecode[2]()
  if not status.ini_version then
    lua.bytecode[2] = nil
  end
end
if status.ini_version then
  lua.prepared_code = {false}
  local code = package.searchers[2]('luametalatex-firstcode')
  if type(code) == "string" then error(string.format("Initialization code not found %s", code)) end
  lua.bytecode[2] = code
end
