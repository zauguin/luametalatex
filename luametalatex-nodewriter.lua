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
local getdata = direct.getdata
local getgeometry = direct.getgeometry
local getorientation = direct.getorientation

local utils = require'luametalatex-pdf-utils'
local strip_floats = utils.strip_floats
local to_bp = utils.to_bp

local make_resources = require'luametalatex-pdf-resources'
local pdf_font_map = require'luametalatex-pdf-font-deduplicate'
local get_whatsit_handler = require'luametalatex-whatsits'.handler

local write_matrix -- Defined later

local dir_id = node.id'dir'
local glue_id = node.id'glue'

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

local function projected_point(m, x, y, w)
  w = w or 1
  return x*m[1] + y*m[3] + w*m[5], x*m[2] + y*m[4] + w*m[6]
end
local fontnames = setmetatable({}, {__index = function(t, k) local res = format("F%i", k) t[k] = res return res end})
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
  if last ~= text then p.strings[#p.strings+1] = "BT" p.pos.lx, p.pos.ly, p.pos.x, p.pos.y, p.font.exfactor, p.font.extend, p.font.squeeze, p.font.slant = 0, 0, 0, 0, 0, 1, 1, 0 end

  local pdf_fid = pdf_font_map[fid]
  p.resources.Font[fontnames[pdf_fid]] = p.fontdirs[pdf_fid]
  p.strings[#p.strings+1] = strip_floats(format("/F%i %f Tf 0 Tr", pdf_fid, to_bp(f.size))) -- TODO: Setting the mode, width, etc.
  p.font.usedglyphs = p.usedglyphs[pdf_fid]

  p.font.fid = fid
  p.font.font = f
  local need_tm = false
  if p.font.extend ~= (f.extend or 1000)/1000 then
    p.font.extend = (f.extend or 1000)/1000
    need_tm = true
  end
  if p.font.squeeze ~= (f.squeeze or 1000)/1000 then
    p.font.squeeze = (f.squeeze or 1000)/1000
    need_tm = true
  end
  if p.font.slant ~= (f.slant or 0)/1000 then
    p.font.slant = (f.slant or 0)/1000
    need_tm = true
  end
  return need_tm
end
function topage(p)
  local last = p.mode
  if last == page then return end
  if last <= text then
    totext(p, p.font.fid) -- First make sure we are really in text mode
    p.strings[#p.strings+1] = "ET"
  elseif last == cm_pending then
    local pending = p.pending_matrix
    if pending[1] ~= 1 or pending[2] ~= 0 or pending[3] ~= 0 or pending[4] ~= 1 or pending[5] ~= 0 or pending[6] ~= 0 then
      p.strings[#p.strings+1] = strip_floats(format("%f %f %f %f %f %f cm", pending[1], pending[2], pending[3], pending[4], to_bp(pending[5]), to_bp(pending[6])))
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
    local xoffset = (x - p.pos.x)/p.font.font.size * 1000 / p.font.extend / (1+exfactor/1000000)
    if math.abs(xoffset) < 1000000 then -- 1000000 is arbitrary
      p.pending[#p.pending+1] = format(")%i(", math.floor(-xoffset))
      p.pos.x = x
      return
    end
  end
  if totext(p, fid) or exfactor ~= p.font.exfactor then
    p.font.exfactor = exfactor
    p.strings[#p.strings+1] = strip_floats(format("%f 0.0 %f %f %f %f Tm", p.font.extend * (1+exfactor/1000000), p.font.slant, p.font.squeeze, to_bp(x), to_bp(y)))
  else
    -- To invert the text transformation matrix (extend 0 0;slant squeeze 0;0 0 1)
    -- we have to apply (extend^-1 0 0;-slant*extend^-1*squeeze^-1 squeeze^-1 0;0 0 1). (extend has to include expansion)
    -- We optimize slightly by separating some steps
    local dx, dy = to_bp((x - p.pos.lx)), to_bp(y - p.pos.ly) / p.font.squeeze
    dx = (dx-p.font.slant*dy) / (p.font.extend * (1+exfactor/1000000))
    p.strings[#p.strings+1] = strip_floats(format("%f %f Td", dx, dy))
  end
  p.pos.lx, p.pos.ly, p.pos.x, p.pos.y = x, y, x, y
  p.mode = glyph
  p.pending[1] = "[("
end

local function boxrotation(p, list, x, y)
  local _, displaced, orientation, anchor = getgeometry(list)
  if anchor then
    error'anchors are not yet supported'
  end
  if not orientation then
    if displaced then
      local _, xoff, yoff, woff, hoff, doff = getorientation(list)
      return x + xoff, y + yoff, woff, hoff, doff
    else
      return x, y, direct.getwhd(list)
    end
  end
  local orientation, xoff, yoff, woff, hoff, doff = getorientation(list)
  x, y = x + xoff, y + yoff
  local baseorientation = orientation & 0xF
  local v_anchor = (orientation & 0xF0) >> 4
  local h_anchor = (orientation & 0xF00) >> 8
  -- assert(baseorientation & 8 == 0)
  if baseorientation & 4 == 4 then
    -- assert(baseorientation < 6)
    baseorientation, v_anchor = 0, baseorientation - 3
  end
  if baseorientation & 1 == 0 then -- horizontal
    if h_anchor == 0 then
    elseif h_anchor == 1 then
      x = x - woff
    elseif h_anchor == 2 then
      x = x + woff
    elseif h_anchor == 3 then
      x = x - woff//2
    elseif h_anchor == 4 then
      x = x + woff//2
    -- else assert(false)
    end
    local flipped = baseorientation ~= 0
    if v_anchor ~= 0 then
      local h, d = hoff, doff
      if flipped then h, d = d, h end
      if v_anchor == 1 then
        y = y + d
      elseif v_anchor == 2 then
        y = y - h
      elseif v_anchor == 3 then
        y = y + (d - h)//2
    -- else assert(false)
      end
    end
    if flipped then
      write_matrix(-1, 0, 0, -1, 2*x, 2*y, p)
      x, y = x - woff, y
    end
  else -- vertical
    if v_anchor == 0 then
    elseif v_anchor == 1 then
      y = y + woff
    elseif v_anchor == 2 then
      y = y - woff
    elseif v_anchor == 3 then
      y = y - woff//2
    -- else assert(false)
    end
    local flipped = baseorientation ~= 1
    if h_anchor ~= 0 then
      local h, d = hoff, doff
      if flipped then h, d = d, h end
      if h_anchor == 1 then
        x = x - h - d
      elseif h_anchor == 2 then
        x = x + h + d
      elseif h_anchor == 3 then
        x = x - (d + h)//2
      elseif h_anchor == 4 then
        x = x + (d + h)//2
      elseif h_anchor == 5 then
        x = x - d
      elseif h_anchor == 6 then
        x = x + h
    -- else assert(false)
      end
    end
    if flipped then
      write_matrix(0, 1, -1, 0, x+y, y-x, p)
      x, y = x, y - hoff
    else
      write_matrix(0, -1, 1, 0, x-y, x+y, p)
      x, y = x - woff, y + doff
    end
  end
  return x, y, woff, hoff, doff
end

local function endboxrotation(p, list, x, y)
  local _, displaced, orientation, anchor = getgeometry(list)
  if anchor then
    error'anchors are not yet supported'
  end
  if not orientation then return end
  local orientation, xoff, yoff, woff, hoff, doff = getorientation(list)
  local orientation = orientation & 0xF
  -- assert(orientation & 8 == 0)
  if orientation & 4 == 4 or orientation == 0 then
    -- write_matrix(1, 0, 0, 1, 0, 0, p)
  elseif orientation == 1 then
    x, y = x + woff, y - doff
    write_matrix(0, 1, -1, 0, x+y, y-x, p)
  elseif orientation == 2 then
    x = x + woff
    write_matrix(-1, 0, 0, -1, 2*x, 2*y, p)
  elseif orientation == 3 then
    y = y + hoff
    write_matrix(0, -1, 1, 0, x-y, x+y, p)
  end
end

-- Let's start with "handlers" for nodes which do not need any special handling:
local function ignore_node() end
-- The following are already handled by the list handler because they only correspond to blank space:
nodehandler.math = ignore_node
nodehandler.kern = ignore_node
-- The following are only for frontend use:
nodehandler.boundary = ignore_node
nodehandler.par = ignore_node
nodehandler.penalty = ignore_node
nodehandler.mark = ignore_node

-- Now we come to more interesting nodes:
function nodehandler.hlist(p, list, x0, y, outerlist, origin, level)
  if outerlist then
    if getid(outerlist) == 0 then
      y = y - getshift(list)
    else
      x0 = x0 + getshift(list)
    end
  end
  local width
  x0, y, width = boxrotation(p, list, x0, y)
  local x = x0
  local direction = getdirection(list)
  if direction == 1 then
    x = x + width
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
  local linkcontext = p.linkcontext
  if linkcontext and not p.linkstate then
    linkcontext:set(p, x, y, list, level+1, 'start')
  end
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
          x = x + (2*direction-1) * dim
          direction = 1-direction
        end
      end
    else
      local next = getnext(n)
      local w = next and rangedimensions(list, n, next) or rangedimensions(list, n)
      if direction == 1 then x = x - w end
      nodehandler[id](p, n, x, y, list, x0, level+1, direction)
      if direction == 0 then x = w + x end
    end
  end
  linkcontext = p.linkcontext
  if linkcontext and not p.linkstate then
    linkcontext:set(p, x, y, list, level+1, 'end')
  end
  endboxrotation(p, list, x0, y)
end
function nodehandler.vlist(p, list, x, y0, outerlist, origin, level)
  if outerlist then
    if getid(outerlist) == 0 then
      y0 = y0 - getshift(list)
    else
      x = x + getshift(list)
    end
  end
  local width, height
  x, y0, width, height = boxrotation(p, list, x, y0)
  local y = y0
  y = y + height
  for n in traverse(getlist(list)) do
    local d, h, _ = 0, getid(n) == glue_id and direct.effective_glue(n, list) or math.tointeger(getkern(n))
    if not h then
      _, h, d = direct.getwhd(n)
    end
    y = y - (h or 0)
    nodehandler[getid(n)](p, n, x, (y+.5)//1, list, y0, level+1)
    y = y - (d or 0)
  end
  endboxrotation(p, list, x, y0)
end
do
local rulesubtypes = {}
for i, n in next, node.subtypes'rule' do
  rulesubtypes[n] = i
end
local box_rule = rulesubtypes.box
local image_rule = rulesubtypes.image
local user_rule = rulesubtypes.user
local empty_rule = rulesubtypes.empty
local outline_rule = rulesubtypes.outline
local ship_img = require'luametalatex-pdf-image'.ship
local ship_box = require'luametalatex-pdf-savedbox'.ship
-- print(require'inspect'(node.subtypes('glue')))
-- print(require'inspect'(node.fields('glue')))
-- print(require'inspect'(node.fields('rule')))
-- print(require'inspect'(node.fields('whatsit')))
function nodehandler.rule(p, n, x, y, outer)
  if getwidth(n) == -1073741824 then setwidth(n, getwidth(outer)) end
  if getheight(n) == -1073741824 then setheight(n, getheight(outer)) end
  if getdepth(n) == -1073741824 then setdepth(n, getdepth(outer)) end
  local sub = getsubtype(n)
  if getwidth(n) <= 0 or getdepth(n) + getheight(n) <= 0 then return end
  if sub == box_rule then
    ship_box(getdata(n), p, n, x, y)
  elseif sub == image_rule then
    ship_img(getdata(n), p, n, x, y)
  elseif sub == empty_rule then
  elseif sub == user_rule then
    error[[We can't handle user rules yet]]
  elseif sub == outline_rule then
    error[[We can't handle outline rules yet]]
  else
    topage(p)
    p.strings[#p.strings+1] = strip_floats(format("%f %f %f %f re f", to_bp(x), to_bp(y - getdepth(n)), to_bp(getwidth(n)), to_bp(getdepth(n) + getheight(n))))
  end
end
end
-- If we encounter disc here, we can just use .replace. We could make TeX drop these using node.flatten_discretionaries,
-- but for now we just accept them. This approach might be a bit faster, but it leads to a few issue due to directions etc.
-- so it might change soon(ish) TODO: Review
function nodehandler.disc(p, n, x, y, list, ...)
  for n in traverse((getreplace(n))) do
    local next = getnext(n)
    local w = next and rangedimensions(list, n, next) or rangedimensions(list, n)
    nodehandler[getid(n)](p, n, x, y, list, ...)
    x = w + x
  end
end
local gluesubtypes = {}
for i, n in next, node.subtypes'glue' do
  gluesubtypes[n] = i
end
local  leaders_glue = gluesubtypes.leaders
local cleaders_glue = gluesubtypes.cleaders
local xleaders_glue = gluesubtypes.xleaders
local gleaders_glue = gluesubtypes.gleaders
function nodehandler.glue(p, n, x, y, outer, origin, level) -- Naturally this is an interesting one.
  local subtype = getsubtype(n)
  if subtype < leaders_glue then return end -- We only really care about leaders
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
  if subtype == leaders_glue then
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
  elseif subtype == cleaders_glue then
    local inner = w - (w // lwidth) * lwidth
    if getid(outer) == 0 then
      x = x + inner/2
    else
      y = y - inner/2
    end
  elseif subtype == xleaders_glue then
    local count = w // lwidth
    local skip = (w - count * lwidth) / (count + 1)
    if getid(outer) == 0 then
      x = x + skip
    else
      y = y - skip
    end
    lwidth = lwidth + skip
  elseif subtype == gleaders_glue then
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

local vf_state

local pdf_escape = require'luametalatex-pdf-escape'.escape_raw
local match = lpeg.match
local function do_commands(p, c, f, cid, fid, x, y, outer, x0, level, direction)
  local fonts = f.fonts
  local stack, current_font = {}, fonts and fonts[1] and fonts[1].id or fid
  for _, cmd in ipairs(c.commands) do
    if cmd[1] == "node" then
      local cmd = cmd[2]
      assert(node.type(cmd))
      cmd = todirect(cmd)
      nodehandler[getid(cmd)](p, cmd, x, y, outer, x0, level, direction)
      x = x + getwidth(cmd)
    elseif cmd[1] == "font" then
      current_font = assert(fonts[cmd[2]], "invalid font requested").id
    elseif cmd[1] == "char" then
      local n = direct.new'glyph'
      setsubtype(n, 256)
      setfont(n, current_font, cmd[2])
      nodehandler.glyph(p, n, x, y, outer, x0, level, direction)
      x = x + getwidth(n)
      direct.free(n)
    elseif cmd[1] == "slot" then
      current_font = assert(fonts[cmd[2]], "invalid font requested").id
      local n = direct.new'glyph'
      setsubtype(n, 256)
      setfont(n, current_font, cmd[3])
      nodehandler.glyph(p, n, x, y, outer, x0, level, direction)
      x = x + getwidth(n)
      direct.free(n)
    elseif cmd[1] == "rule" then
      local n = direct.new'rule'
      setheight(n, cmd[3])
      setwidth(n, cmd[2])
      nodehandler.rule(p, n, x, y, outer, x0, level, direction)
      x = x + getwidth(n)
      direct.free(n)
    elseif cmd[1] == "right" then
      x = x + cmd[2]
    elseif cmd[1] == "down" then
      y = y - cmd[2]
    elseif cmd[1] == "push" then
      stack[#stack + 1] = {x, y}
    elseif cmd[1] == "pop" then
      local top = stack[#stack]
      stack[#stack] = nil
      x, y = top[1], top[2]
    elseif cmd[1] == "special" then
      error[[specials aren't supported yet]] -- TODO
    elseif cmd[1] == "pdf" then
      local mode, literal = cmd[2], cmd[3]
      if not literal then mode, literal = "origin", mode end
      pdf.write(mode, literal, x, y, p)
    elseif cmd[1] == "lua" then
      cmd = cmd[2]
      if type(cmd) == "string" then cmd = load(cmd) end
      assert(type(cmd) == "function")
      local old_vf_state = vf_state -- This can be triggered recursivly in odd cases
      vf_state = {p, stack, current_font, x, y, outer, x0, level, direction}
      pdf._latelua(p, x, y, cmd, fid, cid)
      current_font, x, y = vf_state[3], vf_state[4], vf_state[5]
      vf_state = old_vf_state
    elseif cmd[1] == "image" then
      error[[images aren't supported yet]] -- TODO
      -- ???
    -- else
      -- NOP, comment and invalid commands ignored
    end
  end
end
-- Now we basically duplicate all of that for the `vf` library...
vf = {
  char = function(cid)
    local n = direct.new'glyph'
    setsubtype(n, 256)
    setfont(n, vf_state[3], cid)
    local x = vf_state[4]
    nodehandler.glyph(vf_state[1], n, x, vf_state[5], vf_state[6], vf_state[7], vf_state[8], vf_state[9])
    vf_state[4] = x + getwidth(n)
    direct.free(n)
  end,
  down = function(dy)
    vf_state[5] = vf_state[5] - dy
  end,
  fontid = function(fid)
    vf_state[3] = fid
  end,
  -- image = function(img) -- TODO
  node = function(n)
    local x = vf_state[4]
    nodehandler[getid(n)](vf_state[1], n, x, vf_state[5], vf_state[6], vf_state[7], vf_state[8], vf_state[9])
    vf_state[4] = x + getwidth(n)
  end,
  nop = function() end,
  pop = function()
    local stack = vf_state[2]
    local top = stack[#stack]
    stack[#stack] = nil
    vf_state[4], vf_state[5] = top[1], top[2]
  end,
  push = function()
    local stack = vf_state[2]
    stack[#stack + 1] = {vf_state[4], vf_state[5]}
  end,
  right = function(dx)
    vf_state[4] = vf_state[4] + dx
  end,
  rule = function(width, height)
    local n = direct.new'rule'
    setheight(n, height)
    setwidth(n, width)
    local x = vf_state[4]
    nodehandler.rule(vf_state[1], n, x, vf_state[5], vf_state[6], vf_state[7], vf_state[8], vf_state[9])
    vf_state[4] = x + getwidth(n)
    direct.free(n)
  end,
  special = function()
    error[[specials aren't supported yet]] -- TODO
  end,
  pdf = function(mode, literal)
    if not literal then mode, literal = "origin", mode end
    pdf.write(mode, literal, vf_state[4], vf_state[5], vf_state[1])
  end,
}
function nodehandler.glyph(p, n, x, y, outer, x0, level, direction)
  if getfont(n) ~= p.vfont.fid then
    local fid = getfont(n)
    p.vfont.fid = fid
    p.vfont.font = font.fonts[fid]
  end
  local f, fid = p.vfont.font, p.vfont.fid
  local cid = getchar(n)
  local c = f and f.characters
  c = c and c[cid]
  if not c then
    texio.write_nl(string.format("Missing character U+%04X in font %s", cid, tex.fontidentifier(fid)))
    return
  end
  local xoffset, yoffset = getoffsets(n)
  x = direction == 1 and x - xoffset or x + xoffset
  y = y + yoffset
  if c.commands then return do_commands(p, c, f, cid, fid, x, y, outer, x0, level, direction) end
  toglyph(p, getfont(n), x, y, getexpansion(n))
  local index = c.index
  if index then
    -- if f.encodingbytes == -3 then
    if false then
      if index < 0x80 then
        p.pending[#p.pending+1] = pdf_escape(string.pack('>B', index))
      elseif index < 0x7F80 then
        p.pending[#p.pending+1] = pdf_escape(string.pack('>H', index+0x7F80))
      else
        p.pending[#p.pending+1] = pdf_escape(string.pack('>BH', 0xFF, index-0x7F80))
      end
    else
      p.pending[#p.pending+1] = pdf_escape(string.pack('>H', index))
    end
    if not p.font.usedglyphs[index] then
      p.font.usedglyphs[index] = {index, math.floor(c.width * 1000 / f.size / p.font.extend + .5), c.tounicode}
    end
  else
    p.pending[#p.pending+1] = pdf_escape(string.char(getchar(n)))
    if not p.font.usedglyphs[getchar(n)] then
      p.font.usedglyphs[getchar(n)] = {getchar(n), math.floor(c.width * 1000 / f.size / p.font.extend + .5), c.tounicode}
    end
  end
  p.pos.x = p.pos.x + math.floor(getwidth(n)*(1+getexpansion(n)/1000000)+.5)
end
function nodehandler.whatsit(p, n, ...) -- Whatsit?
  local handler, prop = get_whatsit_handler(n)
  if handler then
    handler(prop, p, n, ...)
  else
    write("Invalid whatsit found (missing handler).")
  end
end
local global_p, global_x, global_y
function pdf._latelua(p, x, y, func, ...)
  global_p, global_x, global_y = p, x, y
  return func(...)
end
function write_matrix(a, b, c, d, e, f, p)
  e, f, p = e or 0, f or 0, p or global_p
  local pending = p.pending_matrix
  if p.mode ~= cm_pending then
    topage(p)
    p.mode = cm_pending
  else
    a, b = projected_point(pending, a, b, 0)
    c, d = projected_point(pending, c, d, 0)
    e, f = projected_point(pending, e, f, 1)
  end
  pending[1], pending[2], pending[3], pending[4], pending[5], pending[6] = a, b, c, d, e, f
end
pdf.write_matrix = write_matrix
local literal_type_names = { [0] =
  'origin', 'page', 'direct', 'raw', 'text'
}
function pdf.write(mode, text, x, y, p)
  x, y, p = x or global_x, y or global_y, p or global_p
  mode = literal_type_names[mode] or mode
  if mode == "page" then
    topage(p)
    p.strings[#p.strings + 1] = text
  elseif mode == "text" then
    topage(p)
    p.strings[#p.strings + 1] = text
  elseif mode == "direct" then
    if p.mode < page then
      totext(p, p.font.fid)
    elseif p.mode > page then
      topage(p)
    end
    p.strings[#p.strings + 1] = text
  elseif mode == "origin" then
    write_matrix(1, 0, 0, 1, x, y, p)
    topage(p)
    p.strings[#p.strings + 1] = text
    write_matrix(1, 0, 0, 1, -x, -y, p)
  else
    write(format('Literal type %s unsupported', mode))
  end
end
function pdf.getpos()
  return global_x, global_y
end
local ondemandmeta = {
  __index = function(t, k)
    t[k] = {}
    return t[k]
  end
}
local function nodewriter(file, n, fontdirs, usedglyphs, colorstacks, resources)
  n = todirect(n)
  resources = resources or make_resources()
  local p = {
    is_page = not not colorstacks,
    file = file,
    mode = 3,
    strings = {},
    pending = {},
    pos = {},
    font = {},
    vfont = {},
    matrix = {1, 0, 0, 1, 0, 0},
    pending_matrix = {},
    resources = resources,
    annots = {},
    linkcontext = colorstacks and file.linkcontext,
    linkstate = colorstacks and file.linkstate,
    fontdirs = fontdirs,
    usedglyphs = usedglyphs,
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
  if colorstacks then
    file.linkcontext = p.linkcontext
    file.linkstate = p.linkstate
  end
  return concat(p.strings, '\n'), resources, (p.annots[1] and string.format("/Annots[%s]", table.concat(p.annots, ' ')) or "")
end
require'luametalatex-pdf-savedbox':init_nodewriter(nodewriter)
return nodewriter
