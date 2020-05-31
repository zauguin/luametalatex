local format = string.format
local concat = table.concat
local write = texio.write_nl
local direct = node.direct
local properties = direct.properties
local tonode = direct.tonode
local todirect = direct.todirect
local getid = direct.getid
local traverse = direct.traverse
local getsubtype = direct.getsubtype
local getdirection = direct.getdirection
local setsubtype = direct.setsubtype
local getdepth = direct.getdepth
local getheight = direct.getheight
local getwidth = direct.getwidth
local setdepth = direct.setdepth
local setheight = direct.setheight
local setwidth = direct.setwidth
local getshift = direct.getshift
local getlist = direct.getlist
local getkern = direct.getkern
local getreplace = direct.getreplace
local getleader = direct.getleader
local setfont = direct.setfont
local getfont = direct.getfont
local getoffsets = direct.getoffsets
local getnext = direct.getnext
local getexpansion = direct.getexpansion
local getchar = direct.getchar
local rangedimensions = direct.rangedimensions
local traverse_id = direct.traverse_id

local dir_id = node.id'dir'

local function doublekeyed(t, id2name, name2id, index)
  return setmetatable(t, {
      __index = index,
      __newindex = function(t, k, v)
        rawset(t, k, v)
        if type(k) == 'string' then
          rawset(t, name2id(k), v)
        else
          rawset(t, id2name(k), v)
        end
      end,
    })
