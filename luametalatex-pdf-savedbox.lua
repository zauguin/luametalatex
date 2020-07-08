local writer -- = require'luametalatex-nodewriter' -- This would introduce some cyclic dependency
local pdfvariable = pdf.variable

-- XForms currently have the form {width, height, depth, objnum, attributes, list, margin}
local xforms = {}

local utils = require'luametalatex-pdf-utils'
local strip_floats = utils.strip_floats
local to_bp = utils.to_bp

local function shipout(pfile, xform, fontdirs, usedglyphs)
  local list, margin = xform.list, xform.margin
  if not list then return xform.objnum end -- Already shipped out
  local last_page = cur_page cur_page = nil
  local out, resources, annots = writer(pfile, list, fontdirs, usedglyphs)
  cur_page = last_page
  assert(annots == '')
  if pdfvariable.xformattr ~= '' or pdfvariable.xformresources ~= '' then
    texio.write_nl('term and log', 'WARNING (savedboxresource shipout): Ignoring unsupported PDF variables xformattr and xformresources. Specify resources and attributes for specific XForms instead.')
  end
  local bbox = strip_floats(string.format('/BBox[%f %f %f %f]', -to_bp(margin), -to_bp(list.depth+margin), to_bp(list.width+margin), to_bp(list.height+margin)))
  local dict = string.format('/Subtype/Form%s/Resources%s%s', bbox, resources(xform.resources), xform.attributes or '')
  node.flush_list(list)
  xform.list = nil
  local objnum = pfile:stream(xform.objnum, dict, out)
  xform.objnum = objnum
  return objnum
end

local function save(pfile, n, attr, resources, immediate, type, margin, fontdirs, usedglyphs)
  local index = #xforms+1
  local xform = {
    list = assert(n, 'List required for saveboxresource'),
    width = n.width,
    height = n.height,
    depth = n.depth,
    attributes = attr,
    resources = resources,
    margin = margin,
    -- type = type, -- TODO: Not yet used. Do we need this at all?
  }
  xforms[index] = xform
  if immediate then
    shipout(pfile, xform, fontdirs, usedglyphs)
  end
  return index
end

local function adjust_sizes(width, height, depth, real_width, real_height, real_depth)
  if not depth then
    if height then
      local scale = height/real_height
      depth = (real_depth*scale + .5)//1
      width = width or (real_width*scale + .5)//1
    elseif width then
      local scale = width/real_width
      depth = (real_depth*scale + .5)//1
      height = (real_height*scale + .5)//1
    else
      width, height, depth = real_width, real_height, real_depth
    end
  elseif height then
    width = width or (real_width*(height+depth)/(real_height+real_depth) + .5)//1
  else
    width = width or real_width
    local scale = width/real_width
    height = ((real_depth+real_height)*scale + .5)//1 - depth
  end
  return width, height, depth
end

local ruleid = node.id'rule'
local ruletypes = node.subtypes'rule'
local boxrule
for n, name in next, ruletypes do
  if name == 'box' then boxrule = n break end
end   

local function use(index, width, height, depth)
  local xform = xforms[index]
  if not xform then return nil, nil, nil, nil end
  width, height, depth = adjust_sizes(width, height, depth, xform.width, xform.height, xform.depth)
  local n = node.direct.new(ruleid, boxrule)
  node.direct.setdata(n, index)
  node.direct.setwhd(n, width, height, depth)
  return node.direct.tonode(n), width, height, depth
end

local function do_box(data, p, n, x, y)
  local xform = assert(xforms[data], 'Invalid XForm')
  local objnum = shipout(p.file, xform, p.fontdirs, p.usedglyphs)
  local width, height, depth = node.direct.getwhd(n)
  local xscale, yscale = width / xform.width, (height+depth) / (xform.height+xform.depth)
  p.resources.XObject['Fm' .. tostring(data)] = objnum
  pdf.write('page', strip_floats(string.format('q %f 0 0 %f %f %f cm /Fm%i Do Q',
    xscale, yscale,
    to_bp(x), to_bp(y-depth+yscale*xform.depth),
    data)), nil, nil, p)
end

return {
  save = save,
  use = use,
  ship = do_box,
  init_nodewriter = function(t, nodewriter) writer, t.init_nodewriter = nodewriter, nil end,
}
