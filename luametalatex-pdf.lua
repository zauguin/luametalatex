local format = string.format
local gsub = string.gsub
local byte = string.byte
local pack = string.pack
local error = error
local pairs = pairs
local setmetatable = setmetatable
local assigned = {}
local function stream(pdf, num, dict, content)
  if not num then num = pdf:getobj() end
  if pdf[num] ~= assigned then
    error[[Invalid object]]
  end
  pdf[num] = {offset = pdf.file:seek()}
  pdf.file:write(format('%i 0 obj\n<<%s/Length %i>>stream\n', num, dict, #content))
  pdf.file:write(content)
  pdf.file:write'\nendstream\nendobj\n'
  return num
end
local function indirect(pdf, num, content)
  if not num then num = pdf:getobj() end
  if pdf[num] ~= assigned then
    error[[Invalid object]]
  end
  pdf[num] = {offset = pdf.file:seek()}
  pdf.file:write(format('%i 0 obj\n', num))
  pdf.file:write(content)
  pdf.file:write'\nendobj\n'
  return num
end
local function getid(pdf)
  local id = pdf[0] + 1
  pdf[0] = id
  pdf[id] = assigned
  return id
end
local function trailer(pdf)
  local nextid = getid(pdf)
  local myoff = pdf.file:seek()
  pdf[nextid] = {offset = myoff}
  local linked = 0
  local offsets = {}
  for i=1,nextid do
    local off = pdf[i].offset
    if off then
      offsets[i+1] = pack(">I1I3I1", 1, off, 0)
    else
      offsets[linked+1] = pack(">I1I3I1", 0, i, 255)
      linked = i
    end
  end
  offsets[linked+1] = '\0\0\0\0\255'
  pdf[nextid] = assigned
  -- TODO: Add an /ID according to 14.4
  stream(pdf, nextid, format([[/Type/XRef/Size %i/W[1 3 1]/Root %i 0 R]], nextid+1, pdf.root), table.concat(offsets))
  pdf.file:write('startxref\n', myoff, '\n%%EOF')
end
local function close(pdf)
  trailer(pdf)
  if #pdf.version ~= 3 then
    error[[Invalid PDF version]]
  end
  pdf.file:seek('set', 5)
  pdf.file:write(pdf.version)
  pdf.file:close()
end
local pagetree = require'luametalatex-pdf-pagetree'
local pdfmeta = {
  close = close,
  getobj = getid,
  indirect = indirect,
  stream = stream,
  newpage = pagetree.newpage,
  writepages = pagetree.write,
  -- delayed = delayed,
  -- delayedstream = delayedstream,
  -- reference
}
pdfmeta.__index = pdfmeta
local function open(filename)
  local file = io.open(filename, 'w')
  file:write"%PDF-X.X\n%🖋\n"
  return setmetatable({file = file, version = '1.7', [0] = 0, pages = {}}, pdfmeta)
end
return {
  open = open,
}
