local lmlt = luametalatex

local scan_int = token.scan_int
local scan_token = token.scan_token
local scan_keyword = token.scan_keyword
local scan_string = token.scan_string
local scan_word = token.scan_word
local scan_dimen = token.scan_dimen
local scan_box = token.scan_box
token.scan_list = scan_box -- They are equal if no parameter is present

local pdf = pdf
local pdfvariable = pdf.variable

local callbacks = require'luametalatex-callbacks'
local writer = require'luametalatex-nodewriter'
local newpdf = require'luametalatex-pdf'
local nametree = require'luametalatex-pdf-nametree'
local build_fontdir = require'luametalatex-pdf-font'
local prepare_node_font = require'luametalatex-pdf-font-node'.prepare
local fontmap = require'luametalatex-pdf-font-map'

local utils = require'luametalatex-pdf-utils'
local strip_floats = utils.strip_floats
local to_bp = utils.to_bp

local immediate_flag = lmlt.flag.immediate

local initex_catcodetable = 1

local pdfname, pfile
local fontdirs = setmetatable({}, {__index=function(t, k)t[k] = pfile:getobj() return t[k] end})
local nodefont_meta = {}
local usedglyphs = setmetatable({}, {__index=function(t, fid)
  local v
  if font.fonts[fid].format == 'type3node' then
    v = setmetatable({generation = 0, next_generation = 0}, nodefont_meta)
  else
    v = {}
  end
  t[fid] = v
  return v
end})
local dests = {}
local cur_page
local declare_whatsit = require'luametalatex-whatsits'.new
local whatsit_id = node.id'whatsit'
local whatsits = node.whatsits()
local colorstacks = {{
    page = true,
    mode = "direct",
    default = "0 g 0 G",
    page_stack = {"0 g 0 G"},
  }}
local spacer_cmd = token.command_id'spacer'
local output_directory = arg['output-directory']
local dir_sep = '/' -- FIXME
local function get_pfile()
  if not pfile then
    pdfname = tex.jobname .. '.pdf'
    if output_directory then
      pdfname = output_directory .. dir_sep .. pdfname
    end
    pfile = newpdf.open(pdfname)
  end
  return pfile
end
local outline
local build_outline = require'luametalatex-pdf-outline'
local function get_outline()
  if not outline then
    outline = build_outline()
  end
  return outline
end
local properties = node.direct.properties
local begin_group do
  local tokens = lmlt.primitive_tokens.begingroup
  function begin_group()
    token.put_next(tokens)
  end
end
local finalize_shipout do
  local showbox_token = lmlt.primitive_tokens.showbox
  local global_token = lmlt.primitive_tokens.global
  local deadcycles_token = lmlt.primitive_tokens.deadcycles
  local endgroup_token = lmlt.primitive_tokens.endgroup
  function finalize_shipout()
    if tex.tracingoutput > 0 then
      tex.sprint(initex_catcodetable, showbox_token, 'contentdiagnose 0')
    end
    tex.sprint(initex_catcodetable, global_token, deadcycles_token, '0', endgroup_token)
  end
end
-- LaTeX overwrites \shipout, so we try to set the expl3 alias instead if it's already defined.
-- This ensures that we do not overwrite the redefinition.
lmlt.luacmd(token.isdefined'tex_shipout:D' and 'tex_shipout:D' or 'shipout', function()
  local outlist = scan_box()
  local pfile = get_pfile()
  local total_voffset, total_hoffset = tex.voffset + pdfvariable.vorigin, tex.hoffset + pdfvariable.horigin
  local voff = node.new'kern'
  voff.kern = total_voffset
  voff.next = outlist
  voff.next.shift = total_hoffset
  local list = node.direct.tonode(node.direct.vpack(node.direct.todirect(voff)))
  local pageheight, pagewidth = tex.pageheight, tex.pagewidth
  -- In the following, the total_[hv]offset represents a symmetric offset applied on the right/bottom.
  -- The upper/left one is already included in the box dimensions
  list.height = pageheight ~= 0 and pageheight or list.height + list.depth + total_voffset
  list.width = pagewidth ~= 0 and pagewidth or list.width + total_hoffset
  local page, parent = pfile:newpage()
  cur_page = page
  local out, resources, annots = writer(pfile, list, fontdirs, usedglyphs, colorstacks)
  cur_page = nil
  local content = pfile:stream(nil, '', out)
  pfile:indirect(page, string.format([[<</Type/Page/Parent %i 0 R/Contents %i 0 R/MediaBox[0 %i %i %i]/Resources%s%s%s%s>>]], parent, content, -math.ceil(to_bp(list.depth)), math.ceil(to_bp(list.width)), math.ceil(to_bp(list.height)), resources(pdfvariable.pageresources .. pdf.pageresources), annots, pdfvariable.pageattr, pdf.pageattributes))
  tex.runlocal(begin_group)
  tex.box[0] = outlist
  list.head.next = nil
  node.free(list)
  tex.runlocal(finalize_shipout)
end, 'force', 'protected')