end
local nodehandler = (function()
  local function unknown_handler(_, n, x, y)
    print(node.type(10))
    write(format("Sorry, but the PDF backend does not support %q (id = %i) nodes right now. The supplied node will be dropped at coordinates (%i, %i).", node.type(getid(n)), getid(n), x//1, y//1))
  end
  return doublekeyed({}, node.type, node.id, function()
    return unknown_handler
  end)
end)()
local whatsithandler = (function()
  local whatsits = node.whatsits()
  local function unknown_handler(p, n, x, y, ...)
    local prop = properties[n]-- or node.getproperty(n)
    if prop and prop.handle then
      prop:handle(p, n, x, y, ...)
    else
      write(format("Sorry, but the PDF backend does not support %q (id = %i) whatsits right now. The supplied node will be dropped at coordinates (%i, %i).", whatsits[getsubtype(n)], getsubtype(n), x//1, y//1))
    end
  end
  return doublekeyed({}, function(n)return whatsits[n]end, function(n)return whatsits[n]end, function()
    return unknown_handler
  end)
end)()
local glyph, text, page, cm_pending = 1, 2, 3, 4
local gsub = string.gsub
local function projected_point(m, x, y, w)
  w = w or 1
  return x*m[1] + y*m[3] + w*m[5], x*m[2] + y*m[4] + w*m[6]
end
local function pdfsave(p, x, y)
  local lastmatrix = p.matrix
  p.matrix = {[0] = lastmatrix, table.unpack(lastmatrix)}
end
local function pdfmatrix(p, a, b, c, d, e, f)
  local m = p.matrix
  a, b = projected_point(m, a, b, 0)
  c, d = projected_point(m, c, d, 0)
  e, f = projected_point(m, e, f, 1)
  m[1], m[2], m[3], m[4], m[5], m[6] = a, b, c, d, e, f
end
local function pdfrestore(p, x, y)
  -- TODO: Check x, y
  p.matrix = p.matrix[0]
end
local function sp2bp(sp)
  return sp/65781.76
end
local topage
local function totext(p, fid)
  local last = p.mode
  if last == glyph then
    p.pending[#p.pending+1] = ")]TJ"
    p.strings[#p.strings+1] = concat(p.pending)
    for i=1,#p.pending do p.pending[i] = nil end
    last = text
  end
  if last == cm_pending then topage(p) end
  p.mode = text
  if last == text and p.font.fid == fid then return end
  local f = font.getfont(fid) or font.fonts[fid]
  if last ~= text then p.strings[#p.strings+1] = "BT" p.pos.lx, p.pos.ly, p.pos.x, p.pos.y, p.font.exfactor = 0, 0, 0, 0, 0 end
  p:fontprovider(f, fid)
  -- p.strings[#p.strings+1] = format("/F%i %f Tf 0 Tr", f.parent, sp2bp(f.size)) -- TODO: Setting the mode, expansion, etc.
  p.font.fid = fid
  p.font.font = f
  return false -- Return true if we need a new textmatrix
end
local inspect = require'inspect'
local function show(t) print(inspect(t)) end
function topage(p)
  local last = p.mode
  if last == page then return end
  if last <= text then
    totext(p, p.font.fid) -- First make sure we are really in text mode
    p.strings[#p.strings+1] = "ET"
  elseif last == cm_pending then
    local pending = p.pending_matrix
    if pending[1] ~= 1 or pending[2] ~= 0 or pending[3] ~= 0 or pending[4] ~= 1 or pending[5] ~= 0 or pending[6] ~= 0 then
      p.strings[#p.strings+1] = format("%f %f %f %f %f %f cm", pending[1], pending[2], pending[3], pending[4], sp2bp(pending[5]), sp2bp(pending[6]))
    end
  else
    error[[Unknown mode]]
  end
  p.mode = page
end
local function toglyph(p, fid, x, y, exfactor)
  local last = p.mode
  if last == glyph and p.font.fid == fid and p.pos.y == y and p.font.exfactor == exfactor then
    if x == p.pos.x then return end
    local xoffset = (x - p.pos.x)/p.font.font.size * 1000 / (1+exfactor/1000000)
    if math.abs(xoffset) < 1000000 then -- 1000000 is arbitrary
      p.pending[#p.pending+1] = format(")%i(", math.floor(-xoffset))
      p.pos.x = x
      return
    end
  end
  if totext(p, fid) or exfactor ~= p.font.exfactor then
    p.font.exfactor = exfactor
    p.strings[#p.strings+1] = gsub(format("%f 0.0 %f %f %f %f Tm", 1+exfactor/1000000, 0, 1, sp2bp(x), sp2bp(y)), '%.?0+ ', ' ')
  else
    p.strings[#p.strings+1] = gsub(format("%f %f Td", sp2bp((x - p.pos.lx)/(1+exfactor/1000000)), sp2bp(y - p.pos.ly)), '%.?0+ ', ' ')
  end
  p.pos.lx, p.pos.ly, p.pos.x, p.pos.y = x, y, x, y
  p.mode = glyph
  p.pending[1] = "[("
end
local function write_matrix(p, a, b, c, d, e, f)
  local pending = p.pending_matrix
  if p.mode ~= cm_pending then
    topage(p)
    p.mode = cm_pending
    pending[1], pending[2], pending[3], pending[4], pending[5], pending[6] = a, b, c, d, e, f
    return
  else
    a, b = projected_point(pending, a, b, 0)
    c, d = projected_point(pending, c, d, 0)
    e, f = projected_point(pending, e, f, 1)
    pending[1], pending[2], pending[3], pending[4], pending[5], pending[6] = a, b, c, d, e, f
    return
  end
end
local linkcontext = {}
-- local function get_action_attr(p, action)
  -- if action.action_type == 3 then
    -- return action.data
  -- elseif action.action_type == 2 then
local function write_link(p, link)
  local quads = link.quads
  local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
  assert(link.action.action_type == 3) -- TODO: Other types
  local attr = link.attr .. link.action.data
  assert(#quads%8==0)
  local quadStr = {}
  for i=1,#quads,8 do
    local x1, y1, x4, y4, x2, y2, x3, y3 = table.unpack(quads, i, i+7)
    x1, y1, x2, y2, x3, y3, x4, y4 = sp2bp(x1), sp2bp(y1), sp2bp(x2), sp2bp(y2), sp2bp(x3), sp2bp(y3), sp2bp(x4), sp2bp(y4)
    quadStr[i//8+1] = string.format("%f %f %f %f %f %f %f %f", x1, y1, x2, y2, x3, y3, x4, y4)
    minX = math.min(minX, x1, x2, x3, x4)
    minY = math.min(minY, y1, y2, y3, y4)
    maxX = math.max(maxX, x1, x2, x3, x4)
    maxY = math.max(maxY, y1, y2, y3, y4)
  end
  p.file:indirect(link.objnum, string.format("<</Rect[%f %f %f %f]/QuadPoints[%s]%s>>", minX-.2, minY-.2, maxX+.2, maxY+.2, table.concat(quadStr, ' '), attr))
  for i=1,#quads do quads[i] = nil end
  link.objnum = nil
end
local function addlinkpoint(p, link, x, y, list, kind)
  local quads = link.quads
  local off = pdf.variable.linkmargin
  x = kind == 'start' and x-off or x+off
  if link.annots and link.annots ~= p.annots then -- We started on another page, let's finish that before starting the new page
    write_link(p, link)
    link.annots = nil
  end
  if not link.annots then
    link.annots = p.annots -- Just a marker to indicate the page
    link.objnum = link.objnum or p.file:getobj()
    p.annots[#p.annots+1] = link.objnum .. " 0 R"
  end
  local m = p.matrix
  local lx, ly = projected_point(m, x, y-off-(link.depth or getdepth(list)))
  local ux, uy = projected_point(m, x, y+off+(link.height or getheight(list)))
  local n = #quads
  quads[n+1], quads[n+2], quads[n+3], quads[n+4] = lx, ly, ux, uy
  if kind == 'final' or (link.force_separate and (n+4)%8 == 0) then
    print(kind, n, link.force_separate)
    write_link(p, link)
    link.annots = nil
  end
end
function nodehandler.hlist(p, list, x0, y, outerlist, origin, level)
  if outerlist then
    if getid(outerlist) == 0 then
      y = y - getshift(list)
    else
      x0 = x0 + getshift(list)
    end
  end
  local direction = getdirection(list)
  if direction == 1 then
    x0 = x0 + getwidth(list)
  end
  local dirstack = {}
  local dirnodes = {}
  for n, sub in traverse_id(dir_id, getlist(list)) do
    if sub == 0 then
      dirstack[#dirstack + 1] = n
    else
      local m = dirstack[#dirstack]
      dirnodes[m] = n
      dirstack[#dirstack] = nil
    end
  end
  for i=1,#dirstack do
    dirnodes[dirstack[i]] = rangedimensions(list, dirstack[i])
  end
  local x = x0
  for _,l in ipairs(p.linkcontext) do if l.level == level+1 then
      addlinkpoint(p, l, x, y, list, 'start')
  end end
  for n, id, sub in traverse(getlist(list)) do
    if id == dir_id then
      if sub == 0 then
        local newdir = getdirection(n)
        if newdir ~= direction then
          local close = dirnodes[n]
          local dim = rangedimensions(list, n, close)
          if close then dirnodes[close] = dim end
          x = x + (2*newdir-1) * dim
          direction = newdir
        end
      else
        local dim = dirnodes[n]
        if dim then
          direction = 1-direction
          x = x + (2*newdir-1) * dim
        end
      end
    else
      local next = getnext(n)
      local w = next and rangedimensions(list, n, next) or rangedimensions(list, n)
      if direction == 1 then x = x - w end
      nodehandler[id](p, n, x, y, list, x0, level+1)
      if direction == 0 then x = w + x end
    end
  end
  for _,l in ipairs(p.linkcontext) do if l.level == level+1 then
      addlinkpoint(p, l, x, y, list, 'end')
  end end
end
function nodehandler.vlist(p, list, x, y0, outerlist, origin, level)
  if outerlist then
    if getid(outerlist) == 0 then
      y0 = y0 - getshift(list)
    else
      x = x + getshift(list)
    end
  end
  y0 = y0 + getheight(list)
  local y = y0
  for n in traverse(getlist(list)) do
    local d, h, _ = 0, direct.effective_glue(n, list) or math.tointeger(getkern(n))
    if not h then
      _, h, d = direct.getwhd(n)
    end
    y = y - (h or 0)
    nodehandler[getid(n)](p, n, x, y, list, y0, level+1)
    y = y - (d or 0)
  end
end
function nodehandler.rule(p, n, x, y, outer)
  if getwidth(n) == -1073741824 then setwidth(n, getwidth(outer)) end
  if getheight(n) == -1073741824 then setheight(n, getheight(outer)) end
  if getdepth(n) == -1073741824 then setdepth(n, getdepth(outer)) end
  local sub = getsubtype(n)
  if sub == 1 then
    error[[We can't handle boxes yet]]
  elseif sub == 2 then
    error[[We can't handle images yet]]
  elseif sub == 3 then
  elseif sub == 4 then
    error[[We can't handle user rules yet]]
  elseif sub == 9 then
    error[[We can't handle outline rules yet]]
  else
    if getwidth(n) <= 0 or getdepth(n) + getheight(n) <= 0 then return end
    topage(p)
    p.strings[#p.strings+1] = gsub(format("%f %f %f %f re f", sp2bp(x), sp2bp(y - getdepth(n)), sp2bp(getwidth(n)), sp2bp(getdepth(n) + getheight(n))), '%.?0+ ', ' ')
  end
end
function nodehandler.boundary() end
function nodehandler.disc(p, n, x, y, list, ...) -- FIXME: I am not sure why this can happen, let's assume we can use .replace
  for n in traverse(getreplace(n)) do
    local next = getnext(n)
    local w = next and rangedimensions(list, n, next) or rangedimensions(list, n)
    nodehandler[getid(n)](p, n, x, y, list, ...)
    x = w + x
  end
end
function nodehandler.local_par() end
function nodehandler.math() end
function nodehandler.glue(p, n, x, y, outer, origin, level) -- Naturally this is an interesting one.
  local subtype = getsubtype(n)
  if subtype < 100 then return end -- We only really care about leaders
  local leader = getleader(n)
  local w = direct.effective_glue(n, outer)
  if getid(leader) == 2 then -- We got a rule, this should be easy
    if getid(outer) == 0 then
      setwidth(leader, w)
    else
      setheight(leader, w)
      setdepth(leader, 0)
    end
    return nodehandler.rule(p, leader, x, y, outer)
  end
  local lwidth = getid(outer) == 0 and getwidth(leader) or getheight(leader) + getdepth(leader)
  if getid(outer) ~= 0 then
    y = y + w
  end
  if subtype == 100 then
    if getid(outer) == 0 then
      local newx = ((x-origin - 1)//lwidth + 1) * lwidth + origin
      -- local newx = -(origin-x)//lwidth * lwidth + origin
      w = w + x - newx
      x = newx
    else
      -- local newy = -(origin-y)//lwidth * lwidth + origin
      local newy = (y-origin)//lwidth * lwidth + origin
      w = w + newy - y
      y = newy
    end
  elseif subtype == 101 then
    local inner = w - (w // lwidth) * lwidth
    if getid(outer) == 0 then
      x = x + inner/2
    else
      y = y - inner/2
    end
  elseif subtype == 102 then
    local count = w // lwidth
    local skip = (w - count * lwidth) / (count + 1)
    if getid(outer) == 0 then
      x = x + skip
    else
      y = y - skip
    end
    lwidth = lwidth + skip
  elseif subtype == 103 then
    if getid(outer) == 0 then
      local newx = ((x - 1)//lwidth + 1) * lwidth
      w = w + x - newx
      x = newx
    else
      local newy = y//lwidth * lwidth
      w = w + newy - y
      y = newy
    end
  end
  local handler = nodehandler[getid(leader)]
  if getid(outer) == 0 then
    while w >= lwidth do
      handler(p, leader, x, y, outer, origin, level+1)
      w = w - lwidth
      x = x + lwidth
    end
  else
    y = y - getheight(leader)
    while w >= lwidth do
      handler(p, leader, x, y, outer, origin, level+1)
      w = w - lwidth
      y = y - lwidth
    end
  end
end
function nodehandler.kern() end
function nodehandler.penalty() end
local literalescape = lpeg.Cs((lpeg.S'\\()\r'/{['\\'] = '\\\\', ['('] = '\\(', [')'] = '\\)', ['\r'] = '\\r'}+1)^0)
local match = lpeg.match
local function do_commands(p, c, f, fid, x, y, outer, ...)
  local fonts = f.fonts
  local stack, current_font = {}, fonts[1]
  for _, cmd in ipairs(c.commands) do
    if cmd[1] == "node" then
      local cmd = cmd[2]
      nodehandler[getid(cmd)](p, cmd, x, y, nil, ...)
      x = x + getwidth(cmd)
    elseif cmd[1] == "font" then
      current_font = fonts[cmd[2]]
    elseif cmd[1] == "char" then
      local n = direct.new'glyph'
      setsubtype(n, 256)
      setfont(n, current_font.id, cmd[2])
      nodehandler.glyph(p, n, x, y, outer, ...)
      direct.free(n)
      x = x + getwidth(n)
    elseif cmd[1] == "slot" then
      local n = direct.new'glyph'
      setsubtype(n, 256)
      setfont(n, cmd[2], cmd[3])
      nodehandler.glyph(p, n, x, y, outer, ...)
      direct.free(n)
      x = x + getwidth(n)
    elseif cmd[1] == "rule" then
      local n = direct.new'rule'
      setheight(n, cmd[2])
      setwidth(n, cmd[3])
      nodehandler.rule(p, n, x, y, outer, ...)
      direct.free(n)
      x = x + getwidth(n)
    elseif cmd[1] == "left" then
      x = x + cmd[2]
    elseif cmd[1] == "down" then
      y = y + cmd[2]
    elseif cmd[1] == "push" then
      stack[#stack + 1] = {x, y}
    elseif cmd[1] == "pop" then
      local top = stack[#stack]
      stack[#stack] = nil
      x, y = top[1], top[2]
    elseif cmd[1] == "special" then
      error[[specials aren't supported yet]] -- TODO
    elseif cmd[1] == "pdf" then
      pdf.write(cmd[3] and cmd[2] or "origin", cmd[3], x, y, p)
    elseif cmd[1] == "lua" then
      cmd = cmd[2]
      if type(cmd) == "string" then cmd = load(cmd) end
      assert(type(cmd) == "function")
      pdf._latelua(p, x, y, cmd, fid, c)
    elseif cmd[1] == "image" then
      error[[images aren't supported yet]] -- TODO
      -- ???
    -- else
      -- NOP, comment and invalid commands ignored
    end
    if #commands ~= 1 then error[[Unsupported command number]] end
    if commands[1][1] ~= "node" then error[[Unsupported command name]] end
    commands = commands[1][2]
    nodehandler[getid(commands)](p, commands, x, y, nil, ...)
  end
end
function nodehandler.glyph(p, n, x, y, ...)
  if getfont(n) ~= p.vfont.fid then
    p.vfont.fid = getfont(n)
    p.vfont.font = font.getfont(getfont(n)) or font.fonts[getfont(n)]
  end
  local f, fid = p.vfont.font, p.vfont.fid
  local c = f.characters[getchar(n)]
  if not c then
    texio.write_nl("Missing character")
    return
  end
  if c.commands then return do_commands(p, c, f, fid, x, y, ...) end
  local xoffset, yoffset = getoffsets(n)
  toglyph(p, getfont(n), x + xoffset, y + yoffset, getexpansion(n))
  local index = c.index
  if index then
    -- if f.encodingbytes == -3 then
    if false then
      if index < 0x80 then
        p.pending[#p.pending+1] = match(literalescape, string.pack('>B', index))
      elseif index < 0x7F80 then
        p.pending[#p.pending+1] = match(literalescape, string.pack('>H', index+0x7F80))
      else
        p.pending[#p.pending+1] = match(literalescape, string.pack('>BH', 0xFF, index-0x7F80))
      end
    else
      p.pending[#p.pending+1] = match(literalescape, string.pack('>H', index))
    end
    if not p.usedglyphs[index] then
      p.usedglyphs[index] = {index, math.floor(c.width * 1000 / f.size + .5), c.tounicode}
    end
  else
    p.pending[#p.pending+1] = match(literalescape, string.char(getchar(n)))
    if not p.usedglyphs[getchar(n)] then
      p.usedglyphs[getchar(n)] = {getchar(n), math.floor(c.width * 1000 / f.size + .5), c.tounicode}
    end
  end
  p.pos.x = p.pos.x + math.floor(getwidth(n)*(1+getexpansion(n)/1000000)+.5)
end
function nodehandler.whatsit(p, n, ...) -- Whatsit?
  return whatsithandler[getsubtype(n)](p, n, ...)
end
--[[ -- These use the old whatsit handling system which might get removed.
function whatsithandler.pdf_save(p, n, x, y, outer)
  topage(p)
  p.strings[#p.strings + 1] = 'q'
  pdfsave(p, x, y)
end
function whatsithandler.pdf_restore(p, n, x, y, outer)
  topage(p)
  p.strings[#p.strings + 1] = 'Q'
  pdfrestore(p, x, y)
end
local numberpattern = (lpeg.R'09'^0 * ('.' * lpeg.R'09'^0)^-1)/tonumber
local matrixpattern = numberpattern * ' ' * numberpattern * ' ' * numberpattern * ' ' * numberpattern
function whatsithandler.pdf_setmatrix(p, n, x, y, outer)
  local a, b, c, d = matrixpattern:match(n.data)
  local e, f = (1-a)*x-c*y, (1-d)*y-b*x
  write_matrix(p, a, b, c, d, e, f)
end
function whatsithandler.pdf_start_link(p, n, x, y, outer, _, level)
  local links = p.linkcontext
  local link = {quads = {}, attr = n.link_attr, action = n.action, level = level, force_separate = false} -- force_separate should become an option
  links[#links+1] = link
  addlinkpoint(p, link, x, y, outer, 'start')
end
function whatsithandler.pdf_end_link(p, n, x, y, outer, _, level)
  local links = p.linkcontext
  local link = links[#links]
  links[#links] = nil
  if link.level ~= level then error"Wrong link level" end
  addlinkpoint(p, link, x, y, outer, 'final')
end
]]
local global_p, global_x, global_y
function pdf._latelua(p, x, y, func, ...)
  global_p, global_x, global_y = p, x, y
  return func(...)
end
function pdf.write(mode, text, x, y, p)
  x, y, p = x or global_x, y or global_y, p or global_p
  if mode == "page" then
    topage(p)
    p.strings[#p.strings + 1] = text
  elseif mode == "text" then
    topage(p)
    p.strings[#p.strings + 1] = text
  elseif mode == "direct" then
    if p.mode ~= page then
      totext(p, p.font.fid)
    end
    p.strings[#p.strings + 1] = text
  elseif mode == "origin" then
    write_matrix(p, 1, 0, 0, 1, x, y)
    topage(p)
    p.strings[#p.strings + 1] = text
    write_matrix(p, 1, 0, 0, 1, -x, -y)
  else
    write(format('Literal type %s unsupported', mode))
  end
end
local ondemandmeta = {
  __index = function(t, k)
    t[k] = {}
    return t[k]
  end
}
local function writeresources(p)
  local resources = p.resources
  local result = {"<<"}
  for kind, t in pairs(resources) do if next(t) then
    result[#result+1] = format("/%s<<", kind)
    for name, value in pairs(t) do
      result[#result+1] = format("/%s %i 0 R", name, value)
      t[name] = nil
    end
    result[#result+1] = ">>"
  end end
  result[#result+1] = ">>"
  return concat(result)
end
local fontnames = setmetatable({}, {__index = function(t, k) local res = format("F%i", k) t[k] = res return res end})
return function(file, n, fontdirs, usedglyphs, colorstacks)
  n = todirect(n)
  setmetatable(usedglyphs, ondemandmeta)
  local linkcontext = file.linkcontext
  if not linkcontext then
    linkcontext = {}
    file.linkcontext = linkcontext
  end
  local p = {
    is_page = not not colorstacks,
    file = file,
    mode = 3,
    strings = {},
    pending = {},
    pos = {},
    fontprovider = function(p, f, fid)
      if not f.parent then f.parent = pdf.getfontname(fid) end
      p.resources.Font[fontnames[f.parent]] = fontdirs[f.parent]
      p.strings[#p.strings+1] = format("/F%i %f Tf 0 Tr", f.parent, sp2bp(f.size)) -- TODO: Setting the mode, expansion, etc.
      p.usedglyphs = usedglyphs[f.parent]
    end,
    font = {},
    vfont = {},
    matrix = {1, 0, 0, 1, 0, 0},
    pending_matrix = {},
    resources = setmetatable({}, ondemandmeta),
    annots = {},
    linkcontext = file.linkcontext,
  }
  if colorstacks then
    for i=1, #colorstacks do
      local colorstack = colorstacks[i]
      if colorstack.page then
        local stack = colorstack.page_stack
        if colorstack.default ~= stack[#stack] then
          pdf.write(colorstack.mode, stack[#stack], 0, 0, p)
        end
      end
    end
  end
  nodehandler[getid(n)](p, n, 0, 0, n, nil, 0)
  -- nodehandler[getid(n)](p, n, 0, getdepth(n), n)
  topage(p)
  return concat(p.strings, '\n'), writeresources(p), (p.annots[1] and string.format("/Annots[%s]", table.concat(p.annots, ' ')) or "")
end
