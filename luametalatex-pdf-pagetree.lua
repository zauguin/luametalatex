local pdf = pdf
local min = math.min
local format = string.format
local concat = table.concat
local pdfvariable = pdf.variable
local function write(pfile, tree, total, max)
  tree = tree or pfile.pages
  if #tree == 0 then 
    local id = pfile:getobj()
    pfile:indirect(id, '<</Type/Pages/Kids[]/Count 0>>')
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
      local parentid = pfile:getobj()
      newtree[-(i//6)] = parentid
      parent = format("/Parent %i 0 R", parentid)
    elseif #tree <= 6 then
      parent = pdfvariable.pagesattr .. pdf.pagesattributes
    end
    pfile:indirect(id, format('<</Type/Pages%s/Kids[%s 0 R]/Count %i>>', parent, concat(tree, ' 0 R ', 6*i+1, min(#tree, 6*i+6)), min(remaining, max)))
    remaining = remaining - max
  end
  if newtree[0] then
    return write(pfile, newtree, total, max*6)
  end
  return newtree[1]
end
local function newpage(pfile)
  local pages = pfile.pages
  local pagenumber = #pages+1
  local pageid = pages.reserved and pages.reserved[pagenumber]
  if pageid then
    pages.reserved[pagenumber] = nil
  else
    pageid = pfile:getobj()
  end
  pages[pagenumber] = pageid
  if 1 == pagenumber % 6 then
    pages[-((pagenumber-1)//6)] = pfile:getobj()
  end
  return pageid, pages[-((pagenumber-1)//6)]
end
local function reservepage(pfile, num)
  local pages = pfile.pages
  if pages[num] then return pages[num] end
  local reserved = pages.reserved
  if reserved then
    if reserved[num] then return reserved[num] end
  else
    reserved = {}
    pages.reserved = reserved
  end
  reserved[num] = pfile:getobj()
  return reserved[num]
end
return {
  write = write,
  newpage = newpage,
  reservepage = reservepage,
}
