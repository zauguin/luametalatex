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

-- Copied from ConTeXt's "node-cmp.lmt"
-- if not modules then modules = { } end modules ['node-cmp'] = {
--   version   = 1.001,
--   comment   = "companion to node-ini.mkiv",
--   author    = "Hans Hagen, PRAGMA-ADE, Hasselt NL",
--   copyright = "PRAGMA ADE / ConTeXt Development Team",
--   license   = "see context related readme files"
-- }

local type = type

local node     = node
local direct   = node.direct
local todirect = direct.tovaliddirect
local tonode   = direct.tonode

local count  = direct.count
local length = direct.length
local slide  = direct.slide

function node.count(id,first,last)
  return count(id,first and todirect(first), last and todirect(last) or nil)
end

function node.length(first,last)
  return length(first and todirect(first), last and todirect(last) or nil)
end

function node.slide(n)
  if n then
      n = slide(todirect(n))
      if n then
          return tonode(n)
      end
  end
  return nil
end

local hyphenating = direct.hyphenating
local ligaturing  = direct.ligaturing
local kerning     = direct.kerning

-- kind of inconsistent

function node.hyphenating(first,last)
  if first then
      local h, t = hyphenating(todirect(first), last and todirect(last) or nil)
      return h and tonode(h) or nil, t and tonode(t) or nil, true
  else
      return nil, false
  end
end

function node.ligaturing(first,last)
  if first then
      local h, t = ligaturing(todirect(first), last and todirect(last) or nil)
      return h and tonode(h) or nil, t and tonode(t) or nil, true
  else
      return nil, false
  end
end

function node.kerning(first,last)
  if first then
      local h, t = kerning(todirect(first), last and todirect(last) or nil)
      return h and tonode(h) or nil, t and tonode(t) or nil, true
  else
      return nil, false
  end
end

local protectglyph    = direct.protectglyph
local unprotectglyph  = direct.unprotectglyph
local protectglyphs   = direct.protectglyphs
local unprotectglyphs = direct.unprotectglyphs

function node.protectglyphs(first,last)
  protectglyphs(todirect(first), last and todirect(last) or nil)
end

function node.unprotectglyphs(first,last)
  unprotectglyphs(todirect(first), last and todirect(last) or nil)
end

function node.protectglyph(first)
  protectglyph(todirect(first))
end

function node.unprotectglyph(first)
  unprotectglyph(todirect(first))
end

local flattendiscretionaries = direct.flattendiscretionaries
local checkdiscretionaries   = direct.checkdiscretionaries
local checkdiscretionary     = direct.checkdiscretionary

function node.flattendiscretionaries(first)
  local h, count = flattendiscretionaries(todirect(first))
  return tonode(h), count
end

function node.checkdiscretionaries(n) checkdiscretionaries(todirect(n)) end
function node.checkdiscretionary  (n) checkdiscretionary  (todirect(n)) end

local hpack        = direct.hpack
local vpack        = direct.vpack
local mlisttohlist = direct.mlisttohlist

function node.hpack(head,...)
  local h, badness = hpack(head and todirect(head) or nil,...)
  return tonode(h), badness
end

function node.vpack(head,...)
  local h, badness = vpack(head and todirect(head) or nil,...)
  return tonode(h), badness
end

function node.mlisttohlist(head,...)
  return tonode(mlisttohlist(head and todirect(head) or nil,...))
end

local endofmath      = direct.endofmath
local findattribute  = direct.findattribute
local firstglyph     = direct.firstglyph

function node.endofmath(n)
  if n then
      n = endofmath(todirect(n))
      if n then
          return tonode(n)
      end
  end
  return nil
end

function node.findattribute(n,a)
  if n then
      local v, n = findattribute(todirect(n),a)
      if n then
          return v, tonode(n)
      end
  end
  return nil
end

function node.firstglyph(first,last)
  local n = firstglyph(todirect(first), last and todirect(last) or nil)
  return n and tonode(n) or nil
end

local dimensions      = direct.dimensions
local rangedimensions = direct.rangedimensions
local effectiveglue   = direct.effectiveglue

function node.dimensions(a,b,c,d,e)
  if type(a) == "userdata" then
      a = todirect(a)
      if type(b) == "userdata" then
          b = todirect(b)
      end
      return dimensions(a,b)
  else
      d = todirect(d)
      if type(e) == "userdata" then
          e = todirect(e)
      end
      return dimensions(a,b,c,d,e)
  end
  return 0, 0, 0
end

function node.rangedimensions(parent,first,last)
  return rangedimensions(todirect(parent),todirect(first),last and todirect(last))
end

function node.effectiveglue(list,parent)
  return effectiveglue(list and todirect(list) or nil,parent and todirect(parent) or nil)
end

local usesfont            = direct.usesfont
local hasglyph            = direct.hasglyph
local protrusionskippable = direct.protrusionskippable

function node.usesfont           (n,f) return usesfont(todirect(n),f)          end
function node.hasglyph           (n)   return hasglyph(todirect(n))            end
function node.protrusionskippable(n)   return protrusionskippable(todirect(n)) end

local makeextensible = direct.make_extensible
local lastnode       = direct.lastnode

function node.makeextensible(...) local n = makeextensible(...) return n and tonode(n) or nil end
function node.lastnode      ()    local n = lastnode()          return n and tonode(n) or nil end

local iszeroglue = direct.iszeroglue
local getglue    = direct.getglue
local setglue    = direct.setglue

function node.iszeroglue(n) return iszeroglue(todirect(n)) end
function node.getglue   (n) return getglue   (todirect(n)) end
function node.setglue   (n) return setglue   (todirect(n)) end

node.family_font               = tex.getfontoffamily
-- End of "node-cmp.lmt"

-- Add the old underscored names:
node.protect_glyph           = node.protectglyph
node.unprotect_glyph         = node.unprotectglyph
node.protect_glyphs          = node.protectglyphs
node.unprotect_glyphs        = node.unprotectglyphs

node.flatten_discretionaries = node.flattendiscretionaries
node.check_discretionaries   = node.checkdiscretionaries
node.check_discretionary     = node.checkdiscretionary

node.mlist_to_hlist          = node.mlisttohlist

node.end_of_math             = node.endofmath
node.find_attribute          = node.findattribute
node.first_glyph             = node.firstglyph

node.range_dimensions        = node.rangedimensions
node.effective_glue          = node.effectiveglue

node.uses_font               = node.usesfont
node.has_glyph               = node.hasglyph
node.protrusion_skippable    = node.protrusionskippable

node.make_extensible         = node.makeextensible
node.last_node               = node.lastnode

node.is_zero_glue            = node.iszeroglue
node.get_glue                = node.getglue
node.set_glue                = node.setglue
