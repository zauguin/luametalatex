local io_open = io.open
local write = texio.write
local find_file = kpse.find_file

local callbacks = require'luametalatex-callbacks'

local categories = { data = 1, map = 2, image = 3, subset = 4, font = 5, enc = 6, pdf_stream = 7, pdf_stream = 8, silent = 9}
local start_categories = { [0] = '?', '(', '{', '<', '<', '<<' }
local stop_categories  = { [0] = '?', ')', '}', '>', '>', '>>' }

local function stop_file(t)
  local cb = callbacks.stop_file
  if cb then
    cb(t.category)
  else
    write(stop_categories[t.category] or '')
  end
  t.file:close()
end

local meta = {
  __close = stop_file,
  __call = function(t) return t.file:read'a' end,
  close = stop_file,
  lines = function(t, ...) return t.file:lines(...) end,
}
meta.__index = meta

return function(category, name, kpse, mode)
  category = tonumber(category) or categories[category] or 0
  if kpse then
    name = find_file(name, kpse)
  end
  if not name then return name end
  local f, msg = io_open(name, mode or 'rb')
  if f then
    local cb = callbacks.start_file
    if cb then
      cb(category, name)
    else
      local start_mark = start_categories[category]
      if start_mark then
        write(start_mark .. name)
      end
    end
  end
  return f and setmetatable({category = category, file = f}, meta), msg
end
