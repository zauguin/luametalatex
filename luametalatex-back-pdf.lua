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
  pfile:indirect(pfile.root, string.format([[<</Type/Catalog/Version/1.7/Pages %i 0 R>>]], pfile:writepages()))
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
  error(string.format("Unknown PDF variable %s", token.scan_word()))
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
token.luacmd("pdffeedback", function()
  if token.scan_keyword"colorstackinit" then
    local page = token.scan_keyword'page'
              or (token.scan_keyword'nopage' and false) -- If you want to pass "page" as mode
    local mode = token.scan_keyword'direct' and 'direct'
              or token.scan_keyword'page' and 'page'
              or 'origin'
    local default = token.scan_string()
    tex.sprint(tostring(pdf.newcolorstack(default, mode, page)))
  else
  -- The following error message gobbles the next word as a side effect.
  -- This is intentional to make error-recovery easier.
    error(string.format("Unknown PDF feedback %s", token.scan_word()))
  end
end)
token.luacmd("pdfextension", function()
  if token.scan_keyword"colorstack" then
    write_colorstack()
  else
  -- The following error message gobbles the next word as a side effect.
  -- This is intentional to make error-recovery easier.
    error(string.format("Unknown PDF extension %s", token.scan_word()))
  end
end)
