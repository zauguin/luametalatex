local function check(buf, i, afterI)
  local checksum = 0
  while i < afterI do
    if i+60 < afterI then
      local num1, num2, num3, num4, num5, num6, num7, num8, num9, num10, num11, num12, num13, num14, num15, num16, newI = string.unpack(">I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4", buf, i)
      i = newI
      checksum = checksum + num1 + num2 + num3 + num4 + num5 + num6 + num7 + num8 + num9 + num10 + num11 + num12 + num13 + num14 + num15 + num16
    elseif i+28 < afterI then
      local num1, num2, num3, num4, num5, num6, num7, num8, newI = string.unpack(">I4I4I4I4I4I4I4I4", buf, i)
      i = newI
      checksum = checksum + num1 + num2 + num3 + num4 + num5 + num6 + num7 + num8
    elseif i+12 < afterI then
      local num1, num2, num3, num4, newI = string.unpack(">I4I4I4I4", buf, i)
      i = newI
      checksum = checksum + num1 + num2 + num3 + num4
    else
      local num
      num, i = string.unpack(">I4", buf, i)
      checksum = checksum + num
    end
  end
  return checksum & 0xFFFFFFFF
end
local function log2floor(i)
  local j = 0
  if i>>8 ~= 0 then
    j = j + 8
  end
  if i>>(j+4) ~= 0 then
    j = j + 4
  end
  if i>>(j+2) ~= 0 then
    j = j + 2
  end
  if i>>(j+1) ~= 0 then
    j = j + 1
  end
  return j
end
return {
  write = function(magic, tables)
    local tabdata = {}
    for t, val in next, tables do
      tabdata[#tabdata+1] = {t, val .. string.rep("\0", (#val+3&~3)-#val), #val}
    end
    table.sort(tabdata, function(a,b)return a[1]<b[1]end)
    local logtabs = log2floor(#tabdata)
    local tabs = {string.pack(">c4I2I2I2I2", magic, #tabdata, 1<<logtabs+4, logtabs, #tabdata-(1<<logtabs)<<4)}
    local offset = #tabs[1]+#tabdata*16
    local checksum, headindex = check(tabs[1], 1, 1+#tabs[1])
    for i=1,#tabdata do
      local tab = tabdata[i]
      local data = tab[2]
      if tab[1] == "head" then
        headindex = i+1+#tabdata
        data = data:sub(1,8) .. '\0\0\0\0' .. data:sub(13) -- Benchmarking suggests that this is faster than a LPEG version
      end
      local thischeck = check(data, 1, 1+tab[3])
      tabs[i+1] = string.pack(">c4I4I4I4", tab[1], thischeck, offset, tab[3])
      checksum = checksum + check(tabs[i+1], 1, 17) + thischeck
      offset = offset + #data
      tabs[i+1+#tabdata] = data
    end
    if headindex then
      local data = tabs[headindex]
      data = data:sub(1,8) .. string.pack(">I4", 0xB1B0AFBA-checksum&0xFFFFFFFF) .. data:sub(13) -- Benchmarking suggests that this is faster than a LPEG version
      tabs[headindex] = data
    end
    return table.concat(tabs)
  end,
  parse = function(buf, off, fontid)
    off = off or 1
    local headMagic, numTables
    headMagic, numTables, off = string.unpack(">c4I2", buf, off)
    if headMagic == "ttcf" then
      if numTables > 2 then -- numTables is actually the major version here, 1&2 are basically equal
        error[[Unsupported TTC header version]]
      end
      headMagic, numTables, off = string.unpack(">I2I4", buf, off)
      fontid = fontid or 1
      if numTables < fontid then
        error[[There aren't that many fonts in this file]]
      end
      off = string.unpack(">I4", buf, off + (fontid-1)*4)+1
      headMagic, numTables, off = string.unpack(">c4I2", buf, off)
    end
    off = off+6
    local tables = {}
    for i=1,numTables do
      local tag, check, offset, len, newOff = string.unpack(">c4I4I4I4", buf, off)
      off = newOff
      tables[tag] = {offset+1, len}
      if offset+len > #buf then
        error[[Font file too small]]
      end
    end
    return headMagic, tables
  end,
}
