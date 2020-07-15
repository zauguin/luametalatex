-- Now overwrite the callback functionality. Our system is based on the ssumption there there are
-- no unknown callback names, just callbacks very unlikely to ever be called. That doesn't lead to
-- good error checking, but we expect this to be overwritten by LaTeX anyway.

local callback_find = callback.find
local callback_register = callback.register
local rawset = rawset
local callbacks = setmetatable({}, {
  __index = function(cbs, name)
    return callback_find(name)
  end,
  __newindex = function(cbs, name, new)
    return callback_register(name, new) or rawset(cbs, name, new)
  end,
})

function callback.register(name, new)
  callbacks[name] = new
end
function callback.find(name)
  return callbacks[name]
end

return callbacks
