local pdf = pdf
local writer = require'luametalatex-nodewriter'
local newpdf = require'luametalatex-pdf'
local pfile = newpdf.open(tex.jobname .. '.pdf')
local fontdirs = setmetatable({}, {__index=function(t, k)t[k] = pfile:getobj() return t[k] end})
local usedglyphs = {}
local colorstacks = {{
    page = true,
    mode = "direct",
    default = "0 g 0 G",
    page_stack = {"0 g 0 G"},
  }}
token.luacmd("shipout", function()
  local voff = node.new'kern'
  voff.kern = tex.voffset + pdf.variable.vorigin
  voff.next = token.scan_list()
  voff.next.shift = tex.hoffset + pdf.variable.horigin
  local list = node.vpack(voff)
  list.height = tex.pageheight
  list.width = tex.pagewidth
  local out, resources, annots = writer(pfile, list, fontdirs, usedglyphs, colorstacks)
  local page, parent = pfile:newpage()
  local content = pfile:stream(nil, '', out)
  pfile:indirect(page, string.format([[<</Type/Page/Parent %i 0 R/Contents %i 0 R/MediaBox[0 %i %i %i]/Resources%s%s>>]], parent, content, -math.ceil(list.depth/65781.76), math.ceil(list.width/65781.76), math.ceil(list.height/65781.76), resources, annots))
  token.put_next(token.create'immediateassignment', token.create'global', token.create'deadcycles', token.create(0x30), token.create'relax')
  token.scan_token()
end, 'protected')
local infodir = ""
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
callback.register("stop_run", function()
  for fid, id in pairs(fontdirs) do
    local f = font.getfont(fid)
    local psname = f.psname or f.fullname
    local sorted = {}
    for k,v in pairs(usedglyphs[fid]) do
    sorted[#sorted+1] = v
    end
    table.sort(sorted, function(a,b) return a[1] < b[1] end)
    pfile:indirect(id, require'luametalatex-pdf-font'(pfile, f, sorted))
  end
  pfile.root = pfile:getobj()
  pfile.version = string.format("%i.%i", pdf.variable.majorversion, pdf.variable.minorversion)
  pfile:indirect(pfile.root, string.format([[<</Type/Catalog/Version/%i.%i/Pages %i 0 R>>]], pfile.version, pfile:writepages()))
  pfile.info = write_infodir(pfile)
  pfile:close()
end, "Finish PDF file")
token.luacmd("pdfvariable", function()
  for n, t in pairs(pdf.variable_tokens) do
    if token.scan_keyword(n) then
      token.put_next(t)
      return
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
local whatsit_id = node.id'whatsit'
local whatsits = node.whatsits()
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
local function scan_literal_mode()
  return token.scan_keyword"direct" and "direct"
      or token.scan_keyword"page" and "page"
      or token.scan_keyword"text" and "text"
      or token.scan_keyword"direct" and "direct"
      or token.scan_keyword"raw" and "raw"
      or "origin"
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
  else
  -- The following error message gobbles the next word as a side effect.
  -- This is intentional to make error-recovery easier.
    error(string.format("Unknown PDF feedback %s", token.scan_word()))
  end
end)
token.luacmd("pdfextension", function()
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
  elseif token.scan_keyword"info" then
    infodir = infodir .. token.scan_string()
  else
  -- The following error message gobbles the next word as a side effect.
  -- This is intentional to make error-recovery easier.
    error(string.format("Unknown PDF extension %s", token.scan_word()))
  end
end, "protected")
