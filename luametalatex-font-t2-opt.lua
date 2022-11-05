-- This is optimizet2.lua.
-- Copyright 2019 Marcel Krüger <tex@2krueger.de>
--
-- This work may be distributed and/or modified under the
-- conditions of the LaTeX Project Public License version 1.3c.
-- The full text of this version can be found at
--   http://www.latex-project.org/lppl/lppl-1-3c.txt
--
-- This work has the LPPL maintenance status `maintained'
--
-- The Current Maintainer of this work is Marcel Krüger.
--
-- This work consists of the files buildcffwrapper.lua, buildotfwrapper.lua,
-- finish_pdffont.lua, finisht3.lua, glyph2char.lua, libSfnt.lua,
-- luaglyphlist.lua, luaotfprovider.lua, make_extensible_per_char.lua,
-- mpfont.lua, mplibtolist.lua, mplibtot2.lua, mpnodelib.lua,
-- mt1_fontloader.lua, nodebuilder.lua, optimizet2.lua, serializet2.lua.

local stack_limit = 48 + 1 -- +1 for the command byte

return function(cs)
  -- cs might contain some false entries, delete them
  do
    local j=1
    for i = 1,#cs do
      if cs[i] then
        if i ~= j then
          cs[j] = cs[i]
        end
        j = j+1
      end
    end
    for i = j,#cs do
      cs[i] = nil
    end
  end
  -- First some easy replacements:
  local use_hintmask
  for i, v in ipairs(cs) do
    if v[1] == 19 then
      -- If this happens only one time, we do not want masks
      use_hintmask = use_hintmask ~= nil
    elseif v[1] == 21 then -- rmoveto
      if v[2] == 0 then
        v[1] = 4
        v[2] = v[3]
        v[3] = nil
      elseif v[3] == 0 then
        v[1] = 22
        v[3] = nil
      end
    elseif v[1] == 5 then -- rlineto
      if v[2] == 0 then
        v[1] = 7
        v[2] = v[3]
        v[3] = nil
      elseif v[3] == 0 then
        v[1] = 6
        v[3] = nil
      end
    elseif v[1] == 8 then -- rrcurveto
      if v[2] == 0 then
        if v[6] == 0 then
          v[1] = 26 -- vvcurveto (even argument case)
          table.remove(v, 6)
          table.remove(v, 2)
        else
          v[1] = 30 -- vhcurveto
          table.remove(v, 2)
          if v[6] == 0 then table.remove(v, 6) end
        end
      elseif v[3] == 0 then
        if v[7] == 0 then
          v[1] = 27 -- hhcurveto (even argument case)
          table.remove(v, 7)
          table.remove(v, 3)
        else
          v[1] = 31 -- hvcurveto
          table.remove(v, 3)
          local t = v[5]
          table.remove(v, 5)
          if t ~= 0 then table.insert(v, t) end
        end
      elseif v[6] == 0 then
        v[1] = 26 -- vvcurveto (odd argument case)
        table.remove(v, 6)
      elseif v[7] == 0 then
        v[1] = 27 -- hhcurveto (odd argument case)
        table.remove(v, 7)
        local t = v[2]
        v[2] = v[3]
        v[3] = t
      end
    end
  end
  if not use_hintmask then
    for i, v in ipairs(cs) do
      if v[1] == 18 then
        v[1] = 1
      elseif not v[1] and cs[i+1] and cs[i+1][1] == 19 then
        v[1] = 3
      elseif v[1] == 19 then
        table.remove(cs, i)
        break
      end
    end
  end
  -- Try combining lineto segments. We could try harder, but this should
  -- never be triggered anyway.
  for i, v in ipairs(cs) do
    if v[1] == 6 or v[1] == 7 then
      while cs[i+1] and v[1] == cs[i+1][1] do
        v[2] = v[2] + cs[i+1][2]
        table.remove(cs, i+1)
      end
    end
  end
  -- Now use the variable argument versions of most commands
  for i, v in ipairs(cs) do
    if v[1] == 5 then -- rlineto
      while cs[i+1] and 5 == cs[i+1][1] and #v + #cs[i+1]-1 <= stack_limit do
        table.insert(v, cs[i+1][2])
        table.insert(v, cs[i+1][3])
        table.remove(cs, i+1)
      end
      if cs[i+1] and 8 == cs[i+1][1] and #v + #cs[i+1]-1 <= stack_limit then -- rrcurveto
        v[1] = 25 -- rlinecurveto
        for j=2,7 do table.insert(v, cs[i+1][j]) end
        table.remove(cs, i+1)
      end
    elseif v[1] == 6 or v[1] == 7 then
      local next_cmd = (v[1]-5)%2+6
      while cs[i+1][1] == next_cmd and #v + #cs[i+1]-1 <= stack_limit do
        next_cmd = (cs[i+1][1]-5)%2+6
        table.insert(v, cs[i+1][2])
        table.remove(cs, i+1)
      end
    elseif v[1] == 8 then
      while cs[i+1] and 8 == cs[i+1][1] and #v + #cs[i+1]-1 <= stack_limit do -- rrcurveto
        for j=2,7 do table.insert(v, cs[i+1][j]) end
        table.remove(cs, i+1)
      end
      if cs[i+1] and 5 == cs[i+1][1] and #v + #cs[i+1]-1 <= stack_limit then -- rlineto
        v[1] = 24 -- rcurveline
        table.insert(v, cs[i+1][2])
        table.insert(v, cs[i+1][3])
        table.remove(cs, i+1)
      end
    elseif v[1] ==  27 then
      while cs[i+1] and 27 == cs[i+1][1] and #cs[i+1] == 5 and #v + #cs[i+1]-1 <= stack_limit do -- hhcurveto
        for j=2,5 do table.insert(v, cs[i+1][j]) end
        table.remove(cs, i+1)
      end
    elseif v[1] ==  26 then
      while cs[i+1] and 26 == cs[i+1][1] and #cs[i+1] == 5 and #v + #cs[i+1]-1 <= stack_limit do -- vvcurveto
        for j=2,5 do table.insert(v, cs[i+1][j]) end
        table.remove(cs, i+1)
      end
    elseif v[1] == 30 or v[1] == 31 then
      local next_cmd = (v[1]-29)%2+30
      while #v % 2 == 1 and cs[i+1] and next_cmd == cs[i+1][1] and #v + #cs[i+1]-1 <= stack_limit do -- [vh|hv]curveto
        local next_cmd = (cs[i+1][1]-29)%2+30
        for j=2,#cs[i+1] do table.insert(v, cs[i+1][j]) end
        table.remove(cs, i+1)
      end
    elseif false then
      -- TODO: More commands
    end
  end
end
