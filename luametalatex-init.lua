do
  local ourpath = arg[0]:match('^%-%-lua=(.*)luametalatex%-init%.lua$')
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
local read_tfm = require'luametalatex-font-tfm'
local read_vf = require'luametalatex-font-vf'
font.read_tfm = read_tfm
font.read_vf = read_vf
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
callback.register('define_font', function(name, size)
  local f = read_tfm(name, size)
  local id = font.define(f)
  if status.ini_version then
    lua.prepared_code[#lua.prepared_code+1] = string.format("assert(%i == font.define(font.read_tfm(%q, %i)))", id, name, size)
  end
  return id
end)
-- callback.register('terminal_input', function(prompt)
  -- print('Input expected: ', prompt)
  -- return 'AAA'
-- end)
callback.register('find_log_file', function(name) return name end)
-- callback.register('find_read_file', function(i, name) return kpse.find_file(name, 'tex', true) end)
callback.register('find_data_file', function(name, ...) return kpse.find_file(name, 'tex', true) end)
callback.register('read_data_file', function(name) error[[TODO]]return kpse.find_file(name, 'tex', true) end)
-- local file_meta = {\
callback.register('open_data_file', function(name)
  local f = io.open(name)
  return setmetatable({
    reader = function() return f:read() end,
    close = function()error[[1]] return f:close() end,
  }, {
    __gc = function()f:close()end,
  })
end)
callback.register('find_format_file', function(name) return kpse.find_file(name, 'fmt', true) end)
callback.register('show_warning_message', function()
  texio.write_nl('WARNING Tag: ' .. status.lastwarningtag)
  texio.write_nl(status.lastwarningstring)
end)
callback.register('show_error_message', function()
  if status.lasterrorcontext then
    texio.write_nl('ERROR Context: ' .. status.lasterrorcontext)
  end
  texio.write_nl(status.lasterrorstring)
end)
callback.register('pre_dump', function()
  lua.bytecode[1] = assert(load(table.concat(lua.prepared_code, ' ')))
end)
function texconfig.init()
  if not status.ini_version then
    lua.bytecode[2]()
    lua.bytecode[2] = nil
  end
end
if status.ini_version then
  lua.prepared_code = {}
  local code = package.searchers[2]('luametalatex-firstcode')
  if type(code) == "string" then error(string.format("Initialization code not found %s", code)) end
  lua.bytecode[2] = code
end
