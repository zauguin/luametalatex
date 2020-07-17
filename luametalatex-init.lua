do
  local ourpath
  ourpath, texconfig.formatname = lua.startupfile:match('(.*[/\\])([^/\\]*)%-init%.lua$')
  local function try_lib(name)
    local path = string.format('%s%s.%s', ourpath, name,
      os.type == 'windows' and 'dll' or 'so')
    return package.loadlib(path, '*') and path
  end
  local library  = try_lib'luametalatex' or try_lib'kpse'
  if not library then
    error[[C support library not found. Please fix your installation]]
  end
  kpse = assert(package.loadlib(library, 'luaopen_luametalatex_kpse') or package.loadlib(library, 'luaopen_kpse'))()
  package.loaded.kpse = kpse
  package.preload.luaharfbuzz = package.loadlib(library, 'luaopen_luametalatex_harfbuzz') or package.loadlib(library, 'luaopen_luametalatex_harfbuzz') or nil
end
do
  local arg_pattern = '-' * lpeg.P'-'^-1 * lpeg.C((1-lpeg.P'=')^1) * ('=' * lpeg.C(lpeg.P(1)^0) + lpeg.Cc(true))
  for _, a in ipairs(arg) do
    local name, value = arg_pattern:match(a)
    if name then
      arg[name] = math.tointeger(value) or value
    end
  end
end
kpse.set_program_name(arg.arg0 or arg[arg[0]], arg.progname)
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
kpse.set_maketex("pk", true, "compile")
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
  local interaction = ({ [true] = 3, [false] = false,
    batchmode=0,
    nonstopmode=1,
    scrollmode=2,
    errorstopmode=3,
  })[arg.interaction or false]
  if interaction then
    tex.setinteraction(interaction)
  elseif interaction == nil then
    texio.write('term', string.format('Unknown interaction mode %q ignored.\n', arg.interaction))
  end
  if build_bytecode then -- Effectivly if status.ini_version
    require'luametalatex-lateinit'(build_bytecode)
  else
    local register = tex.count[262]+1
    lua.bytecode[register]()
    lua.bytecode[register] = nil
  end
end
