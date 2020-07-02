local min = math.min
local format = string.format
local concat = table.concat
local pdfvariable = pdf.variable
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
    elseif #tree <= 6 then
      parent = pdfvariable.pagesattr
    end
    pdf:indirect(id, format('<</Type/Pages%s/Kids[%s 0 R]/Count %i>>', parent, concat(tree, ' 0 R ', 6*i+1, min(#tree, 6*i+6)), min(remaining, max)))
    remaining = remaining - max
  end
  if newtree[0] then
    return write(pdf, newtree, total, max*6)
  end
  return newtree[1]
end
local function newpage(pdf)
  local pages = pdf.pages
  local pagenumber = #pages+1
  local pageid = pages.reserved and pages.reserved[pagenumber] or pdf:getobj()
  pages.reserved[pagenumber] = nil
  pages[pagenumber] = pageid
  if 1 == pagenumber % 6 then
    pages[-((pagenumber-1)//6)] = pdf:getobj()
  end
  return pageid, pages[-((pagenumber-1)//6)]
end
local function reservepage(pdf, num)
  local pages = pdf.pages
  if pages[num] then return pages[num] end
  local reserved = pages.reserved
  if reserved then
    if reserved[num] then return reserved[num] end
  else
    reserved = {}
    pages.reserved = reserved
  end
  reserved[num] = pdf:getobj()
  return reserved[num]
end
return {
  write = write,
  newpage = newpage,
  reservepage = reservepage,
}
