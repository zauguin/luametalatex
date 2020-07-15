local box_fallback = {
  BleedBox = "CropBox",
  TrimBox  = "CropBox",
  ArtBox   = "CropBox",
  CropBox  = "MediaBox",
}
  
local boxmap = {
  media = "MediaBox",
  crop  = "CropBox",
  bleed = "BleedBox",
  trim  = "TrimBox",
  art   = "ArtBox",
}

local utils = require'luametalatex-pdf-utils'
local strip_floats = utils.strip_floats
local to_sp = utils.to_sp
local to_bp = utils.to_bp

local function get_box(page, box)
  box = boxmap[box]
  while box do
    local found = pdfe.getbox(page, box)
    if found then
      return {to_sp(found[1]), to_sp(found[2]), to_sp(found[3]), to_sp(found[4])}
    end
    box = box_fallback[box]
  end
end

local pdf_functions = {}

local function open_pdfe(img, f)
  local file
  if f and f.file then
    file = pdfe.openfile(f.file)
    f.file = nil
  elseif img.filedata then
    file = pdfe.new(img.filedata, #img.filedata)
  elseif img.filepath then
    file = pdfe.open(img.filepath)
  end
  do
    local userpassword = img.userpassword
    local ownerpassword = img.ownerpassword
    if userpassword or ownerpassword then
      pdfe.unencrypt(file, userpassword, ownerpassword)
    end
  end
  local status = pdfe.getstatus(file)
  if status >= 0 then
    return file
  elseif status == -1 then
    error[[PDF image is encrypted. Please provide the decryption key.]]
  elseif status == -2 then
    error[[PDF image could not be opened.]]
  else
    assert(false)
  end
end
function pdf_functions.scan(img, f)
  local file = open_pdfe(img, f)
  img.pages = pdfe.getnofpages(file)
  img.page = img.page or 1
  if img.page > img.pages then
    error[[Not enough pages in PDF image]]
  end
  local page = pdfe.getpage(file, img.page)
  local bbox = img.bbox or get_box(page, img.pagebox or 'crop') or {0, 0, 0, 0}
  img.bbox = bbox
  img.rotation = (360 - (page.Rotate or 0)) % 360
  assert(img.rotation % 90 == 0, "Invalid /Rotate")
  img.rotation = img.rotation / 90
  if img.rotation < 0 then img.rotation = img.rotation + 4 end
  img.xsize = bbox[3] - bbox[1]
  img.ysize = bbox[4] - bbox[2]
  img.xres, img.yres = nil, nil
end

local pdfe_deepcopy = require'luametalatex-pdfe-deepcopy'
function pdf_functions.write(pfile, img)
  local file = open_pdfe(img)
  local page = pdfe.getpage(file, img.page)
  local bbox = img.bbox
  local dict = strip_floats(string.format("/Subtype/Form/BBox[%f %f %f %f]/Resources ", to_bp(bbox[1]), to_bp(bbox[2]), to_bp(bbox[3]), to_bp(bbox[4])))
  dict = dict .. pdfe_deepcopy(file, img.filepath, pfile, pdfe.getfromdictionary(page, 'Resources'))
  local content, raw = page.Contents
  -- Three cases: Contents is a stream, so copy the stream (Remember to copy filter if necessary)
  --              Contents is an array of streams, so append all the streams as a new stream
  --              Contents is missing. Then create an empty stream.
  local type = pdfe.type(content)
  if type == 'pdfe.stream' then
    raw = true
    for i=1,#content do
      local key, type, value, detail = pdfe.getfromstream(content, i)
      dict = dict .. pdfe_deepcopy(file, img.filepath, pfile, 5, key) .. ' ' .. pdfe_deepcopy(file, img.filepath, pfile, type, value, detail)
    end
    content = content(false)
  elseif type == 'pdfe.array' then
    local array = content
    content = ''
    for i=1,#array do
      content = content .. array[i](true)
    end
  else
    content = ''
  end
  local attr = img.attr
  if attr then
    dict = dict .. attr
  end
  pfile:stream(img.objnum, dict, content, nil, raw)
end

return pdf_functions
