local purenumber = lpeg.R'09'^1
local optoperator = lpeg.C(lpeg.S'+-='^-1)*lpeg.C(lpeg.P(1)^0)
local commentchar = lpeg.S' %*;#'+-1
local wordpatt = (lpeg.C('"') * lpeg.C((1-lpeg.P'"')^0) * lpeg.P'"'^-1 + lpeg.C(('<' * lpeg.S'<['^-1)^-1) * lpeg.S' \t'^0 * lpeg.C((1-lpeg.S' \t')^0)) * lpeg.S' \t'^0 * lpeg.Cp()
local fontmap = {}
local function mapline(line, operator)
  if not operator then
    operator, line = optoperator:match(line)
  end
  if commentchar:match(line) then return end
  local pos = 1
  local tfmname, psname, flags, special, enc, font, subset
  local kind, word
  while pos ~= #line+1 do
    kind, word, pos = wordpatt:match(line, pos)
    if kind == "" then
      if not tfmname then tfmname = word
      elseif not psname and not purenumber:match(word) then
        psname = word
      elseif purenumber:match(word) then flags = tonumber(word)
      else
        error[[Invalid map file line, excessive simple words]]
      end
    elseif kind == '"' then
      special = word
    else
      if kind == "<[" or (kind ~= "<<" and word:sub(-4) == ".enc") then
        enc = word
      else
        font = word
        subset = kind ~= "<<"
      end
    end
  end
  fontmap[tfmname] = {psname or tfmname, flags or (font and 4 or 0x22), font, enc, special, subset}
end
local function mapfile(filename, operator)
  if not operator then
    operator, filename = optoperator:match(filename)
  end
  local file = io.open(kpse.find_file(filename, 'map'))
  for line in file:lines() do mapline(line, operator) end
  file:close()
end
return {
  mapline = mapline,
  mapfile = mapfile,
  fontmap = fontmap
}