local infodir = ""
local namesdir = ""
local catalogdir = ""
local catalog_openaction
local creationdate = os.date("D:%Y%m%d%H%M%S")
do
  local time0 = os.time()
  local tz = os.date('%z', time0)
  if tz:match'^[+-]%d%d%d%d$' then
    if tz:sub(1) == '0000' then
      tz = 'Z'
    else
      tz = tz:sub(1,3) .. "'" .. tz:sub(4)
    end
  else
    local utc_time = os.date('!*t')
    utc_time.isdst = nil
    local time1 = os.time(utc_time)
    local offset = time1-time0
    if offset == 0 then
      tz = 'Z'
    else
      if offset > 0 then
        tz = '-'
      else
        tz = '+'
        offset = -offset
      end
      offset = offset // 60
      tz = string.format("%s%02i'%02i", tz, offset//60, offset%60)
    end
  end
  creationdate = creationdate .. tz
end
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
    additional = string.format("%s/PTEX.Fullbanner(%s)", additional, status.enginestate.banner)
  end
  return p:indirect(nil, string.format("<<%s%s>>", infodir, additional))
end

local pdf_escape = require'luametalatex-pdf-escape'
local pdf_bytestring = pdf_escape.escape_bytes
local pdf_text = pdf_escape.escape_text

local function nodefont_newindex(t, k, v)
  t.generation = t.next_generation
  return rawset(t, k, v)
end

function callbacks.stop_run()
  local user_callback = callbacks.stop_run
  if user_callback then user_callback() end

  if not pfile then
    return
  end
  do
    nodefont_meta.__newindex = nodefont_newindex -- Start recording generations
    local need_new_run = true
    while need_new_run do
      need_new_run = nil
      for fid, glyphs in pairs(usedglyphs) do
        local next_gen = glyphs.next_generation
        if next_gen and next_gen == glyphs.generation then
          glyphs.next_generation = next_gen+1
          need_new_run = true
          local f = font.getfont(fid) or font.fonts[fid]
          prepare_node_font(f, glyphs, pfile, fontdirs, usedglyphs) -- Might become fid, glyphs
        end
      end
    end
  end
  for fid, id in pairs(fontdirs) do
    local f = font.getfont(fid) or font.fonts[fid]
    local sorted = {}
    local used = usedglyphs[fid]
    used.generation, used.next_generation = nil, nil
    for k,v in pairs(usedglyphs[fid]) do
      sorted[#sorted+1] = v
    end
    table.sort(sorted, function(a,b) return a[1] < b[1] end)
    pfile:indirect(id, build_fontdir(pfile, f, sorted))
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
      texio.write_nl(string.format("Warning: Undefined destination %q", tostring(k)))
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
  if catalog_openaction then
    catalogdir = catalogdir .. '/OpenAction' .. catalog_openaction
  end
  pfile:indirect(pfile.root, string.format([[<</Type/Catalog/Version/%s/Pages %i 0 R%s>>]], pfile.version, pfile:writepages(), catalogdir))
  pfile.info = write_infodir(pfile)
  local size = pfile:close()
  texio.write_nl("term", "(see the transcript file for additional information)")
  -- TODO: Additional logging, epecially targeting the log file
  texio.write_nl("term and log", " node memory still in use:")
  -- texio.write_nl("term and log", string.format(" %d words of node memory still in use:", status.nodestate.use))
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
  texio.write_nl(string.format("Transcript written on %s.\n", status.enginestate.logfilename))
end
callbacks.__freeze('stop_run', true)

lmlt.luacmd("pdfvariable", function()
  for _, n in ipairs(pdf.variable_names) do
    if scan_keyword(n) then
      return token.put_next(token.create('pdfvariable  ' .. n))
    end
  end
  -- The following error message gobbles the next word as a side effect.
  -- This is intentional to make error-recovery easier.
  --[[
  error(string.format("Unknown PDF variable %s", scan_word()))
  ]] -- Delay the error to ensure luatex85.sty compatibility
  texio.write_nl(string.format("Unknown PDF variable %s", scan_word()))
  tex.sprint"\\unexpanded{\\undefinedpdfvariable}"
end)

local lastannot = -1
local lastlink = -1
local lastobj = -1

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
local function projected(m, x, y, w)
  w = w or 1
  return x*m[1] + y*m[3] + w*m[5], x*m[2] + y*m[4] + w*m[6]
end

local function scan_rule()
  local width, height, depth
  while true do
    if scan_keyword'width' then
      width = scan_dimen()
    elseif scan_keyword'height' then
      height = scan_dimen()
    elseif scan_keyword'depth' then
      depth = scan_dimen()
    else
      break
    end
  end
  return width, height, depth
end

local annot_whatsit = declare_whatsit('pdf_annot', function(prop, p, n, x, y, outer, _, level)
  if not prop then
    tex.error('Invalid pdf_annot whatsit', "A pdf_annot whatsit did not contain all necessary \z
        parameters. Maybe your code hasn't been adapted to LuaMetaLaTeX yet?")
    return
  end
  if not p.is_page then
    tex.error('pdf_annot outside of page', "PDF annotations are not allowed in Type3 charstrings or Form XObjects. \z
        The annotation will be ignored")
    return
  end
  -- TODO: Think about directions
  -- TODO: Think about running width
  local width = assert(prop.width, 'FIXME: Running annot width unsupported')
  local depth = prop.depth or node.direct.getdepth(outer)
  local height = prop.height or node.direct.getheight(outer)
  local margin = 0 -- TODO: Which value to use here?
  local llx, lly = x - margin, y - depth - margin
  local urx, ury = x + width + margin, y + height + margin
  p.annots[#p.annots+1] = prop.objnum .. " 0 R"
  local m = p.matrix
  local x1, y1 = projected(m, llx, lly)
  local x2, y2 = projected(m, llx, ury)
  local x3, y3 = projected(m, urx, lly)
  local x4, y4 = projected(m, urx, ury)
  x1, y1, x2, y2, x3, y3, x4, y4 = to_bp(x1), to_bp(y1), to_bp(x2), to_bp(y2), to_bp(x3), to_bp(y3), to_bp(x4), to_bp(y4)
  local minX = math.min(x1, x2, x3, x4)
  local minY = math.min(y1, y2, y3, y4)
  local maxX = math.max(x1, x2, x3, x4)
  local maxY = math.max(y1, y2, y3, y4)
  pfile:indirect(prop.objnum, string.format("<</Type/Annot/Rect[%f %f %f %f]%s>>", minX, minY, maxX, maxY, prop.data))
end)

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
    local page = assert(action.page, 'Page action must contain a page')
    local tokens = action.tokens
    if file then
      action_attr = string.format("%s/S/GoToR/D[%i %s]>>", action_attr, page-1, tokens)
    else
      local page_objnum = pfile:reservepage(page)
      action_attr = string.format("%s/S/GoTo/D[%i 0 R %s]>>", action_attr, page_objnum, tokens)
    end
  elseif action_type == 1 then -- GoTo
    local id = assert(action.id, 'GoTo action must contain an id')
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
    x1, y1, x2, y2, x3, y3, x4, y4 = to_bp(x1), to_bp(y1), to_bp(x2), to_bp(y2), to_bp(x3), to_bp(y3), to_bp(x4), to_bp(y4)
    quadStr[i//8+1] = string.format("%f %f %f %f %f %f %f %f", x1, y1, x2, y2, x3, y3, x4, y4)
    minX = math.min(minX, x1, x2, x3, x4)
    minY = math.min(minY, y1, y2, y3, y4)
    maxX = math.max(maxX, x1, x2, x3, x4)
    maxY = math.max(maxY, y1, y2, y3, y4)
  end
  local boxes = strip_floats(string.format("/Rect[%f %f %f %f]/QuadPoints[%s]", minX-.2, minY-.2, maxX+.2, maxY+.2, table.concat(quadStr, ' ')))
  pfile:indirect(link.objnum, string.format("<</Type/Annot%s%s>>", boxes, attr))
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
  if not p.is_page then return end
  for _,l in ipairs(linkcontext) do if l.level == level then
      addlinkpoint(p, l, x, y, list, level, kind)
  end end
end

local start_link_whatsit = declare_whatsit('pdf_start_link', function(prop, p, n, x, y, outer, _, level)
  if not prop then
    tex.error('Invalid pdf_start_link whatsit', "A pdf_start_link whatsit did not contain all necessary \z
        parameters. Maybe your code hasn't been adapted to LuaMetaLaTeX yet?")
    return
  end
  if not p.is_page then
    tex.error('pdf_start_link outside of page', "PDF links are not allowed in Type3 charstrings or Form XObjects. \z
        The link will be ignored")
    return
  end
  local links = p.linkcontext
  if not links then
    links = {set = linkcontext_set}
    p.linkcontext = links
  end
  local link = {quads = {}, attr = prop.link_attr, action = prop.action, level = level, force_separate = false} -- force_separate should become an option
  links[#links+1] = link
  addlinkpoint(p, link, x, y, outer, 'start')
end)
local end_link_whatsit = declare_whatsit('pdf_end_link', function(prop, p, n, x, y, outer, _, level)
  if not p.is_page then
    tex.error('pdf_start_link outside of page', "PDF links are not allowed in Type3 charstrings or Form XObjects. \z
        The link will be ignored")
    return
  end
  local links = p.linkcontext
  if not links then
    tex.error('No link here to end', "You asked me to end a link, but currently there is no link active. \z
        Maybe you forgot to run \\pdfextension startlink first?")
    return
  end
  local link = links[#links]
  if link.level ~= level then
    tex.error('Inconsistent link level', "You asked me to end a link, but the most recent link had been started at another level. \z
        I will continue with the link for now.")
    return
  end
  links[#links] = nil
  if not links[1] then p.linkcontext = nil end
  addlinkpoint(p, link, x, y, outer, 'final')
end)

local setmatrix_whatsit do
  local numberpattern = (lpeg.P'-'^-1 * lpeg.R'09'^0 * ('.' * lpeg.R'09'^0)^-1)/tonumber
  local matrixpattern = numberpattern * ' ' * numberpattern * ' ' * numberpattern * ' ' * numberpattern
  setmatrix_whatsit = declare_whatsit('pdf_setmatrix', function(prop, p, n, x, y, outer)
    if not prop then
      tex.error('Invalid pdf_setmatrix whatsit', "A pdf_setmatrix whatsit did not contain a matrix value. \z
          Maybe your code hasn't been adapted to LuaMetaLaTeX yet?")
      return
    end
    local m = p.matrix
    local a, b, c, d = matrixpattern:match(prop.data)
    if not a then
      tex.error('Invalid matrix', "The matrix in this pdf_setmatrix whatsit does not have the expected structure and could not be parsed. \z
          Did you provide enough parameters? The matrix needs exactly four decimal entries.")
      return
    end
    local e, f = (1-a)*x-c*y, (1-d)*y-b*x -- Emulate that the origin is at x, y for this transformation
                                          -- (We could also first translate by (-x, -y), then apply the matrix
                                          --  and translate back, but this is more direct)
    pdf.write_matrix(a, b, c, d, e, f, p)
    a, b = projected(m, a, b, 0)
    c, d = projected(m, c, d, 0)
    e, f = projected(m, e, f, 1)
    m[1], m[2], m[3], m[4], m[5], m[6] = a, b, c, d, e, f
  end)
end
local save_whatsit = declare_whatsit('pdf_save', function(prop, p, n, x, y, outer)
  pdf.write('page', 'q', x, y, p)
  local lastmatrix = p.matrix
  p.matrix = {[0] = lastmatrix, table.unpack(lastmatrix)}
end)
local restore_whatsit = declare_whatsit('pdf_restore', function(prop, p, n, x, y, outer)
  -- TODO: Check x, y
  pdf.write('page', 'Q', x, y, p)
  p.matrix = p.matrix[0]
end)
local dest_whatsit = declare_whatsit('pdf_dest', function(prop, p, n, x, y)
  if not prop then
    tex.error('Invalid pdf_dest whatsit', "A pdf_dest whatsit did not contain all necessary \z
        parameters. Maybe your code hasn't been adapted to LuaMetaLaTeX yet?")
  end
  assert(cur_page, "Destinations can not appear outside of a page")
  local id = prop.dest_id
  local dest_type = prop.dest_type
  local off = pdfvariable.linkmargin
  local data
  if dest_type == "xyz" then
    local x, y = projected(p.matrix, x, y)
    local zoom = prop.xyz_zoom
    if zoom then
      data = string.format("[%i 0 R/XYZ %.5f %.5f %.3f]", cur_page, to_bp(x-off), to_bp(y+off), prop.zoom/1000)
    else
      data = string.format("[%i 0 R/XYZ %.5f %.5f null]", cur_page, to_bp(x-off), to_bp(y+off))
    end
  elseif dest_type == "fitr" then
    local m = p.matrix
    local llx, lly = projected(x, x - prop.depth)
    local lrx, lry = projected(x+prop.width, x - prop.depth)
    local ulx, uly = projected(x, x + prop.height)
    local urx, ury = projected(x+prop.width, x + prop.height)
    local left, lower, right, upper = math.min(llx, lrx, ulx, urx), math.min(lly, lry, uly, ury),
                                      math.max(llx, lrx, ulx, urx), math.max(lly, lry, uly, ury)
    data = string.format("[%i 0 R/FitR %.5f %.5f %.5f %.5f]", cur_page, to_bp(left-off), to_bp(lower-off), to_bp(right+off), to_bp(upper+off))
  elseif dest_type == "fit" then
    data = string.format("[%i 0 R/Fit]", cur_page)
  elseif dest_type == "fith" then
    local x, y = projected(p.matrix, x, y)
    data = string.format("[%i 0 R/FitH %.5f]", cur_page, to_bp(y+off))
  elseif dest_type == "fitv" then
    local x, y = projected(p.matrix, x, y)
    data = string.format("[%i 0 R/FitV %.5f]", cur_page, to_bp(x-off))
  elseif dest_type == "fitb" then
    data = string.format("[%i 0 R/FitB]", cur_page)
  elseif dest_type == "fitbh" then
    local x, y = projected(p.matrix, x, y)
    data = string.format("[%i 0 R/FitBH %.5f]", cur_page, to_bp(y+off))
  elseif dest_type == "fitbv" then
    local x, y = projected(p.matrix, x, y)
    data = string.format("[%i 0 R/FitBV %.5f]", cur_page, to_bp(x-off))
  end
  if pfile:written(dests[id]) then
    texio.write_nl(string.format("Duplicate destination %q", id))
  else
    dests[id] = pfile:indirect(dests[id], strip_floats(data))
  end
end)
local refobj_whatsit = declare_whatsit('pdf_refobj', function(prop, p, n, x, y)
  if not prop then
    tex.error('Invalid pdf_refobj whatsit', "A pdf_refobj whatsit did not reference any object. \z
        Maybe your code hasn't been adapted to LuaMetaLaTeX yet?")
    return
  end
  pfile:reference(prop.obj)
end)
local literal_whatsit = declare_whatsit('pdf_literal', function(prop, p, n, x, y)
  if not prop then
    tex.error('Invalid pdf_literal whatsit', "A pdf_literal whatsit did not contain a literal to be inserted. \z
        Maybe your code hasn't been adapted to LuaMetaLaTeX yet?")
    return
  end
  pdf.write(prop.mode, prop.data, x, y, p)
end)
local colorstack_actions = {[0] =
  'set',
  'push',
  'pop',
  'current',
}
local colorstack_action_ids = {}
for i=0, #colorstack_actions do
  colorstack_action_ids[colorstack_actions[i]] = i
end
local colorstack_whatsit = declare_whatsit('pdf_colorstack', function(prop, p, n, x, y)
  if not prop then
    tex.error('Invalid pdf_colorstack whatsit', "A pdf_colorstack whatsit did not contain all necessary \z
        parameters. Maybe your code hasn't been adapted to LuaMetaLaTeX yet?")
    return
  end
  local idx = prop.colorstack or 0
  local colorstack = colorstacks[idx + 1]
  if not colorstack then
    tex.error('Undefined colorstack', "The requested colorstack is not initialized. \z
        This probably means that you forgot to run \\pdffeedback colorstackinit or \z
        that you specified the wrong index. I will continue with colorstack 0.")
    colorstack = colorstacks[1]
  end
  local stack
  if p.is_page then
    stack = colorstack.page_stack
  elseif colorstack.last_form == p.resources then
    stack = colorstack.form_stack
  else
    colorstack.last_form = p.resources
    stack = {prop.default or ''}
    colorstack.form_stack = stack
  end
  local action = prop.command
  action = colorstack_actions[action] or action
  if action == "push" then
    stack[#stack+1] = prop.data
  elseif action == "pop" then
    if #stack > 1 then
      stack[#stack] = nil
    else
      texio.write_nl('Warning (PDF): Ignoring attempt to pop empty color stack')
    end
  elseif action == "set" then
    stack[#stack] = prop.data
  elseif action ~= "current" then
    tex.error('Undefined colorstack command', "The requested colorstack command is not known. \z
        I will assume that you meant \\pdfextension colorstack current.")
  end
  pdf.write(colorstack.mode, stack[#stack], x, y, p)
end)
local link_state_whatsit = declare_whatsit('pdf_link_state', function(prop, p, n, x, y)
  if not p.is_page then return end
  local value = prop and prop.value
  if not value then
    tex.error('Invalid pdf_link_state whatsit', "A pdf_link_state whatsit did not contain all necessary \z
        parameters. Maybe your code hasn't been adapted to LuaMetaLaTeX yet?")
  end
  if value == 0 or value == 1 then
    p.linkstate = value == 1 and 1 or nil
  end
end)
local function write_colorstack()
  local idx = scan_int()
  local action = scan_keyword'pop' and 'pop'
              or scan_keyword'set' and 'set'
              or scan_keyword'current' and 'current'
              or scan_keyword'push' and 'push'
  if not action then
    tex.error('Missing action specifier for colorstack',
        "I don't know what you want to do with this colorstack. I would have expected pop/set/current or push here. \z
        I will ignore this command.")
    return
  end
  local text
  if action == "push" or "set" then
    text = scan_string()
    -- text = token.serialize(token.scan_tokenlist()) -- Attention! This should never be executed in an expand-only context
  end
  local whatsit = node.new(whatsit_id, colorstack_whatsit)
  node.setproperty(whatsit, {
      colorstack = idx,
      command = colorstack_action_ids[action],
      data = text,
    })
  node.write(whatsit)
end
local function scan_action()
  local action_type
  
  if scan_keyword'user' then
    return {action_type = 3, data = scan_string()}
  elseif scan_keyword'thread' then
    error[[FIXME: Unsupported]] -- TODO
  elseif scan_keyword'goto' then
    action_type = 1
  else
    error[[Unsupported action]]
  end
  local action = {
    action_type = action_type,
    file = scan_keyword'file' and scan_string(),
  }
  if scan_keyword'page' then
    assert(action_type == 1)
    action_type = 0
    action.action_type = 0
    local page = scan_int()
    if page <= 0 then
      error[[page must be positive in action specification]]
    end
    action.page = page
    action.tokens = scan_string()
  elseif scan_keyword'num' then
    if action.file and action_type == 1 then
      error[[num style GoTo actions must be internal]]
    end
    action.id = scan_int()
    if action.id <= 0 then
      error[[id must be positive]]
    end
  elseif scan_keyword'name' then
    action.id = scan_string()
  else
    error[[Unsupported id type]]
  end
  action.new_window = scan_keyword'newwindow' and 1
                   or scan_keyword'nonewwindow' and 2
  if action.new_window and not action.file then
    error[[newwindow is only supported for external files]]
  end
  return action
end
local function scan_literal_mode()
  return scan_keyword"direct" and "direct"
      or scan_keyword"page" and "page"
      or scan_keyword"text" and "text"
      or scan_keyword"direct" and "direct"
      or scan_keyword"raw" and "raw"
      or "origin"
end
local function maybe_gobble_cmd(cmd)
  local t = scan_token()
  if t.command ~= cmd then
    token.put_next(t)
  end
end
lmlt.luacmd("pdffeedback", function()
  if scan_keyword"colorstackinit" then
    local page = scan_keyword'page'
              or (scan_keyword'nopage' and false) -- If you want to pass "page" as mode
    local mode = scan_literal_mode()
    local default = scan_string()
    tex.sprint(tostring(pdf.newcolorstack(default, mode, page)))
  elseif scan_keyword"creationdate" then
    tex.sprint(creationdate)
  elseif scan_keyword"lastannot" then
    tex.sprint(tostring(lastannot))
  elseif scan_keyword"lastlink" then
    tex.sprint(tostring(lastlink))
  elseif scan_keyword"lastobj" then
    tex.sprint(tostring(lastobj))
  elseif scan_keyword"pageref" then
    local page = scan_int()
    if page <= 0 then
      tex.error('Invalid page number when requestiong pageref')
      tex.sprint('0')
    else
      local pfile = get_pfile()
      local pageref = pfile:reservepage(page)
      tex.sprint(tostring(pageref))
    end
  else
  -- The following error message gobbles the next word as a side effect.
  -- This is intentional to make error-recovery easier.
    error(string.format("Unknown PDF feedback %s", scan_word()))
  end
end)
lmlt.luacmd("pdfextension", function(_, immediate)
  if immediate == "value" then return end
  if immediate and immediate & ~immediate_flag ~= 0 then
    immediate = immediate & immediate_flag
    tex.error("Unexpected prefix", "You used \\pdfextension with a prefix that doesn't belong there. I will ignore it for now.")
  end
  if scan_keyword"colorstack" then
    write_colorstack()
  elseif scan_keyword"literal" then
    local mode = scan_literal_mode()
    local literal = scan_string()
    local whatsit = node.new(whatsit_id, literal_whatsit)
    node.setproperty(whatsit, {
        mode = mode,
        data = literal,
      })
    node.write(whatsit)
  elseif scan_keyword"annot" then
    local pfile = get_pfile()
    if scan_keyword"reserveobjnum" then
      lastannot = pfile:getobj()
    else
      local whatsit = node.new(whatsit_id, annot_whatsit)
      local objnum = scan_keyword'useobjnum' and scan_int() or pfile:getobj()
      lastannot = objnum
      local prop = {
        objnum = objnum,
      }
      prop.width, prop.height, prop.depth = scan_dimen()
      prop.data = scan_string()
      node.setproperty(whatsit, prop)
      node.write(whatsit)
    end
  elseif scan_keyword"startlink" then
    local pfile = get_pfile()
    local whatsit = node.new(whatsit_id, start_link_whatsit)
    local attr = scan_keyword'attr' and scan_string() or ''
    local action = scan_action()
    local objnum = pfile:getobj()
    lastlink = objnum
    node.setproperty(whatsit, {
        link_attr = attr,
        action = action,
        objnum = objnum,
      })
    node.write(whatsit)
  elseif scan_keyword"endlink" then
    local whatsit = node.new(whatsit_id, end_link_whatsit)
    node.write(whatsit)
  elseif scan_keyword"save" then
    local whatsit = node.new(whatsit_id, save_whatsit)
    node.write(whatsit)
  elseif scan_keyword"setmatrix" then
    local matrix = scan_string()
    local whatsit = node.new(whatsit_id, setmatrix_whatsit)
    node.setproperty(whatsit, {
        data = matrix,
      })
    node.write(whatsit)
  elseif scan_keyword"restore" then
    local whatsit = node.new(whatsit_id, restore_whatsit)
    node.write(whatsit)
  elseif scan_keyword"info" then
    infodir = infodir .. scan_string()
  elseif scan_keyword"catalog" then
    catalogdir = catalogdir .. ' ' .. scan_string()
    if scan_keyword'openaction' then
      if catalog_openaction then
        tex.error("Duplicate openaction", "Only one use of \\pdfextension catalog is allowed to \z
            have an openaction.")
      else
        local action = scan_action()
        catalog_openaction = get_action_attr(get_pfile(), action)
      end
    end
  elseif scan_keyword"names" then
    namesdir = namesdir .. ' ' .. scan_string()
  elseif scan_keyword"obj" then
    local pfile = get_pfile()
    if scan_keyword"reserveobjnum" then
      lastobj = pfile:getobj()
    else
      local num = scan_keyword'useobjnum' and scan_int() or pfile:getobj()
      lastobj = num
      local uncompressed = scan_keyword'uncompressed'
      local attr = scan_keyword'stream' and (scan_keyword'attr' and scan_string() or '')
      local isfile = scan_keyword'file'
      local content = scan_string()
      if immediate == immediate_flag then
        if attr then
          pfile:stream(num, attr, content, isfile, uncompressed)
        else
          pfile:indirect(num, content, isfile, not uncompressed)
        end
      else
        if attr then
          pfile:delayedstream(num, attr, content, isfile, uncompressed)
        else
          pfile:delayed(num, attr, content, isfile, not uncompressed)
        end
      end
    end
  elseif scan_keyword"refobj" then
    local num = scan_int()
    local whatsit = node.new(whatsit_id, refobj_whatsit)
    node.setproperty(whatsit, {
        obj = num,
      })
    node.write(whatsit)
  elseif scan_keyword"outline" then
    local pfile = get_pfile()
    local attr = scan_keyword'attr' and scan_string() or ''
    local action
    if scan_keyword"useobjnum" then
      action = scan_int()
    else
      local actionobj = scan_action()
      action = pfile:indirect(nil, get_action_attr(pfile, actionobj))
    end
    local outline = get_outline()
    if scan_keyword'level' then
      local level = scan_int()
      local open = scan_keyword'open'
      local title = scan_string()
      outline:add(pdf_text(title), action, level, open, attr)
    else
      local count = scan_keyword'count' and scan_int() or 0
      local title = scan_string()
      outline:add_legacy(pdf_text(title), action, count, attr)
    end
  elseif scan_keyword"dest" then
    local id
    if scan_keyword'num' then
      id = scan_int()
      if id <= 0 then
        error[[id must be positive]]
      end
    elseif scan_keyword'name' then
      id = scan_string()
    else
      error[[Unsupported id type]]
    end
    local whatsit = node.new(whatsit_id, dest_whatsit)
    local prop = {
      dest_id = id,
    }
    node.setproperty(whatsit, prop)
    if scan_keyword'xyz' then
      prop.dest_type = 'xyz'
      prop.xyz_zoom = scan_keyword'zoom' and scan_int()
      maybe_gobble_cmd(spacer_cmd)
    elseif scan_keyword'fitr' then
      prop.dest_type = 'fitr'
      maybe_gobble_cmd(spacer_cmd)
      prop.width, prop.height, prop.depth = scan_dimen()
    elseif scan_keyword'fitbh' then
      prop.dest_type = 'fitbh'
      maybe_gobble_cmd(spacer_cmd)
    elseif scan_keyword'fitbv' then
      prop.dest_type = 'fitbv'
      maybe_gobble_cmd(spacer_cmd)
    elseif scan_keyword'fitb' then
      prop.dest_type = 'fitb'
      maybe_gobble_cmd(spacer_cmd)
    elseif scan_keyword'fith' then
      prop.dest_type = 'fith'
      maybe_gobble_cmd(spacer_cmd)
    elseif scan_keyword'fitv' then
      prop.dest_type = 'fitv'
      maybe_gobble_cmd(spacer_cmd)
    elseif scan_keyword'fit' then
      prop.dest_type = 'fit'
      maybe_gobble_cmd(spacer_cmd)
    else
      error[[Unsupported dest type]]
    end
    node.write(whatsit)
  elseif scan_keyword'mapfile' then
    fontmap.mapfile(scan_string())
  elseif scan_keyword'mapline' then
    fontmap.mapline(scan_string())
  elseif scan_keyword'linkstate' then
    local value = scan_int()
    local whatsit = node.new(whatsit_id, link_state_whatsit)
    local prop = {
      value = value,
    }
    node.setproperty(whatsit, prop)
    node.write(whatsit)
  else
  -- The following error message gobbles the next word as a side effect.
  -- This is intentional to make error-recovery easier.
    error(string.format("Unknown PDF extension %s", scan_word()))
  end
end, "value")
local imglib = require'luametalatex-pdf-image'
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
lmlt.luacmd("saveimageresource", function(_, immediate)
  if immediate == "value" then return end
  if immediate and immediate & ~immediate_flag ~= 0 then
    immediate = immediate & immediate_flag
    tex.error("Unexpected prefix", "You used \\saveimageresource with a prefix that doesn't belong there. I will ignore it for now.")
  end
  local width, height, depth = scan_rule()
  local attr = scan_keyword'attr' and scan_string() or nil
  local page = scan_keyword'page' and scan_int() or nil
  local userpassword = scan_keyword'userpassword' and scan_string() or nil
  local ownerpassword = scan_keyword'ownerpassword' and scan_string() or nil
  -- local colorspace = scan_keyword'colorspace' and scan_int() or nil -- Doesn't make sense for PDF
  local pagebox = scan_keyword'mediabox' and 'media'
               or scan_keyword'cropbox' and 'crop'
               or scan_keyword'bleedbox' and 'bleed'
               or scan_keyword'trimbox' and 'trim'
               or scan_keyword'artbox' and 'art'
               or nil
  local filename = scan_string()
  local img = imglib.scan{
    attr = attr,
    page = page,
    userpassword = userpassword,
    ownerpassword = ownerpassword,
    pagebox = pagebox,
    filename = filename,
    width = width,
    height = height,
    depth = depth,
  }
  local pfile = get_pfile()
  lastimage = imglib.get_num(pfile, img)
  lastimagepages = img.pages or 1
  if immediate == immediate_flag then
    imglib_immediatewrite(pfile, img)
  end
end, "value")

lmlt.luacmd("useimageresource", function()
  local pfile = get_pfile()
  local img = assert(imglib.from_num(scan_int()))
  imglib_write(pfile, img)
end, "protected")

local integer_code = lmlt.value.integer

lmlt.luacmd("lastsavedimageresourceindex", function()
  return integer_code, lastimage
end, "value")

lmlt.luacmd("lastsavedimageresourcepages", function()
  return integer_code, lastimagepages
end, "value")

local savedbox = require'luametalatex-pdf-savedbox'
local savedbox_save = savedbox.save
function tex.saveboxresource(n, attr, resources, immediate, type, margin, pfile)
  if not node.type(n) then
    n = tonumber(n)
    if not n then
      error[[Invalid argument to saveboxresource]]
    end
    token.put_next(token.create'box', token.new(n, token.command_id'char_given'))
    n = scan_box()
  end
  margin = margin or pdfvariable.xformmargin
  return savedbox_save(pfile or get_pfile(), n, attr, resources, immediate, type, margin, fontdirs, usedglyphs)
end
tex.useboxresource = savedbox.use

local lastbox = -1

lmlt.luacmd("saveboxresource", function(_, immediate)
  if immediate == "value" then return end
  if immediate and immediate & ~immediate_flag ~= 0 then
    immediate = immediate & immediate_flag
    tex.error("Unexpected prefix", "You used \\saveboxresource with a prefix that doesn't belong there. I will ignore it for now.")
  end
  local type
  if scan_keyword'type' then
    texio.write_nl('XForm type attribute ignored')
    type = scan_int()
  end
  local attr = scan_keyword'attr' and scan_string() or nil
  local resources = scan_keyword'resources' and scan_string() or nil
  local margin = scan_keyword'margin' and scan_dimen() or nil
  local box = scan_int()

  local index = tex.saveboxresource(box, attr, resources, immediate == immediate_flag, type, margin)
  lastbox = index
end, "value")
lmlt.luacmd("useboxresource", function()
  local width, height, depth = scan_rule()
  local index = scan_int()
  node.write((tex.useboxresource(index, width, height, depth)))
end, "protected")

lmlt.luacmd("lastsavedboxresourceindex", function()
  return integer_code, lastbox
end, "value")

local saved_pos_x, saved_pos_y = -1, -1
local save_pos_whatsit = declare_whatsit('save_pos', function(_, _, _, x, y)
  saved_pos_x, saved_pos_y = assert(math.tointeger(x)), assert(math.tointeger(y))
end)
lmlt.luacmd("savepos", function() -- \savepos
  return node.direct.write(node.direct.new(whatsit_id, save_pos_whatsit))
end, "protected")

lmlt.luacmd("lastxpos", function()
  return integer_code, (saved_pos_x+.5)//1
end, "value")

lmlt.luacmd("lastypos", function()
  return integer_code, (saved_pos_y+.5)//1
end, "value")

local function pdf_register_funcs(name)
  pdf[name] = ""
  pdf['get' .. name] = function() return pdf[name] end
  pdf['set' .. name] = function(s) pdf[name] = assert(s) end
end

pdf_register_funcs'pageattributes'
pdf_register_funcs'pageresources'
pdf_register_funcs'pagesattributes'
