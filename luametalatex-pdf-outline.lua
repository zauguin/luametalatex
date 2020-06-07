local outline = {
  { title = "title 1", attr = "", open = true, level = 5,
    { ... },
  }
}
local function add_outline(outline, title, action, level, open, attr)
  local entry = {title = title, action = action, attr = attr, open = open, level = level}
  -- Now find the right nesting level. We have to deal with non-continuous
  -- levels, so we search the last entry which still had a smaller level
  -- and append under that
  local parent
  repeat
    parent = outline
    outline = outline[#outline]
  until not outline or outline.level >= level
  parent[#parent + 1] = entry 
end
local function assign_objnum(pdf, outline)
  local objnum = pdf:getobj()
  outline.objnum = objnum
  local cur
  for i=1,#outline do
    local prev = cur
    cur = outline[i]
    cur.parent = objnum
    assign_objnum(pdf, cur)
    if prev then
      cur.prev = prev.objnum
      prev.next = cur.objnum
    end
  end
  if outline[1] then
    outline.first, outline.last = outline[1].objnum, outline[#outline].objnum
  end
end
local function get_count(pdf, outline)
  local count = 0
  for i=1,#outline do
    local child = outline[i]
    local sub = get_count(pdf, child)
    local open = child.open
    child.count = sub ~= 0 and (open and sub or -sub) or nil
    count = count + 1 + (open and sub or 0)
  end
  return count
end
local function write_objects(pdf, outline)
  local content = "<<"
  local title = outline.title
  if title then
    content = string.format("%s/Title%s", content, title)
  end
  local parent = outline.parent
  if parent then
    content = string.format("%s/Parent %i 0 R", content, parent)
  end
  local prev = outline.prev
  if prev then
    content = string.format("%s/Prev %i 0 R", content, prev)
  end
  local next = outline.next
  if next then
    content = string.format("%s/Next %i 0 R", content, next)
  end
  local first = outline.first
  if first then
    content = string.format("%s/First %i 0 R", content, first)
  end
  local last = outline.last
  if last then
    content = string.format("%s/Last %i 0 R", content, last)
  end
  local action = outline.action
  if action then
    content = string.format("%s/A %i 0 R", content, action)
  end
  local count = outline.count
  if count then
    content = string.format("%s/Count %i", content, count)
  end
  content = content .. (outline.attr or '') .. ">>"
  pdf:indirect(outline.objnum, content)
  for i=1,#outline do
    write_objects(pdf, outline[i])
  end
end
local function write_outline(outline, pdf)
  assign_objnum(pdf, outline)
  local count = get_count(pdf, outline)
  outline.count = count == #outline and count or nil
  write_objects(pdf, outline)
  return outline.objnum
end
local meta = {__index = {
  write = write_outline,
  add = add_outline,
}}
return function()
  return setmetatable({}, meta)
end
