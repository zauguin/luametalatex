local format = string.format
local byte = string.byte
local pack = string.pack
local error = error
local pairs = pairs
local setmetatable = setmetatable
local assigned = {}
local delayed = {}
local compress = xzip.compress
local pdfvariable = pdf.variable
-- slightly tricky interface: No/nil return means that the objects content
-- isn't known yet, while false indicates a delayed object.
local function written(pdf, num)
  num = pdf[num]
  if not num or num == assigned then return end
  return num ~= delayed
end
-- raw: Pass on preencoded stream. Currently ignored.
local function stream(pdf, num, dict, content, isfile, raw)
  if not num then num = pdf:getobj() end
  if pdf[num] ~= assigned then
    error[[Invalid object]]
  end
  pdf[num] = {offset = pdf.file:seek()}
  if isfile then
    local f = io.open(content, 'rb')
    content = f:read'a'
    f:close()
  end
  local level = not raw and pdfvariable.compresslevel or 0
  local filter = ''
  if level > 0 then
    local compressed = compress(content, level)
    if #compressed < #content + 19 then -- Filter has some overhead
      filter = "/Filter/FlateDecode"
      content = compressed
    end
  end
  pdf.file:write(format('%i 0 obj\n<<%s%s/Length %i>>stream\n', num, dict, filter, #content))
  pdf.file:write(content)
  pdf.file:write'\nendstream\nendobj\n'
  return num
end
local function delayedstream(pdf, num, dict, content, isfile, raw)
  if not num then num = pdf:getobj() end
  if pdf[num] ~= assigned then
    error[[Invalid object]]
  end
  pdf[num] = delayed
  pdf[-num] = {stream, dict, content, isfile, raw}
  return num
end
local function indirect(pdf, num, content, isfile, objstream)
  if not num then num = pdf:getobj() end
  if pdf[num] ~= assigned then
    error[[Invalid object]]
  end
  if isfile then
    local f = io.open(content, 'rb')
    content = f:read'a'
    f:close()
  end
  if objstream ~= false and pdfvariable.objcompresslevel ~= 0 then
    objstream = objstream or true
    local objstr = pdf.objstream[objstream]
    if not objstr then
      objstr = {objnum = pdf:getobj(), off = 0, {}}
      pdf.objstream[objstream] = objstr
    end
    local i = #objstr
    pdf[num] = {objstr = objstr.objnum, i = i-1}
    objstr[1][i] = string.format("%i %i ", num, objstr.off)
    objstr[i+1] = content
    objstr.off = objstr.off + #content
  else
    pdf[num] = {offset = pdf.file:seek()}
    pdf.file:write(format('%i 0 obj\n', num))
    pdf.file:write(content)
    pdf.file:write'\nendobj\n'
  end
  return num
end
local function delay(pdf, num, content, isfile)
  if not num then num = pdf:getobj() end
  if pdf[num] ~= assigned then
    error[[Invalid object]]
  end
  pdf[num] = delayed
  pdf[-num] = {indirect, content, isfile}
  return num
end
local function reference(pdf, num)
  local status = pdf[num]
  if status == delayed then
    local saved = pdf[-num]
    pdf[-num] = nil
    pdf[num] = assigned
    return saved[1](pdf, num, table.unpack(saved, 2))
  elseif status == assigned or not status then
    error[[Invalid object]]
  -- else -- Already written
  end
end
local function getid(pdf)
  local id = pdf[0] + 1
  pdf[0] = id
  pdf[id] = assigned
  return id
end
local function trailer(pdf)
  local linked = 0
  for k,objstr in next, pdf.objstream do
    objstr[1] = table.concat(objstr[1])
    pdf:stream(objstr.objnum, string.format("/Type/ObjStm/N %i/First %i", #objstr-1, #objstr[1]), table.concat(objstr))
  end
  local nextid = getid(pdf)
  local myoff = pdf.file:seek()
  pdf[nextid] = {offset = myoff}
  local offsets = {}
  for i=1,nextid do
    local off = pdf[i].offset
    if off then
      offsets[i+1] = pack(">I1I3I2", 1, off, 0)
    else
      local objstr = pdf[i].objstr
      if objstr then
        offsets[i+1] = pack(">I1I3I2", 2, objstr, pdf[i].i)
      else
        offsets[linked+1] = pack(">I1I3I2", 0, i, 255)
        linked = i
      end
    end
  end
  offsets[linked+1] = '\0\0\0\0\255\255'
  pdf[nextid] = assigned
  -- TODO: Add an /ID according to 14.4
  local info = pdf.info and string.format("/Info %i 0 R", pdf.info) or ""
  stream(pdf, nextid, format([[/Type/XRef/Size %i/W[1 3 2]/Root %i 0 R%s]], nextid+1, pdf.root, info), table.concat(offsets))
  pdf.file:write('startxref\n', myoff, '\n%%EOF')
end
local function close(pdf)
  trailer(pdf)
  local size = pdf.file:seek()
  if #pdf.version ~= 3 then
    error[[Invalid PDF version]]
  end
  pdf.file:seek('set', 5)
  pdf.file:write(pdf.version)
  pdf.file:close()
  return size
end
local pagetree = require'luametalatex-pdf-pagetree'
local pdfmeta = {
  close = close,
  getobj = getid,
  indirect = indirect,
  stream = stream,
  newpage = pagetree.newpage,
  reservepage = pagetree.reservepage,
  writepages = pagetree.write,
  delayed = delay,
  delayedstream = delayedstream,
  reference = reference,
  written = written,
}
pdfmeta.__index = pdfmeta
local function open(filename)
  local file = io.open(filename, 'wb')
  file:write"%PDF-X.X\n%\xe4\xf6\xfc\xdf\n"
  return setmetatable({file = file, version = '1.7', [0] = 0, pages = {}, objstream = {}}, pdfmeta)
end
return {
  open = open,
}
