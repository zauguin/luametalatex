local min = math.min
local format = string.format
local concat = table.concat
local move = table.move
local function write(pdf, tree, escaped, step)
  local nextcount = (#tree-1)//6+1
  for i=1, nextcount do
    if #tree > 6 then
      tree[i] = pdf:indirect(nil, format('<</Limits[%s %s]/Kids[%s 0 R]>>', escaped[step*(i-1)+1], escaped[step*i] or escaped[#escaped], concat(tree, ' 0 R ', 6*i-5, min(#tree, 6*i))))
    else
      return pdf:indirect(nil, format('<</Kids[%s 0 R]>>', concat(tree, ' 0 R ', 6*i-5, #tree)))
    end
  end
  move(tree, #tree+1, 2*#tree-nextcount, nextcount+1)
  return write(pdf, tree, escaped, step*6)
end

local pdf_bytestring = require'luametalatex-pdf-escape'.escape_bytes

local serialized = {}
return function(values, pdf)
  local tree = {}
  for k in next, values do
    if type(k) ~= "string" then
      error[[Invalid entry in nametree]] -- Might get ignored in a later version
    end
    tree[#tree+1] = k
  end
  table.sort(tree)
  local total = #tree
  local newtree = {}
  for i=0,(total-1)//6 do
    for j=1, 6 do
      local key = tree[6*i+j]
      if key then
        local value = values[key]
        key = pdf_bytestring(key)
        tree[6*i+j] = key
        serialized[2*j-1] = key
        serialized[2*j] = value
      else
        serialized[2*j-1], serialized[2*j] = nil, nil
      end
    end
    if total > 6 then
      newtree[i+1] = pdf:indirect(nil, format('<</Limits[%s %s]/Names[%s]>>', tree[6*i+1], tree[6*i+6] or tree[total], concat(serialized, ' ')))
    else
      return pdf:indirect(nil, format('<</Names[%s]>>', concat(serialized, ' ')))
    end
  end
  return write(pdf, newtree, tree, 36)
end
