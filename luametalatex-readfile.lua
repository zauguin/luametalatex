local io_open = io.open
local write = texio.write
local find_file = kpse.find_file

local callbacks = require'luametalatex-callbacks'

-- local categories = { data = 1, map = 2, image = 3, subset = 4, font = 5 -- , enc = 6, pdf_stream = 7, pdf_stream = 8, silent = 9}

local our_callbacks = {
  vf       = {'vf',             false, 'rb', 'find_vf_file',       'read_vf_file'},
  tfm      = {'tfm',            false, 'rb', 'find_font_file',     'read_font_file'},
  map      = {'map',            2,     'r',  'find_map_file',      'read_map_file'},
  enc      = {'enc files',      false, 'r',  'find_enc_file',      'read_enc_file'},
  type1    = {'type1 fonts',    4,     'rb', 'find_type1_file',    'read_type1_file'},
  truetype = {'truetype fonts', 4,     'rb', 'find_truetype_file', 'read_truetype_file'},
  opentype = {'opentype fonts', 4,     'rb', 'find_opentype_file', 'read_opentype_file'},
  pk       = {'pk',             4,     'rb', 'find_pk_file',       'read_pk_file'},
  image    = {'tex',            3,     'rb', 'find_image_file',    'read_image_file'},
  data     = {'tex',            1,     'rb', 'find_data_file',     'read_data_file'},
}

local start_categories = { [0] = '?', '(', '{', '<', '<', '<<' }
local stop_categories  = { [0] = '?', ')', '}', '>', '>', '>>' }

local function stop_file(t)
  local cb = callbacks.stop_file
  if cb then
    cb(t.category)
  else
    write(stop_categories[t.category] or '')
  end
  if t.file then t.file:close() end
end

local meta_file = {
  __close = stop_file,
  __call = function(t) return t.file:read'a' end,
  close = stop_file,
  lines = function(t, ...) return t.file:lines(...) end,
}
meta_file.__index = meta_file

local meta_data = {
  __close = stop_file,
  __call = function(t) return t.data end,
  close = stop_file,
  lines = function(t, ...) return t.data:gmatch('([^\n]*)\n') end,
}
meta_data.__index = meta_data

return function(kind, name, ...)
  local handle
  local kind_info = our_callbacks[kind]
  local msg
  if kind_info then
    local find_callback = callbacks[kind_info[4]]
    if find_callback then
      name, msg = find_callback(name, ...)
    else
      name, msg = find_file(name, kind_info[1], ...)
    end
    if not name then return name, msg end
    handle = {category = kind_info[2]}
    local read_callback = callbacks[kind_info[5]]
    if read_callback then
      local success, data, size = read_callback(name)
      if not success then return success, data end
      if size < #data then data = data:sub(1,size) end
      handle.data = data, data
      setmetatable(handle, meta_data)
    else
      local f f, msg = io_open(name, kind_info[3])
      if not f then return f, msg end
      handle.file = f
      setmetatable(handle, meta_file)
    end
    if handle.category then
      local cb = callbacks.start_file
      if cb then
        cb(handle.category, name)
      else
        write(start_categories[handle.category] .. name)
      end
    end
  else
    error[[Unknown file]]
  end
  return handle, name
end
