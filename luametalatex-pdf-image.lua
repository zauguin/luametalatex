local rawset = rawset
local setdata = node.direct.setdata
local nodenew = node.direct.new
local getwhd = node.direct.getwhd
local setwhd = node.direct.setwhd
local tonode = node.direct.tonode
local nodewrite = node.write

-- Mapping extensions to canonical type names if necessary
local imagetype_map = {
  -- pdf1 = 'pdf',
}
local imagetypes = setmetatable({}, {__index = function(t, k)
  local remapped = imagetype_map[k]
  local module = remapped and t[remapped] or require('luametalatex-pdf-image-' .. k)
  t[k] = module
  return module
end})

-- FIXME:
local function to_sp(bp) return bp*65781.76//1 end
local function to_bp(sp) return sp/65781.76 end

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
    -- TODO: At some point we should just take the lowercased extension
    local imagetype = real.filename:match'%.pdf$' and 'pdf'
                   or real.filename:match'%.png$' and 'png'
                   or error'Unsupported image format'
    real.filepath = assert(kpse.find_file(real.filename), "Image not found")
    real.imagetype = imagetype
    imagetypes[imagetype].scan(real)
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
    local xsize, ysize = real.xsize, real.ysize
    if not real.bbox then
      local xres, yres = img.xres, img.yres
      -- TODO: \pdfvariable Parameters
      if xres == 0 then
        xres = 72
        yres = xres * ((not yres or yres == 0) and 1 or yres)
      elseif yres == 0 then
        yres = 72
        xres = yres * ((not xres or xres == 0) and 1 or xres)
      end
      local xscale, yscale = 4736286.72/xres, 4736286.72/yres
      xsize, ysize = xsize*xscale//1, ysize*yscale//1
    end
    local total_y
    if flipped then
      img.width = ysize
      total_y = xsize
    else
      img.width = xsize
      total_y = ysize
    end
    if img.height then
      img.depth = total_y - img.height
    else
      img.height = total_y - img.depth
    end
  else
    local ratio = flipped and xsize / ysize or ysize / xsize
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
    imagetypes[img.imagetype].write(pfile, img)
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
  local a, b, c, d, e, f = 1, 0, 0, 1
  if bbox then
    e, f = -bbox[1], -bbox[2]
  else
    e, f = 0, 0
    xsize, ysize = 65781.76, 65781.76
  end
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
