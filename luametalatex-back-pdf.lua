local pdf = pdf
local pdfvariable = pdf.variable
local writer = require'luametalatex-nodewriter'
local newpdf = require'luametalatex-pdf'
local nametree = require'luametalatex-pdf-nametree'
local pdfname, pfile
local fontdirs = setmetatable({}, {__index=function(t, k)t[k] = pfile:getobj() return t[k] end})
local usedglyphs = {}
local dests = {}
local cur_page
local whatsit_id = node.id'whatsit'
local whatsits = node.whatsits()
local colorstacks = {{
    page = true,
    mode = "direct",
    default = "0 g 0 G",
    page_stack = {"0 g 0 G"},
  }}
token.scan_list = token.scan_box -- They are equal if no parameter is present
local spacer_cmd = token.command_id'spacer'
local function get_pfile()
  if not pfile then
    pdfname = tex.jobname .. '.pdf'
    pfile = newpdf.open(tex.jobname .. '.pdf')
  end
  return pfile
end
local outline
local function get_outline()
  if not outline then
    outline = require'luametalatex-pdf-outline'()
  end
  return outline
end
local properties = node.direct.properties
token.luacmd("shipout", function()
  local pfile = get_pfile()
  local voff = node.new'kern'
  voff.kern = tex.voffset + pdfvariable.vorigin
  voff.next = token.scan_list()
  voff.next.shift = tex.hoffset + pdfvariable.horigin
  local list = node.direct.tonode(node.direct.vpack(node.direct.todirect(voff)))
  list.height = tex.pageheight
  list.width = tex.pagewidth
  local page, parent = pfile:newpage()
  cur_page = page
  local out, resources, annots = writer(pfile, list, fontdirs, usedglyphs, colorstacks)
  cur_page = nil
  local content = pfile:stream(nil, '', out)
  pfile:indirect(page, string.format([[<</Type/Page/Parent %i 0 R/Contents %i 0 R/MediaBox[0 %i %i %i]/Resources%s%s>>]], parent, content, -math.ceil(list.depth/65781.76), math.ceil(list.width/65781.76), math.ceil(list.height/65781.76), resources, annots))
  node.flush_list(list)
  token.put_next(token.create'immediateassignment', token.create'global', token.create'deadcycles', token.create(0x30), token.create'relax')
  token.scan_token()
end, 'force', 'protected')
local infodir = ""
local namesdir = ""
local catalogdir = ""
local creationdate = os.date("D:%Y%m%d%H%M%S%z"):gsub("+0000$", "Z"):gsub("%d%d$", "'%0")
local function write_infodir(p)
  local additional = ""
  if not string.find(infodir, "/CreationDate", 1, false) then
    additional = string.format("/CreationDate(%s)", creationdate)
  end
  if not string.find(infodir, "/ModDate", 1, false) then
    additional = string.format("%s/ModDate(%s)", additional, creationdate)
  end
  if not string.find(infodir, "/Producer", 1, false) then
    additional = string.format("%s/Producer(LuaMetaLaTeX)", additional)
  end
  if not string.find(infodir, "/Creator", 1, false) then
    additional = string.format("%s/Creator(TeX)", additional)
  end
  if not string.find(infodir, "/PTEX.Fullbanner", 1, false) then
    additional = string.format("%s/PTEX.Fullbanner(%s)", additional, status.banner)
  end
  return p:indirect(nil, string.format("<<%s%s>>", infodir, additional))
end

local pdf_escape = require'luametalatex-pdf-escape'
local pdf_bytestring = pdf_escape.escape_bytes
local pdf_text = pdf_escape.escape_text

