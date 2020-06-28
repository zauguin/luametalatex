local value_values = token.values'value'
for i=0,#value_values do
  value_values[value_values[i]] = i
end
local count_code = value_values.integer
local dimen_code = value_values.dimension

local set_local = require'luametalatex-local'

local texmeta = getmetatable(tex)
local texmetaoldindex = texmeta.__index
local texmetaoldnewindex = texmeta.__newindex

local tex_variables = {}

function texmeta.__index(t, k)
  return tex_variables[k] or texmetaoldindex(t, k)
end
function texmeta.__newindex(t, k, v)
  if tex_variables[k] then
    return set_local(tex_variables, k, v)
  else
    return texmetaoldnewindex(t, k, v)
  end
end

local function tex_variable(value, scanner, name, default)
  token.luacmd(name, function(_, scanning)
    if scanning == 'value' then
      return value, tex_variables[name]
    else
      token.scan_keyword'='
      return set_local(tex_variables, name, scanner(), scanning == 'global')
    end
  end, 'global', 'protected', 'value')
  tex_variables[name] = default
end

local real_pdf_variables, pdf_variable_names = {}, {'pageresources'}
local pdf_toks = {}
local pdf_variables = setmetatable(pdf.variable, {
  __index = function(_, k)
    local v = real_pdf_variables[k]
    if v then return v end
    v = pdf_toks[k]
    if v then
      return tex.toks[v]
    end
  end,
  __newindex = function(_, k, v)
    if real_pdf_variables[k] then
      return set_local(real_pdf_variables, k, v)
    end
    local toks = pdf_toks[k]
    if toks then
      tex.toks[toks] = v
    end
  end,
})
pdf.variable_names = pdf_variable_names

local function pdf_variable(value, scanner, name, default)
  pdf_variable_names[#pdf_variable_names+1] = name
  token.luacmd('pdfvariable  ' .. name, function(_, scanning)
    if scanning == 'value' then
      return value, real_pdf_variables[name]
    else
      token.scan_keyword'='
      return set_local(real_pdf_variables, name, scanner(), scanning == 'global')
    end
  end, 'global', 'protected', 'value')
  real_pdf_variables[name] = default
end

tex_variable(count_code, token.scan_int, 'suppressfontnotfounderror', 0)
tex_variable(count_code, token.scan_int, 'outputmode', 1) -- The "traditional" default would be 0,
                                                            -- but we do not actually support that.
tex_variable(dimen_code, token.scan_dimen, 'pageheight', tex.sp'297mm')
tex_variable(dimen_code, token.scan_dimen, 'pagewidth', tex.sp'210mm')

tex_variable(count_code, token.scan_int, 'bodydirection', 0)
tex_variable(count_code, token.scan_int, 'pagedirection', 0)

pdf_variable(dimen_code, token.scan_dimen, 'horigin', tex.sp'1in')
pdf_variable(dimen_code, token.scan_dimen, 'vorigin', tex.sp'1in')
pdf_variable(dimen_code, token.scan_dimen, 'linkmargin', tex.sp'0pt')
pdf_variable(count_code, token.scan_int, 'majorversion', 1)
pdf_variable(count_code, token.scan_int, 'minorversion', 7)
pdf_variable(count_code, token.scan_int, 'compresslevel', 0)
pdf_variable(count_code, token.scan_int, 'objcompresslevel', 0) -- 0 is actually the only supported value right now, so this is basically ignored

function tex.getbodydir() return tex.bodydirection end
function tex.getpagedir() return tex.pagedirection end
function tex.setbodydir(i) tex.bodydirection = i end
function tex.setpagedir(i) tex.pagedirection = i end
local dir_regs = require 'luametalatex-dir-registers'
dir_regs 'textdir'
dir_regs 'bodydir'
dir_regs 'pagedir'
