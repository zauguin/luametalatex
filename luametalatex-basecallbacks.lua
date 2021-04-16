-- Three callbacks are defined in other files: stop_run in back-pdf, pre_dump in lateinit, and find_fmt_file in init

local read_tfm = font.read_tfm
local font_define = font.define
local callbacks = require'luametalatex-callbacks'

if status.ini_version then
  function callbacks.define_font(name, size)
    local f = read_tfm(name, size)
    if not f then return end
    local id = font_define(f)
    lua.prepared_code[#lua.prepared_code+1] = string.format("assert(%i == font.define(font.read_tfm(%q, %i)))", id, name, size)
    return id
  end
else
  function callbacks.define_font(name, size)
    local f = read_tfm(name, size)
    if not f then
      tex.error(string.format("Font %q not found", name), "The requested font could't be loaded.\n\z
        Are you sure that you passed the right name and\n\z
        that the font is actually installed?")
      return 0
    end
    return font.define(f)
  end
end
callbacks.__freeze'define_font'

function callbacks.find_log_file(name) return name end
callbacks.__freeze'find_log_file'

-- find_data_file is not an engine callback in luametatex, so we don't __freeze it
if status.ini_version then
  function unhook_expl()
    callbacks.find_data_file = nil
  end
  function callbacks.find_data_file(name)
    if name == 'ltexpl.ltx' then
      name = 'luametalatex-ltexpl-hook'
    end
    return kpse.find_file(name, 'tex', true)
  end
end
  local function normal_find_data_file(name)
    return kpse.find_file(name, 'tex', true)
  end
function callbacks.open_data_file(name)
  local find_callback = callbacks.find_data_file
  local path
  if find_callback then
    path = find_callback(name)
  else
    path = kpse.find_file(name, 'tex', true)
  end
  if not path then return end

  local open_callback = callbacks.open_data_file
  if open_callback then
    return open_callback(path)
  end

  local f = io.open(path, 'r')
  return f and setmetatable({
    reader = function()
      local line = f:read()
      return line
    end,
    close = function() f:close() f = nil end,
  }, {
    __gc = function() if f then f:close() end end,
  })
end
callbacks.__freeze('open_data_file', true)

local do_terminal_input do
  local function terminal_open_data_file()
    local old = callbacks.open_data_file
    return function()
      callbacks.open_data_file = old
      return {
        reader = function()
          texio.write_nl('term', '* ')
          local line = io.stdin:read()
          return line
        end,
        close = function() end,
      }
    end
  end
  function do_terminal_input()
    local old_find = callbacks.find_data_file
    function callbacks.find_data_file(name) 
      callbacks.find_data_file = old_find 
      return name
    end
    callbacks.open_data_file = terminal_open_data_file()
    token.put_next(token.create'expandafter', token.create'relax', token.create'input', 'TERMINAL ')
    token.skip_next_expanded()
  end
end

local errorvalues = tex.geterrorvalues()
function callbacks.intercept_tex_error(mode, errortype)
  errortype = errorvalues[errortype]
  if errortype == "eof" then
    -- print('EOF', token.peek_next())
    token.put_next(token.create'ABD')
    return 3
  end
  texio.write'.'
  tex.showcontext()
  if mode ~= 3 then return mode end
  repeat
    texio.write_nl'? '
    local line = io.read()
    if not line then
      tex.fatalerror'End of line encountered on terminal'
    end
    if line == "" then return 3 end
    local first = line:sub(1,1):upper()
    if first == 'H' then
      texio.write(tex.gethelptext() or "Sorry, I don't know how to help in this situation.\n\z
        Maybe you should try asking a human?")
    elseif first == 'I' then
      line = line:sub(2)
      tex.runlocal(function()
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
end
callbacks.__freeze'intercept_tex_error'
