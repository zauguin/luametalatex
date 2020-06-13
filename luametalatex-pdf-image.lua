local rawset = rawset
local setdata = node.direct.setdata
local nodenew = node.direct.new
local getwhd = node.direct.getwhd
local setwhd = node.direct.setwhd
local tonode = node.direct.tonode
local nodewrite = node.write

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
local function to_sp(bp) return bp*65781.76//1 end
local function to_bp(sp) return sp/65781.76 end

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
  img.rotation = (360 - (page.Rotate or 0)) % 360
  assert(img.rotation % 90 == 0, "Invalid /Rotate")
  img.rotation = img.rotation / 90
  if img.rotation < 0 then img.rotation = img.rotation + 4 end
  img.xsize = bbox[3] - bbox[1]
  img.ysize = bbox[4] - bbox[2]
end

local pdfe_deepcopy = require'luametalatex-pdfe-deepcopy'
local function write_pdf(pfile, img)
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
  local attr = img.attr
  if attr then
    dict = dict .. attr
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
  img.transform = img.transform or 0
  -- (Re)Set dimensions
  if img.depth and img.height and img.width then
    return img
  end
  local flipped = (img.transform + real.rotation) % 2 == 1
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

local img_by_objnum = {}
-- local function img_from_objnum(objnum, img)
  -- img = img or {}
  -- real_images[img] = assert(img_by_objnum[objnum])
  -- return setmetatable(img, restricted_meta)
-- end

-- Noop if already reserved
function reserve(pfile, real)
  local obj = real.objnum or pfile:getobj()
  real.objnum = obj
  img_by_objnum[obj] = real
  return obj
end

local function write_img(pfile, img)
  local objnum = reserve(pfile, img)
  if not img.written then
    img.written = true
    write_pdf(pfile, img)
  end
end
local function do_img(data, p, n, x, y)
  local img = assert(img_by_objnum[data >> 3], 'Invalid image ID')
  write_img(p.file, img)
  local mirror = data & 4 == 4
  local rotate = (data + img.rotation) & 3
  local width, height, depth = getwhd(n)
  height = height + depth
  local bbox = img.bbox
  local xsize, ysize = img.xsize, img.ysize
  local a, b, c, d, e, f = 1, 0, 0, 1, -bbox[1], -bbox[2]
  if mirror then
    a, e = -a, -e+xsize
  end
  for i=1,rotate do
    a, b, c, d, e, f = -b, a, -d, c, -f+ysize, e
    xsize, ysize = ysize, xsize
  end
  local xscale, yscale = width / xsize, height / ysize
  a, c, e = a*xscale, c*xscale, e*xscale
  b, d, f = b*yscale, d*yscale, f*yscale
  e, f = to_bp(x + e), to_bp(y - depth + f)
  p.resources.XObject['Im' .. tostring(img.objnum)] = img.objnum
  pdf.write('page', string.format('q %f %f %f %f %f %f cm /Im%i Do Q', a, b, c, d, e, f, img.objnum), nil, nil, p)
end
local ruleid = node.id'rule'
local ruletypes = node.subtypes'rule'
local imagerule
for n, name in next, ruletypes do
  if name == 'image' then imagerule = n break end
end
assert(imagerule)
local function node(pfile, img)
  img = scan(img)
  local n = nodenew(ruleid, imagerule) -- image
  setdata(n, (reserve(pfile, real_images[img]) << 3) | ((img.transform or 0) & 7))
  setwhd(n, img.width or -0x40000000, img.height or -0x40000000, img.depth or -0x40000000)
  return tonode(n)
end

local function write(pfile, img)
  img = scan(img)
  nodewrite(node(pfile, img))
  return img
end

local function immediatewrite(pfile, img)
  img = scan(img)
  write_img(pfile, real_images[img])
  return img
end

return {
  new = new,
  scan = scan,
  write = write,
  node = node,
  from_num = function(i)
    local img = {}
    real_images[img] = assert(img_by_objnum[i])
    return setmetatable(img, restricted_meta)
  end,
  get_num = function(pfile, img)
    return reserve(pfile, real_images[img])
  end,
  ship = do_img,
}
