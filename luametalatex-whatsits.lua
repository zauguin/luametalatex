local whatsit_id = node.id'whatsit'
local whatsits = {
  [0] = "open",
        "write",
        "close",
        "special",
        nil,
        nil,
        "save_pos",
        "late_lua",
        "user_defined",
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        "pdf_literal",
        "pdf_refobj",
        "pdf_annot",
        "pdf_start_link",
        "pdf_end_link",
        "pdf_dest",
        "pdf_action",
        "pdf_thread",
        "pdf_start_thread",
        "pdf_end_thread",
        "pdf_thread_data",
        "pdf_link_data",
        "pdf_colorstack",
        "pdf_setmatrix",
        "pdf_save",
        "pdf_restore",
}
local whatsithandler = {}
-- for i = 0,#whatsits do -- #whatsits isn't guaranteed to work because of the nil entries
for i = 0,31 do
  local v = whatsits[i]
  if v then
    whatsits[v] = i
  end
end
function node.whatsits() return whatsits end
function node.subtype(s) return type(s) == "string" and whatsits[s] or nil end

local direct = node.direct
local getsubtype = direct.getsubtype
local properties = direct.get_properties_table()
local tonode, todirect = direct.tonode, direct.todirect

local function get_handler(n, subtype)
  local props = properties[n]
  return props and props.handle or whatsithandler[subtype or getsubtype(n)], props
end
local function new(name, handler)
  assert(type(name) == 'string')
  local subtype = whatsits[name]
  if subtype then
    if whatsithandler[subtype] then
      texio.write_nl'WARNING: Overwriting default whatsit handler'
    end
  else
    subtype = #whatsits + 1
    whatsits[subtype] = name
    whatsits[name] = subtype
  end
  whatsithandler[subtype] = handler
  return subtype
end

-- TODO: Some fields might expect different values
local function setwhatsitfield(n, name, value)
  local props = properties[n]
  if not props then
    props = {}
    properties[n] = props
  end
  props[name] = value
end
direct.setwhatsitfield = setwhatsitfield

local function getwhatsitfield(n, name)
  local props = properties[n]
  return props and props[name]
end
direct.getwhatsitfield = getwhatsitfield

-- TODO: Some fields might be nodes and therefore have to be converted
function node.setwhatsitfield(n, ...) return setwhatsitfield(todirect(n), ...) end
function node.getwhatsitfield(n, ...) return getwhatsitfield(todirect(n), ...) end

return {
  handler = get_handler,
  new = new,
}
