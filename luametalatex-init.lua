do
  local ourpath = lua.startupfile:match('(.*[/\\])[^/\\]*%.lua$')
  kpse = assert(package.loadlib(ourpath .. 'kpse.so', 'luaopen_kpse'))()
end
local interaction
do
  local arg0, progname
  for _, a in ipairs(arg) do
    if a:sub(1,11) == "--progname=" then
      progname = a:sub(12)
    elseif a:sub(1,7) == "--arg0=" then
      arg0 = a:sub(8)
    elseif a:match'^%-%-?interaction=' then
      local interaction_name = a:sub(a:find'='+1)
      interaction = ({
        batchmode=0,
        nonstopmode=1,
        scrollmode=2,
        errorstopmode=3,
      })[interaction_name]
      if not interaction then
        texio.write('term', string.format('Unknown interaction mode %q ignored.\n', interaction_name))
      end
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
kpse.set_maketex("fmt", true, "compile")
-- kpse.init_prog("LUATEX", 400, "nexthi", nil)
require'luametalatex-init-config'
local callback_register = callback.register
local build_bytecode
if status.ini_version then
  local build_bytecode_mod = require'luametalatex-build-bytecode'
  local preloaded_modules = {}
  local old_searcher = package.searchers[2]
  package.searchers[2] = function(name)
    local mod, file = old_searcher(name)
    if not file then return mod end -- Only works because we always return file when successful
    preloaded_modules[#preloaded_modules+1] = {name, file}
    return mod, file
  end
  function build_bytecode(str)
    return load(build_bytecode_mod(preloaded_modules) .. "\nrequire'luametalatex-lateinit'(function()" .. str .. '\nend)', 'preloaded', 't')
  end
end

callback_register('find_format_file', function(name) return kpse.find_file(name, 'fmt', true) end)
function texconfig.init()
  if interaction then
    tex.setinteraction(interaction)
  end
  if build_bytecode then -- Effectivly if status.ini_version
    require'luametalatex-lateinit'(build_bytecode)
  else
    local register = tex.count[262]+1
    lua.bytecode[register]()
    lua.bytecode[register] = nil
  end
end