callback.register("stop_run", function()
  if not pfile then
    return
  end
  for fid, id in pairs(fontdirs) do
    local f = font.getfont(fid) or font.fonts[fid]
    local psname = f.psname or f.fullname
    local sorted = {}
    for k,v in pairs(usedglyphs[fid]) do
    sorted[#sorted+1] = v
    end
    table.sort(sorted, function(a,b) return a[1] < b[1] end)
    pfile:indirect(id, require'luametalatex-pdf-font'(pfile, f, sorted))
  end
  pfile.root = pfile:getobj()
  pfile.version = string.format("%i.%i", pdfvariable.majorversion, pdfvariable.minorversion)
  local destnames = {}
  for k,obj in next, dests do
    if pfile:written(obj) then
      if type(k) == 'string' then
        destnames[k] = obj .. ' 0 R'
      end
    else
      texio.write_nl("Warning: Undefined destination %q", tostring(k))
    end
  end
  if next(destnames) then
    namesdir = string.format("/Dests %i 0 R%s", nametree(destnames, pfile), namesdir or '')
  end
  if namesdir then
    catalogdir = string.format("/Names<<%s>>%s", namesdir, catalogdir)
  end
  local pages = #pfile.pages
  if outline then
    catalogdir = string.format("/Outlines %i 0 R%s", outline:write(pfile), catalogdir)
  end
  pfile:indirect(pfile.root, string.format([[<</Type/Catalog/Version/%s/Pages %i 0 R%s>>]], pfile.version, pfile:writepages(), catalogdir))
  pfile.info = write_infodir(pfile)
  local size = pfile:close()
  texio.write_nl("term", "(see the transcript file for additional information)")
  -- TODO: Additional logging, epecially targeting the log file
  texio.write_nl("term and log", string.format(" %d words of node memory still in use:", status.var_used))
  local by_type, by_sub = {}, {}
  for n, id, sub in node.traverse(node.usedlist()) do
    if id == whatsit_id then
      by_sub[sub] = (by_sub[sub] or 0) + 1
    else
      by_type[id] = (by_type[id] or 0) + 1
    end
  end
  local nodestat = {}
  local types = node.types()
  for id, c in next, by_type do
    nodestat[#nodestat + 1] = string.format("%d %s", c, types[id])
  end
  for id, c in next, by_sub do
    nodestat[#nodestat + 1] = string.format("%d %s", c, whatsits[id])
  end
  texio.write_nl("  " .. table.concat(nodestat, ', '))
  texio.write_nl(string.format("Output written on %s (%d pages, %d bytes).", pdfname, pages, size))
  texio.write_nl(string.format("Transcript written on %s.\n", status.log_name))
end, "Finish PDF file")
token.luacmd("pdfvariable", function()
  for _, n in ipairs(pdf.variable_names) do
    if token.scan_keyword(n) then
      return token.put_next(token.create('pdfvariable  ' .. n))
    end
  end
  -- The following error message gobbles the next word as a side effect.
  -- This is intentional to make error-recovery easier.
  --[[
  error(string.format("Unknown PDF variable %s", token.scan_word()))
  ]] -- Delay the error to ensure luatex85.sty compatibility
  texio.write_nl(string.format("Unknown PDF variable %s", token.scan_word()))
  tex.sprint"\\unexpanded{\\undefinedpdfvariable}"
end)

local lastobj = -1
local lastannot = -1

function pdf.newcolorstack(default, mode, page)
  local idx = #colorstacks
  colorstacks[idx + 1] = {
    page = page,
    mode = mode or "origin",
    default = default,
    page_stack = {default},
  }
  return idx
end
local function sp2bp(sp)
  return sp/65781.76
end
local function projected(m, x, y, w)
  w = w or 1
  return x*m[1] + y*m[3] + w*m[5], x*m[2] + y*m[4] + w*m[6]
end

local function get_action_attr(p, action, is_link)
  local action_type = action.action_type
  if action_type == 3 then return action.data end
  local action_attr = is_link and "/Subtype/Link/A<<" or "<<"
  local file = action.file
  if file then
    action_attr = action_attr .. '/F' .. pdf_bytestring(file)
    local newwindow = action.new_window
    if newwindow and newwindow > 0 then
      action_attr = action_attr .. '/NewWindow ' .. (newwindow == 1 and 'true' or 'false')
    end
  end
  if action_type == 2 then
    error[[FIXME: Threads are currently unsupported]] -- TODO
  elseif action_type == 0 then
    error[[FIXME]]
  elseif action_type == 1 then -- GoTo
    local id = action.id
    if file then
      assert(type(id) == "string")
      action_attr = action_attr .. "/S/GoToR/D" .. pdf_bytestring(id) .. ">>"
    else
      local dest = dests[id]
      if not dest then
        dest = pfile:getobj()
        dests[id] = dest
      end
      if type(id) == "string" then
        action_attr = action_attr .. "/S/GoTo/D" .. pdf_bytestring(id) .. ">>"
      else
        action_attr = string.format("%s/S/GoTo/D %i 0 R>>", action_attr, dest)
      end
    end
  end
  return action_attr
end
local function write_link(p, link)
  local quads = link.quads
  local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
  local attr = link.attr .. get_action_attr(p, link.action, true)
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
  pfile:indirect(link.objnum, string.format("<</Type/Annot/Rect[%f %f %f %f]/QuadPoints[%s]%s>>", minX-.2, minY-.2, maxX+.2, maxY+.2, table.concat(quadStr, ' '), attr))
  for i=1,#quads do quads[i] = nil end
  link.objnum = nil
end
local function addlinkpoint(p, link, x, y, list, kind)
  local quads = link.quads
  local off = pdfvariable.linkmargin
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
  local lx, ly = projected(m, x, y-off-(link.depth or node.direct.getdepth(list)))
  local ux, uy = projected(m, x, y+off+(link.height or node.direct.getheight(list)))
  local n = #quads
  quads[n+1], quads[n+2], quads[n+3], quads[n+4] = lx, ly, ux, uy
  if kind == 'final' or (link.force_separate and (n+4)%8 == 0) then
    write_link(p, link)
    link.annots = nil
  end
end
local function linkcontext_set(linkcontext, p, x, y, list, level, kind)
  for _,l in ipairs(linkcontext) do if l.level == level then
      addlinkpoint(p, l, x, y, list, level, kind)
  end end
end

function do_start_link(prop, p, n, x, y, outer, _, level)
  local links = p.linkcontext
  if not links then
    links = {set = linkcontext_set}
    p.linkcontext = links
  end
  local link = {quads = {}, attr = prop.link_attr, action = prop.action, level = level, force_separate = false} -- force_separate should become an option
  links[#links+1] = link
  addlinkpoint(p, link, x, y, outer, 'start')
end
function do_end_link(prop, p, n, x, y, outer, _, level)
  local links = p.linkcontext
  if not links then error"No link here to end" end
  local link = links[#links]
  links[#links] = nil
  if link.level ~= level then error"Wrong link level" end
  addlinkpoint(p, link, x, y, outer, 'final')
end

local do_setmatrix do
  local numberpattern = (lpeg.P'-'^-1 * lpeg.R'09'^0 * ('.' * lpeg.R'09'^0)^-1)/tonumber
  local matrixpattern = numberpattern * ' ' * numberpattern * ' ' * numberpattern * ' ' * numberpattern
  function do_setmatrix(prop, p, n, x, y, outer)
    local m = p.matrix
    local a, b, c, d = matrixpattern:match(prop.data)
    if not a then
      print(prop.data)
      error[[No valid matrix found]]
    end
    local e, f = (1-a)*x-c*y, (1-d)*y-b*x -- Emulate that the origin is at x, y for this transformation
                                          -- (We could also first translate by (-x, -y), then apply the matrix
                                          --  and translate back, but this is more direct)
    pdf.write_matrix(a, b, c, d, e, f, p)
    a, b = projected(m, a, b, 0)
    c, d = projected(m, c, d, 0)
    e, f = projected(m, e, f, 1)
    m[1], m[2], m[3], m[4], m[5], m[6] = a, b, c, d, e, f
  end
end
local function do_save(prop, p, n, x, y, outer)
  pdf.write('page', 'q', x, y, p)
  local lastmatrix = p.matrix
  p.matrix = {[0] = lastmatrix, table.unpack(lastmatrix)}
end
local function do_restore(prop, p, n, x, y, outer)
  -- TODO: Check x, y
  pdf.write('page', 'Q', x, y, p)
  p.matrix = p.matrix[0]
end
local function do_dest(prop, p, n, x, y)
  assert(cur_page, "Destinations can not appear outside of a page")
  local id = prop.dest_id
  local dest_type = prop.dest_type
  local data
  if dest_type == "xyz" then
    local x, y = projected(p.matrix, x, y)
    local zoom = prop.xyz_zoom
    if zoom then
      data = string.format("[%i 0 R/XYZ %.5f %.5f %.3f]", cur_page, sp2bp(x), sp2bp(y), prop.zoom/1000)
    else
      data = string.format("[%i 0 R/XYZ %.5f %.5f null]", cur_page, sp2bp(x), sp2bp(y))
    end
  elseif dest_type == "fitr" then
    local m = p.matrix
    local llx, lly = projected(x, x - prop.depth)
    local lrx, lry = projected(x+prop.width, x - prop.depth)
    local ulx, uly = projected(x, x + prop.height)
    local urx, ury = projected(x+prop.width, x + prop.height)
    local left, lower, right, upper = math.min(llx, lrx, ulx, urx), math.min(lly, lry, uly, ury),
                                      math.max(llx, lrx, ulx, urx), math.max(lly, lry, uly, ury)
    data = string.format("[%i 0 R/FitR %.5f %.5f %.5f %.5f]", cur_page, sp2bp(left), sp2bp(lower), sp2bp(right), sp2bp(upper))
  elseif dest_type == "fit" then
    data = string.format("[%i 0 R/Fit]", cur_page)
  elseif dest_type == "fith" then
    local x, y = projected(p.matrix, x, y)
    data = string.format("[%i 0 R/FitH %.5f]", cur_page, sp2bp(y))
  elseif dest_type == "fitv" then
    local x, y = projected(p.matrix, x, y)
    data = string.format("[%i 0 R/FitV %.5f]", cur_page, sp2bp(x))
  elseif dest_type == "fitb" then
    data = string.format("[%i 0 R/FitB]", cur_page)
  elseif dest_type == "fitbh" then
    local x, y = projected(p.matrix, x, y)
    data = string.format("[%i 0 R/FitBH %.5f]", cur_page, sp2bp(y))
  elseif dest_type == "fitbv" then
    local x, y = projected(p.matrix, x, y)
    data = string.format("[%i 0 R/FitBV %.5f]", cur_page, sp2bp(x))
  end
  if pfile:written(dests[id]) then
    texio.write_nl(string.format("Duplicate destination %q", id))
  else
    dests[id] = pfile:indirect(dests[id], data)
  end
end
local function do_refobj(prop, p, n, x, y)
  pfile:reference(prop.obj)
end
local function do_literal(prop, p, n, x, y)
  pdf.write(prop.mode, prop.data, x, y, p)
end
local function do_colorstack(prop, p, n, x, y)
  local colorstack = prop.colorstack
  local stack
  if p.is_page then
    stack = colorstack.page_stack
  elseif prop.last_form == resources then
    stack = colorstack.form_stack
  else
    stack = {prop.default}
    colorstack.form_stack = stack
  end
  if prop.action == "push" then
    stack[#stack+1] = prop.data
  elseif prop.action == "pop" then
    assert(#stack > 1)
    stack[#stack] = nil
  elseif prop.action == "set" then
    stack[#stack] = prop.data
  end
  pdf.write(colorstack.mode, stack[#stack], x, y, p)
end
local function write_colorstack()
  local idx = token.scan_int()
  local colorstack = colorstacks[idx + 1]
  if not colorstack then
    error[[Undefined colorstack]]
  end
  local action = token.scan_keyword'pop' and 'pop'
              or token.scan_keyword'set' and 'set'
              or token.scan_keyword'current' and 'current'
              or token.scan_keyword'push' and 'push'
  if not action then
    error[[Missing action specifier for colorstack command]]
  end
  local text
  if action == "push" or "set" then
    text = token.scan_string()
    -- text = token.to_string(token.scan_tokenlist()) -- Attention! This should never be executed in an expand-only context
  end
  local whatsit = node.new(whatsit_id, whatsits.pdf_colorstack)
  node.setproperty(whatsit, {
      handle = do_colorstack,
      colorstack = colorstack,
      action = action,
      data = text,
    })
  node.write(whatsit)
end
local function scan_action()
  local action_type
  
  if token.scan_keyword'user' then
    return {action_type = 3, data = token.scan_string()}
  elseif token.scan_keyword'thread' then
    error[[FIXME: Unsupported]] -- TODO
  elseif token.scan_keyword'goto' then
    action_type = 1
  else
    error[[Unsupported action]]
  end
  local action = {
    action_type = action_type,
    file = token.scan_keyword'file' and token.scan_string(),
  }
  if token.scan_keyword'page' then
    error[[TODO]]
  elseif token.scan_keyword'num' then
    if action.file and action_type == 3 then
      error[[num style GoTo actions must be internal]]
    end
    action.id = token.scan_int()
    if action.id <= 0 then
      error[[id must be positive]]
    end
  elseif token.scan_keyword'name' then
    action.id = token.scan_string()
  else
    error[[Unsupported id type]]
  end
  action.new_window = token.scan_keyword'newwindow' and 1
                   or token.scan_keyword'nonewwindow' and 2
  if action.new_window and not action.file then
    error[[newwindow is only supported for external files]]
  end
  return action
end
local function scan_literal_mode()
  return token.scan_keyword"direct" and "direct"
      or token.scan_keyword"page" and "page"
      or token.scan_keyword"text" and "text"
      or token.scan_keyword"direct" and "direct"
      or token.scan_keyword"raw" and "raw"
      or "origin"
end
local function maybe_gobble_cmd(cmd)
  local t = token.scan_token()
  if t.command ~= cmd then
    token.put_next(t)
  end
end
token.luacmd("pdffeedback", function()
  if token.scan_keyword"colorstackinit" then
    local page = token.scan_keyword'page'
              or (token.scan_keyword'nopage' and false) -- If you want to pass "page" as mode
    local mode = scan_literal_mode()
    local default = token.scan_string()
    tex.sprint(tostring(pdf.newcolorstack(default, mode, page)))
  elseif token.scan_keyword"creationdate" then
    tex.sprint(creationdate)
  elseif token.scan_keyword"lastannot" then
    tex.sprint(tostring(lastannot))
  elseif token.scan_keyword"lastobj" then
    tex.sprint(tostring(lastobj))
  else
  -- The following error message gobbles the next word as a side effect.
  -- This is intentional to make error-recovery easier.
    error(string.format("Unknown PDF feedback %s", token.scan_word()))
  end
end)
token.luacmd("pdfextension", function(_, imm)
  if token.scan_keyword"colorstack" then
    write_colorstack()
  elseif token.scan_keyword"literal" then
    local mode = scan_literal_mode()
    local literal = token.scan_string()
    local whatsit = node.new(whatsit_id, whatsits.pdf_literal)
    node.setproperty(whatsit, {
        handle = do_literal,
        mode = mode,
        data = literal,
      })
    node.write(whatsit)
  elseif token.scan_keyword"startlink" then
    local pfile = get_pfile()
    local whatsit = node.new(whatsit_id, whatsits.pdf_start_link)
    local attr = token.scan_keyword'attr' and token.scan_string() or ''
    local action = scan_action()
    local objnum = pfile:getobj()
    lastannot = num
    node.setproperty(whatsit, {
        handle = do_start_link,
        link_attr = attr,
        action = action,
        objnum = objnum,
      })
    node.write(whatsit)
  elseif token.scan_keyword"endlink" then
    local whatsit = node.new(whatsit_id, whatsits.pdf_end_link)
    node.setproperty(whatsit, {
        handle = do_end_link,
      })
    node.write(whatsit)
  elseif token.scan_keyword"save" then
    local whatsit = node.new(whatsit_id, whatsits.pdf_save)
    node.setproperty(whatsit, {
        handle = do_save,
      })
    node.write(whatsit)
  elseif token.scan_keyword"setmatrix" then
    local matrix = token.scan_string()
    local whatsit = node.new(whatsit_id, whatsits.pdf_setmatrix)
    node.setproperty(whatsit, {
        handle = do_setmatrix,
        data = matrix,
      })
    node.write(whatsit)
  elseif token.scan_keyword"restore" then
    local whatsit = node.new(whatsit_id, whatsits.pdf_restore)
    node.setproperty(whatsit, {
        handle = do_restore,
      })
    node.write(whatsit)
  elseif token.scan_keyword"info" then
    infodir = infodir .. token.scan_string()
  elseif token.scan_keyword"catalog" then
    catalogdir = catalogdir .. ' ' .. token.scan_string()
  elseif token.scan_keyword"names" then
    namesdir = namesdir .. ' ' .. token.scan_string()
  elseif token.scan_keyword"obj" then
    local pfile = get_pfile()
    if token.scan_keyword"reserveobjnum" then
      lastobj = pfile:getobj()
    else
      local num = token.scan_keyword'useobjnum' and token.scan_int() or pfile:getobj()
      lastobj = num
      local attr = token.scan_keyword'stream' and (token.scan_keyword'attr' and token.scan_string() or '')
      local isfile = token.scan_keyword'file'
      local content = token.scan_string()
      if immediate then
        if attr then
          pfile:stream(num, attr, content, isfile)
        else
          pfile:indirect(num, content, isfile)
        end
      else
        if attr then
          pfile:delayedstream(num, attr, content, isfile)
        else
          pfile:delayed(num, attr, content, isfile)
        end
      end
    end
  elseif token.scan_keyword"refobj" then
    local num = token.scan_int()
    local whatsit = node.new(whatsit_id, whatsits.pdf_refobj)
    node.setproperty(whatsit, {
        obj = num,
        handle = do_refobj,
      })
    node.write(whatsit)
  elseif token.scan_keyword"outline" then
    local pfile = get_pfile()
    local attr = token.scan_keyword'attr' and token.scan_string() or ''
    local action
    if token.scan_keyword"useobjnum" then
      action = token.scan_int()
    else
      local actionobj = scan_action()
      action = pfile:indirect(nil, get_action_attr(pfile, actionobj))
    end
    local outline = get_outline()
    if token.scan_keyword'level' then
      local level = token.scan_int()
      local open = token.scan_keyword'open'
      local title = token.scan_string()
      outline:add(pdf_text(title), action, level, open, attr)
    else
      local count = token.scan_keyword'count' and token.scan_int() or 0
      local title = token.scan_string()
      outline:add_legacy(pdf_text(title), action, count, attr)
    end
  elseif token.scan_keyword"dest" then
    local id
    if token.scan_keyword'num' then
      id = token.scan_int()
      if id <= 0 then
        error[[id must be positive]]
      end
    elseif token.scan_keyword'name' then
      id = token.scan_string()
    else
      error[[Unsupported id type]]
    end
    local whatsit = node.new(whatsit_id, whatsits.pdf_dest)
    local prop = {
      dest_id = id,
      handle = do_dest,
    }
    node.setproperty(whatsit, prop)
    if token.scan_keyword'xyz' then
      prop.dest_type = 'xyz'
      prop.xyz_zoom = token.scan_keyword'zoom' and token.scan_int()
      maybe_gobble_cmd(spacer_cmd)
    elseif token.scan_keyword'fitr' then
      prop.dest_type = 'fitr'
      maybe_gobble_cmd(spacer_cmd)
      while true do
        if token.scan_keyword'width' then
          prop.width = token.scan_dimen()
        elseif token.scan_keyword'height' then
          prop.height = token.scan_dimen()
        elseif token.scan_keyword'depth' then
          prop.depth = token.scan_dimen()
        else
          break
        end
      end
    elseif token.scan_keyword'fitbh' then
      prop.dest_type = 'fitbh'
      maybe_gobble_cmd(spacer_cmd)
    elseif token.scan_keyword'fitbv' then
      prop.dest_type = 'fitbv'
      maybe_gobble_cmd(spacer_cmd)
    elseif token.scan_keyword'fitb' then
      prop.dest_type = 'fitb'
      maybe_gobble_cmd(spacer_cmd)
    elseif token.scan_keyword'fith' then
      prop.dest_type = 'fith'
      maybe_gobble_cmd(spacer_cmd)
    elseif token.scan_keyword'fitv' then
      prop.dest_type = 'fitv'
      maybe_gobble_cmd(spacer_cmd)
    elseif token.scan_keyword'fit' then
      prop.dest_type = 'fit'
      maybe_gobble_cmd(spacer_cmd)
    else
      error[[Unsupported dest type]]
    end
    node.write(whatsit)
  else
  -- The following error message gobbles the next word as a side effect.
  -- This is intentional to make error-recovery easier.
    error(string.format("Unknown PDF extension %s", token.scan_word()))
  end
end, "protected")
imglib = require'luametalatex-pdf-image'
local imglib_node = imglib.node
local imglib_write = imglib.write
local imglib_immediatewrite = imglib.immediatewrite
img = {
  new = imglib.new,
  scan = imglib.scan,
  node = function(img, pfile) return imglib_node(pfile or get_pfile(), img) end,
  write = function(img, pfile) return imglib_write(pfile or get_pfile(), img) end,
  immediatewrite = function(img, pfile) return imglib_immediatewrite(pfile or get_pfile(), img) end,
}

local lastimage = -1
local lastimagepages = -1

-- These are very minimal right now but LaTeX isn't using the scaling etc. stuff anyway.
token.luacmd("saveimageresource", function(imm)
  local attr = token.scan_keyword'attr' and token.scan_string() or nil
  local page = token.scan_keyword'page' and token.scan_int() or nil
  local userpassword = token.scan_keyword'userpassword' and token.scan_string() or nil
  local ownerpassword = token.scan_keyword'ownerpassword' and token.scan_string() or nil
  -- local colorspace = token.scan_keyword'colorspace' and token.scan_int() or nil -- Doesn't make sense for PDF
  local pagebox = token.scan_keyword'mediabox' and 'media'
               or token.scan_keyword'cropbox' and 'crop'
               or token.scan_keyword'bleedbox' and 'bleed'
               or token.scan_keyword'trimbox' and 'trim'
               or token.scan_keyword'artbox' and 'art'
               or nil
  local filename = token.scan_string()
  local img = imglib.scan{
    attr = attr,
    page = page,
    userpassword = userpassword,
    ownerpassword = ownerpassword,
    pagebox = pagebox,
    filename = filename,
  }
  local pfile = get_pfile()
  lastimage = imglib.get_num(pfile, img)
  lastimagepages = img.pages or 1
  if imm == 'immediate' then
    imglib_immediatewrite(pfile, img)
  end
end, "protected")

token.luacmd("useimageresource", function()
  local pfile = get_pfile()
  local img = assert(imglib.from_num(token.scan_int()))
  imglib_write(pfile, img)
end, "protected")

local value_values = token.values'value'
for i=0,#value_values do
  value_values[value_values[i]] = i
end
local integer_code = value_values.integer

token.luacmd("lastsavedimageresourceindex", function()
  return integer_code, lastimage
end, "protected", "value")

token.luacmd("lastsavedimageresourcepages", function()
  return integer_code, lastimagepages
end, "protected", "value")
