-- Provide enough compatibility functions in the node module to make LuaTeX code happy.
--
local direct = node.direct
--
-- These were added for luaotfload

local properties = direct.get_properties_table()
local flush = direct.flush_list
local meta = {__gc = function(t) if t.components then flush(t.components) end end}

function direct.getcomponents(n)
  local props = properties[n]
  return props and props.components and props.components.components
end

function direct.setcomponents(n, comp)
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

local mlist_to_hlist = direct.mlist_to_hlist
local todirect = direct.todirect
local tonode = direct.tonode

function node.mlist_to_hlist(n, ...)
  return tonode(mlist_to_hlist(todirect(n), ...))
end

-- For luapstricks we also need
local hpack = direct.hpack

function node.hpack(n, ...)
  local h, b = hpack(todirect(n), ...)
  return tonode(h), b
end

-- Originally for lua-widow-control
local slide = direct.slide
local vpack = direct.vpack
local find_attribute = direct.find_attribute
local effective_glue = direct.effective_glue

function node.slide(n) return tonode(slide(todirect(n))) end
function node.vpack(n, ...)
  local v, b = vpack(todirect(n), ...)
  return tonode(v), b
end
function node.find_attribute(n, id)
  local val, found = find_attribute(todirect(n), id)
  if val then
    return val, tonode(found)
  end
end
function node.effective_glue(n, m, round)
  return effective_glue(todirect(n), todirect(m), round)
end

--
local has_attribute = direct.has_attribute

function node.has_attribute(n, ...) return has_attribute(todirect(n), ...) end
