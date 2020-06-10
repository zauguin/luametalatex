local rawset = rawset

local reserve

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

-- FIXME:
local function to_sp(bp) return bp*65536//1 end
local function to_bp(sp) return sp/65536 end

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

local function open_pdfe(img)
  local file = pdfe.open(img.filepath)
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
local function scan_pdf(img)
  local file = open_pdfe(img)
  img.imagetype = 'pdf'
  img.pages = pdfe.getnofpages(file)
  img.page = img.page or 1
  if img.page > img.pages then
    error[[Not enough pages in PDF image]]
  end
  local page = pdfe.getpage(file, img.page)
  local bbox = img.bbox or get_box(page, img.pagebox or 'crop') or {0, 0, 0, 0}
  img.bbox = bbox
  img.rotation = (page.Rotation or 0) % 360
  if img.rotation < 0 then img.rotation = img.rotation + 360 end
  if img.rotation % 2 == 0 then
    img.xsize = bbox[3] - bbox[1]
    img.ysize = bbox[4] - bbox[2]
  else
    img.xsize = bbox[4] - bbox[2]
    img.ysize = bbox[3] - bbox[1]
  end
  img.transform = img.transform or 0
end

local pdfe_deepcopy = require'luametalatex-pdfe-deepcopy'
local function write_pdf(img, pfile)
  local file = open_pdfe(img)
  local page = pdfe.getpage(file, img.page)
  local bbox = img.bbox
  local dict = string.format("/Subtype/Form/BBox[%f %f %f %f]/Resources %s", bbox[1], bbox[2], bbox[3], bbox[4], pdfe_deepcopy(file, img.filepath, pfile, pdfe.getfromdictionary(page, 'Resources')))
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
  pfile:stream(img.objnum, dict, content, nil, raw)
end

local liberal_keys = {height = true, width = true, depth = true, transform = true}
local real_images = {}
local function relaxed_newindex(t, k, v)
  if liberal_keys[k] then
    return rawset(t, k, v)
  else
    real_images[t][k] = v
  end
end
local function no_newindex(t, k, v)
  if liberal_keys[k] then
    return rawset(t, k, v)
  else
    error(string.format("You are not allowed to set %q in an already scanned image"))
  end
end
local function get_underlying(t, k)
  return assert(real_images[t])[k]
end
local meta = {__index = get_underlying, __newindex = relaxed_newindex}
local restricted_meta = {__index = get_underlying, __newindex = no_newindex}
-- transform isn't documented to be changable but it kind of fits
local function new(spec)
  local img, real = {}, {}
  real_images[img] = real
  if spec then for k,v in next, spec do
    (liberal_keys[k] and img or real)[k] = v
  end end
  img.depth = img.depth or 0
  return setmetatable(img, meta)
end
local function scan(img)
  local m = getmetatable(img)
  local real
  if m == restricted_meta then
    real = real_images[img]
  else
    if m ~= meta then img = new(img) end
    real = real_images[img]
    if real.stream then error[[stream images are not yet supported]] end
    assert(real.filename)
    if not real.filename:match'%.pdf$' then error[[Currently only PDF images are supported]] end
    real.filepath = assert(kpse.find_file(real.filename), "Image not found")
    scan_pdf(real)
    setmetatable(img, restricted_meta)
  end
  -- (Re)Set dimensions
  if img.depth and img.height and img.width then
    return img
  end
  local flipped = img.transform % 2 == 1
  if not (img.depth or img.height) then img.depth = 0 end
  if not img.width and not (img.height and img.depth) then
    local total_y
    if flipped then
      img.width = real.ysize
      total_y = real.xsize
    else
      img.width = real.xsize
      total_y = real.ysize
    end
    if img.height then
      img.depth = total_y - img.height
    else
      img.height = total_y - img.depth
    end
  else
    local ratio = flipped and real.xsize / real.ysize or real.ysize / real.xsize
    if img.width then
      if img.depth then
        img.height = (ratio * img.width - img.depth) // 1
      else
        img.depth = (ratio * img.width - img.height) // 1
      end
    else
      img.width = ((img.height + img.depth) / ratio) // 1
    end
  end
  return img
end

-- Noop if already reserved
function reserve(img, pfile)
  local real = assert(real_images[img])
  local obj = real.objnum or pfile:getobj()
  real.objnum = obj
  return img, obj
end

local function write_img(pfile, img)
  local _, objnum = reserve(img, pfile)
  local real = real_images[img]
  if not real.written then
    real.written = true
    write_pdf(real, pfile)
  end
end
local function do_img(prop, p, n, x, y, outer)
  local img = prop.img
  img.height, img.depth, img.width = prop.height, prop.depth, prop.width
  scan(img)
  write_img(p.file, img)
  local real = real_images[img]
  local total_height = img.height + img.depth
  local bbox = real.bbox
  x, y = to_bp(x - bbox[1]), to_bp(y - img.depth + bbox[2])
  p.resources.XObject['Im' .. tostring(real.objnum)] = real.objnum
  pdf.write('page', string.format('q 1 0 0 1 %f %f cm /Im%i Do Q', x, y, real.objnum), nil, nil, p)
end
local function node(img, pfile)
  pfile = pfile or pdf.__get_pfile()
  local n = _ENV.node.new('whatsit', 42) -- image
  _ENV.node.setproperty(n, {
    handle = do_img,
    img = img,
  })
  return n
end

--[[
local function write(img, immediate, pfile)
  pfile = pfile or pdf.__get_pfile()
  local _, objnum = reserve(img, pfile)
  local real = real_images[img]
end
]]

return {
  new = new,
  scan = scan,
  write = write,
  node = node,
}
