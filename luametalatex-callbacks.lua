-- Now overwrite the callback functionality. Our system is based on the ssumption there there are
-- no unknown callback names, just callbacks very unlikely to ever be called. That doesn't lead to
-- good error checking, but we expect this to be overwritten by LaTeX anyway.
--
-- There are four callback types on this level:
--  1. luametalatex defined callbacks. They are not real engine callbacks, the code using them is
--     responsible for their potential non-existance.
--  2. Engine callbacks not defined by us. They are simply passed on to the engine. All engine
--     callbacks are set to this by default.
--  3. Engine callbacks with a provided default. There is a luametalatex implementation, but it
--     can be overwritten by the user. If the user disabled their implementation, so provided
--     default is restored.
--  4. Engine callbacks with mandatory code. The luametalatex implementation can not be overwitten
--     by the user, but a luametalatex-defined callback is added with the same name.
--
--  A callback has type 1 or type 4 if is_user_callback is true. If it has type 4, is_user_callback
--  has to be set manually and in addition, an implementation if the system callback is registered.
--
--  A callback has type 3, if is_user_callback is false and system_callbacks is defined.

local callback_known = callback.known
local callback_find = callback.find
local callback_register = callback.register
local rawset = rawset
local system_callbacks = {}
local is_user_callback = setmetatable({}, {
  __index = function(t, name)
    local is_user = not callback_known(name)
    t[name] = is_user
    return is_user
  end,
})
local callbacks callbacks = setmetatable({
  __freeze = function(name, fixed)
    -- Convert from type 2 to type 3 or 4. This function will be deleted before user code runs.
    assert(not is_user_callback[name], 'Not a system callback')
    assert(not system_callbacks[name], 'Already frozen')
    is_user_callback[name] = fixed and true or false
    system_callbacks[name] = callback_find(name)
    rawset(callbacks, name, nil)
    assert(system_callbacks[name], 'Attempt to freeze undefined callback')
  end,
}, {
  __index = function(cbs, name)
    if is_user_callback[name] then
      -- Avoid repetitive lookups
      rawset(cbs, name, false)
      return false
    end
    return callback_find(name)
  end,
  __newindex = function(cbs, name, new)
    if is_user_callback[name] then
      -- Avoid repetitive lookups
      rawset(cbs, name, new or false)
      return
    end
    return callback_register(name, new or system_callbacks[name])
  end,
})

function callback.register(name, new)
  callbacks[name] = new
end
-- The and ... or construction makes sure that even in raw mode, non-engine callbacks are found
function callback.find(name, raw)
  return raw and callback_find(name) or callbacks[name]
end

return callbacks
