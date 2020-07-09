-- Two callbacks are defined in other files: pre_dump in lateinit and find_fmt_file in init

local read_tfm = font.read_tfm
local font_define = font.define
local callback_register = callback.register

if status.ini_version then
  callback_register('define_font', function(name, size)
    local f = read_tfm(name, size)
    if not f then return end
    local id = font_define(f)
    lua.prepared_code[#lua.prepared_code+1] = string.format("assert(%i == font.define(font.read_tfm(%q, %i)))", id, name, size)
    return id
  end)
else
  callback_register('define_font', function(name, size)
    local f = read_tfm(name, size)
    if not f then return end
    return font.define(f)
  end)
end
callback_register('find_log_file', function(name) return name end)
do
  local function normal_find_data_file(name)
    return kpse.find_file(name, 'tex', true)
  end
  if status.ini_version then
    function unhook_expl()
      callback_register('find_data_file', normal_find_data_file)
    end
    callback_register('find_data_file', function(name)
      if name == 'ltexpl.ltx' then
        name = 'luametalatex-ltexpl-hook'
      end
      return normal_find_data_file(name)
    end)
  else
    callback_register('find_data_file', normal_find_data_file)
  end
end
-- callback_register('read_data_file', function(name) error[[TODO]]return kpse.find_file(name, 'tex', true) end)
callback_register('open_data_file', function(name)
  local f = io.open(name, 'r')
  return setmetatable({
    reader = function()
      local line = f:read()
      return line
    end,
    close = function()error[[1]] return f:close() end,
  }, {
    __gc = function()f:close()end,
  })
end)
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
      texio.write(tex.gethelptext() or "Sorry, I don't know how to help in this situation.\n\z
        Maybe you should try asking a human?")
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
