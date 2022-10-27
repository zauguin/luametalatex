-- Provide enough compatibility functions in the node module to make LuaTeX code happy.
--
-- These were added for luaotfload

local properties = node.direct.get_properties_table()
local flush = node.direct.flush_list
local meta = {__gc = function(t) if t.components then flush(t.components) end end}

function node.direct.getcomponents(n)
  local props = properties[n]
  return props and props.components and props.components.components
end

function node.direct.setcomponents(n, comp)
  local props = properties[n]
  if not props then
    if not comp then return end
    props = {components = setmetatable({components = comp}, meta)}
    properties[n] = props
    return
  end
  local props_comp = rawget(props, 'components')
  if props_comp then
    props_comp.components = comp -- Important even if nil to avoid double-free
    if not comp then props.components = nil end
  elseif not comp then
  else
    props.components = setmetatable({components = comp}, meta)
  end
end

local mlist_to_hlist = node.direct.mlist_to_hlist
local todirect = node.direct.todirect
local tonode = node.direct.tonode

function node.mlist_to_hlist(n, ...)
  return tonode(mlist_to_hlist(todirect(n), ...))
end

-- For luapstricks we also need
local hpack = node.direct.hpack

function node.hpack(n, ...)
  local h, b = hpack(todirect(n), ...)
  return tonode(h), b
end

local slide = node.direct.slide

function node.slide(n)
    return tonode(slide(todirect(n)))
end

local vpack = node.direct.vpack

function node.vpack(n, ...)
  local h, b = vpack(todirect(n), ...)
  return tonode(h), b
end

local findattribute = node.direct.findattribute

function node.findattribute(n, a)
    local v, n = findattribute(todirect(n), a)
    if n then
      return v, tonode(n)
    end
end

node.find_attribute = node.findattribute
