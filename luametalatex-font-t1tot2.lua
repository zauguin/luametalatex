local function parse_charstring(cs, subrs, result)
  result = result or {{false}}
  local lastresult = result[#result]
  local i = 1
  while i~=#cs+1 do
    local cmd = cs:byte(i)
    if cmd == 255 then
      lastresult[#lastresult+1] = string.unpack(">i4", cs:sub(i+1, i+4))
      i = i+4
    elseif cmd >= 251 then
      lastresult[#lastresult+1] = -((cmd-251)*256)-string.byte(cs, i+1)-108
      i = i+1
    elseif cmd >= 247 then
      lastresult[#lastresult+1] = (cmd-247)*256+string.byte(cs, i+1)+108
      i = i+1
    elseif cmd >= 32 then
      lastresult[#lastresult+1] = cmd-139
    elseif cmd == 9 then -- closepath, implicit in Type2
    elseif cmd == 10 then
      local subr = subrs[lastresult[#lastresult]]
      lastresult[#lastresult] = nil
      parse_charstring(subr, subrs, result)
      lastresult = result[#result]
    elseif cmd == 11 then
      break -- We do not keep subroutines, so drop returns and continue with the outer commands
    elseif cmd == 12 then
      i = i+1
      cmd = cs:byte(i)
      if cmd == 12 then -- div, we might have huge parameters, so execute directly
        lastresult[#lastresult-1] = lastresult[#lastresult-1]/lastresult[#lastresult]
        lastresult[#lastresult] = nil
      elseif cmd == 16 then -- othersubr...
        cmd = lastresult[#lastresult]
        lastresult[#lastresult] = nil
        local numargs = lastresult[#lastresult]
        lastresult[#lastresult] = nil
        if cmd == 3 then -- Hint replacement. This is easy, we support hint replacement, so we
                         -- keep the original subr number
          assert(numargs == 1)
        elseif cmd == 1 then -- Flex initialization
        elseif cmd == 2 then -- Flex parameter
          if result[#result-1].flex then
            result[#result] = nil -- TODO: Warn if there were additional values in lastresult. 
            lastresult = result[#result] -- We keep collecting arguments
          end
          lastresult.flex = true
        elseif cmd == 0 then -- Flex
          local flexinit = result[#result-1]
          lastresult[2] = lastresult[2] + flexinit[2]
          lastresult[3] = lastresult[3] + flexinit[3]
          lastresult.flex = nil
          result[#result-1] = lastresult
          result[#result] = nil
          lastresult[#lastresult] = nil
          lastresult[#lastresult] = nil
          lastresult[1] = -36
          lastresult = {false}
          result[#result+1] = lastresult
          lastresult[#lastresult+1] = "setcurrentpointmark"
        elseif cmd == 12 or cmd == 13 then
          local pending = {}
          local results = #lastresult
          for i = 1,numargs do
            pending[i] = lastresult[results-numargs+i]
            lastresult[results-numargs+i] = nil
          end
          if lastresult.pendingargs then
            for i = 1,#lastresult.pendingargs do
              pending[numargs+i] = lastresult.pendingargs[i]
            end
          end
          if cmd == 12 then
            lastresult.pendingargs = pending
          else
            lastresult.pendingargs = nil
            local n = pending[1]
            local i = 2
            local groups = {}
            for group = 1, n do
              local current = {20}
              local last = 0
              while pending[i+1] > 0 do
                last = last + pending[i]
                current[#current+1] = {1, last, pending[i+1]}
                last = last + pending[i+1]
                i = i+2
              end
              last = last + pending[i]
              current[#current+1] = {1, last + pending[i+1], -pending[i+1]}
              groups[group] = current
              i = i+2
            end
            n = pending[i]
            i = i+1
            for group = 1, n do
              local current = groups[group] or {20}
              local last = 0
              while pending[i+1] > 0 do
                last = last + pending[i]
                current[#current+1] = {3, last, pending[i+1]}
                last = last + pending[i+1]
                i = i+2
              end
              last = last + pending[i]
              current[#current+1] = {3, last + pending[i+1], -pending[i+1]}
              groups[group] = current
              i = i+2
            end
            assert(i == #pending+1)
            table.move(groups, 1, #groups, #result, result) -- This overwrites lastresult
            result[#result+1] = lastresult -- And restore lastresult
          end
        else
          error[[UNSUPPORTED Othersubr]]
        end
      elseif cmd == 17 then -- pop... Ignore them, they should already be handled by othersubr.
                            --        Compatibility with unknown othersubrs is futile, because
                            --        we can't interpret PostScript
      elseif cmd == 33 then -- setcurrentpoint... If we expected this, it is already handled.
                            --                    Otherwise fail, according to the spec it should
                            --                    only be used with othersubrs.
        assert(lastresult[#lastresult] == "setcurrentpointmark")
        lastresult[#lastresult] = nil
      else
        lastresult[1] = -cmd-1
        lastresult = {false}
        result[#result+1] = lastresult
      end
    else
      lastresult[1] = cmd
      lastresult =  {false}
      result[#result+1] = lastresult
    end
    i = i+1
  end
  return result
end
local function adjust_charstring(cs) -- Here we get a not yet optimized but parsed Type1 charstring and
  -- do some adjustments to make them more "Type2-like".
  cs[#cs] = nil -- parse_charstring adds a `{false}` for internal reasons. Just drop it here. FIXME: Check that #cs[#cs]==1, otherwise there were values left on the charstring stack
  if cs[1][1] ~= 13 then
    error[[Unsupported first Type1 operator]] -- probably cs[1][1] == sbw
    -- If you find a font using this, I'm sorry for you.
  end
  local hoffset = cs[1][2]
  if hoffset ~= 0 then
    -- non-zero sidebearings :-(
    for i, cmd in ipairs(cs) do
      if cmd[1] == 21 or cmd[1] == 22 then
        cmd[2] = cmd[2] + cs[1][2]
        break
      elseif cmd[1] == 4 then
        cmd[3] = cmd[2]
        cmd[2] = cs[1][2]
        cmd[1] = 21
        break
      end
      -- Here I rely on the fact that the first relative command is always [hvr]moveto.
      -- This is based on "Use rmoveto for the first point in the path." in the T1 spec
      -- for hsbw. I am not entirely sure if this is a strict requirement or if there could
      -- be weird charstrings where this fails (esp. since [hv]moveto are also used in the example), 
      -- but I decided to take the risk.
      -- hints are affected too. They do not use relative coordinates in T1, so we store the offset
      -- and handle hints later
    end
  end
  cs[1][2] = cs[1][3]
  cs[1][3] = nil
  cs[1][1] = nil
  -- That's it for the width, now we need some hinting stuff. This would be easy, if hint replacement
  -- wouldn't require hint masks in Type2. And because we really enjoy this BS, we get counter
  -- hinting as an additional treat... Oh, if you actually use counter hinting: Please test this
  -- and report back if it works, because this is pretty much untested.
  local stems = {}
  local stem3 = {20}
  local cntrs = {}
  -- First iterate over the charstring, recording all hints and collecting them in stems/stem3/cntrs
  for i, cmd in ipairs(cs) do
    if cmd[1] == 1 or cmd[1] == 3 then
      stems[#stems + 1] = cmd
    elseif cmd[1] == -2 or cmd[1] == -3 then
      local c = cmd[1] == -2 and 3 or 1
      stems[#stems + 1] = {c, cmd[2], cmd[3]}
      stems[#stems + 1] = {c, cmd[4], cmd[5]}
      stems[#stems + 1] = {c, cmd[6], cmd[7]}
      table.move(stems, #stems-2, #stems, #stem3+1, stem3)
      cs[i] = false
    elseif cmd[1] == 20 then
      cntrs[#cntrs+1] = cmd
      table.move(cmd, 2, #cmd, #stems+1, stems)
    end
  end
  table.sort(stems, function(first, second)
    if first[1] ~= second[1] then return first[1] < second[1] end
    if first[2] ~= second[2] then return first[2] < second[2] end
    return first[3] < second[3]
  end)
  -- Now store the index of every stem in the idx member of the hint command
  -- After that `j` stores the number of stems
  local j,k = 1,1
  if stems[1] then stems[1].idx = 1 end
  for i = 2,#stems do
    if stems[i][2] == stems[k][2] and stems[i][3] == stems[k][3] then
      stems[i].idx = j
      stems[i] = false
    else
      j, k = j+1, i
      stems[i].idx = j
    end
  end
  -- Now the indices are known, so the cntrmask can be written, if counters or stem3 occured.
  -- This is done before writing the stem list to make the thable.insert parameters easier.
  -- First translate stem3 into a counter group
  if stem3[2] then
    cntrs[#cntrs+1] = stem3
    table.insert(cs, 2, stem3)
  end
  local bytes = {}
  for i=1, #cntrs do
    local cntr = cntrs[i]
    for l = 1, math.floor((j + 7)/8) do
      bytes[l] = 0
    end
    for l = 2, #cntr do
      local idx = cntr[l].idx-1
      bytes[math.floor(idx/8) + 1] = bytes[math.floor(idx/8) + 1] | (1<<(7-idx%8))
      cntr[l] = nil
    end
    cntr[2] = string.char(table.unpack(bytes))
  end
  local current = 1
  -- Then list the collected stems at the beginning of the charstring
  if stems[current] and stems[current][1] == 1 then
    local stem_tbl, last = {18}, 0
    while stems[current] ~= nil and (not stems[current] or stems[current][1] == 1) do
      if stems[current] then
        stem_tbl[#stem_tbl + 1] = stems[current][2] - last
        last = stems[current][2] + stems[current][3]
        stem_tbl[#stem_tbl + 1] = stems[current][3]
      end
      current = current + 1
    end
    table.insert(cs, 2, stem_tbl)
  end
  if stems[current] and stems[current][1] == 3 then
    local stem_tbl, last = {false}, -hoffset
    while stems[current] ~= nil and (not stems[current] or stems[current][1] == 3) do
      if stems[current] then
        stem_tbl[#stem_tbl + 1] = stems[current][2] - last
        last = stems[current][2] + stems[current][3]
        stem_tbl[#stem_tbl + 1] = stems[current][3]
      end
      current = current + 1
    end
    table.insert(cs, stems[1][1] == 1 and 3 or 2, stem_tbl)
  end
  -- Finally, replace every run of hint commands, corresponding to a hint replacement, by a single hintmask
  local i = 1
  while cs[i] ~= nil do
    if cs[i] and cs[i].idx then
      if stem3[2] then
        local s3 = stem3[2]
        for l = 1, math.floor((j + 7)/8) do
          bytes[l] = string.byte(s3, l)
        end
      else
        for l = 1, math.floor((j + 7)/8) do
          bytes[l] = 0
        end
      end
      while (cs[i] or {}).idx do
        local idx = cs[i].idx-1
        bytes[math.floor(idx/8) + 1] = bytes[math.floor(idx/8) + 1] | (1<<(7-idx%8))
        cs[i] = false
        i = i+1
      end
      i = i-1
      cs[i] = {19, string.char(table.unpack(bytes))}
    end
    i = i+1
  end
end
return function(cs, subrs)
  local parsed = parse_charstring(cs, subrs)
  adjust_charstring(parsed)
  return parsed
end
