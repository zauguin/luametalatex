local min = math.min
local format = string.format
local concat = table.concat
local function write(pdf, tree, total, max)
  tree = tree or pdf.pages
  if #tree == 0 then 
    local id = pdf:getobj()
    pdf:indirect(id, '<</Type/Pages/Kids[]/Count 0>>')
    return id
  end
  max = max or 6 -- These defaults only work on the lowest level
  total = total or #tree
  local remaining = total
  -- if #tree == 1 then
  --   retur
  local newtree = {}
  local parent = ""
  for i=0,(#tree-1)//6 do
    local id = tree[-i]
    newtree[i+1] = id
    if 0 == i % 6 and #tree > 6 then
      local parentid = pdf:getobj()
      newtree[-(i//6)] = parentid
      parent = format("/Parent %i 0 R", parentid)
    end
    pdf:indirect(id, format('<</Type/Pages%s/Kids[%s 0 R]/Count %i>>', parent, concat(tree, ' 0 R ', 6*i+1, min(#tree, 6*i+6)), min(remaining, max)))
    remaining = remaining - max
  end
  if #parent > 0 then
    return write(pdf, newtree, total, max*6)
  end
  return newtree[1]
end
local function newpage(pdf)
  local pageid = pdf:getobj()
  local pagenumber = #pdf.pages
  pdf.pages[pagenumber+1] = pageid
  if 0 == pagenumber % 6 then
    pdf.pages[-(pagenumber//6)] = pdf:getobj()
  end
  return pageid, pdf.pages[-(pagenumber//6)]
end
return {
  write = write,
  newpage = newpage,
}
