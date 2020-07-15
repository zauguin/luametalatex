local function decode_char(buf)
  local flag = buf:byte(1)
  local form = flag & 0x07
  local tfm, dx, dy, w, h, hoff, voff, off
  if form < 4 then
    tfm, dx, w, h, hoff, voff, off = string.unpack(">I3BBBbb", buf, 4)
    dx, dy = dx * 2^16, 0
  elseif form < 7 then
    tfm, dx, w, h, hoff, voff, off = string.unpack(">I3HHHhh", buf, 5)
    dx, dy = dx * 2^16, 0
  else
    tfm, dx, dy, w, h, hoff, voff, off = string.unpack(">I4I4I4I4I4i4i4", buf, 10)
  end
  local dyn_f, state = flag >> 4, flag & 8 == 8
  local data
  local stride = w+7>>3
  if dyn_f == 14 then
    print(state)
    -- assert(not state)
    data = lua.newtable(stride*h, 0)
    local bit_offset, saved = 0
    local delta_bit_offset = 8 - w%8
    delta_bit_offset = delta_bit_offset == 8 and 0 or delta_bit_offset
    for y=0,h-1 do
      for x=1,stride do
        if bit_offset == 0 then
          saved = buf:byte(off)
          data[y*stride+x] = saved
        else
          local saved_mask = (1<<bit_offset)-1
          local current = (saved&saved_mask) << 8-bit_offset
          saved = buf:byte(off)
          data[y*stride+x] = current | (saved & ~saved_mask) >> bit_offset
        end
        off = off+1
      end
      if delta_bit_offset then
        data[(y+1)*stride] = data[(y+1)*stride] & (0x100 - (1<<delta_bit_offset))
      end
      bit_offset = bit_offset + delta_bit_offset
      if bit_offset >= 8 then
        bit_offset = bit_offset-8
        off = off-1
        saved = buf:byte(off)
      end
    end
  else
    data = {string.rep('\0', stride*h):byte(1,-1)} -- FIXME: This is probably really slow
    local nibble, repeat_row = nil, 0
    local function get_nibble()
      if nibble then
        local cur = nibble
        nibble = nil
        off = off+1
        return cur
      else
        local cur = buf:byte(off)
        nibble = cur&0xF
        return cur >> 4
      end
    end
    local function get_packed()
      local cur = get_nibble()
      if cur == 0 then
        local i = 0
        repeat
          cur = get_nibble()
          i = i+1
        until cur ~= 0
        for _=1,i do
          cur = (cur<<4) + get_nibble()
        end
        return cur - 0xF + (13-dyn_f << 4) + dyn_f
      elseif cur <= dyn_f then
        return cur
      elseif cur < 14 then
        return (cur-dyn_f-1 << 4) + get_nibble() + dyn_f + 1
      else
        repeat_row = cur == 14 and get_packed() or 1
        return get_packed()
      end
    end
    local cur_x, cur_y = 0, 0
    while cur_y < h do
      local count = get_packed()
      repeat
        local this_line = math.min(w - cur_x, count)
        count = count - this_line
        if state then
          local cur_bit_offset = cur_x % 8
          if cur_bit_offset ~= 0 then -- We are in the middle of a byte
            cur_bit_offset = 8-cur_bit_offset -- The remaining bits in the byte
            local off = cur_y*stride+(cur_x>>3)+1
            if this_line > cur_bit_offset then -- Fill byte with ones
              data[off] = data[off] + (1<<cur_bit_offset)-1
              this_line, cur_x = this_line-cur_bit_offset, cur_x+cur_bit_offset
            else
              data[off] = data[off] + (1<<cur_bit_offset)-(1<<cur_bit_offset-this_line)
              this_line, cur_x = 0, cur_x+this_line
            end
          end
          while this_line >= 8 do
            data[cur_y*stride+(cur_x>>3)+1] = 0xFF
            this_line, cur_x = this_line-8, cur_x+8
          end
          if this_line ~= 0 then
            data[cur_y*stride+(cur_x>>3)+1] = 0x100-(1<<8-this_line)
          end
        end
        cur_x = cur_x + this_line
        if cur_x == w then
          for i = 1, repeat_row do
            table.move(data, cur_y*stride+1, (cur_y+1)*stride, (cur_y+i)*stride+1) -- TODO
          end
          cur_y, cur_x, repeat_row = cur_y + 1 + repeat_row, 0, 0
        end
      until count == 0
      state = not state
    end
  end
  data = string.char(table.unpack(data))
  return {
    data = data,
    tfm = tfm,
    dx = dx,
    dy = dy,
    hoff = hoff,
    voff = voff,
    w = w,
    h = h,
  }
end

local commands = {
  [240] = function(buf, off, t)
    local xxx xxx, off = string.unpack(">xs1", buf, off)
    return off
  end,
  [241] = function(buf, off, t)
    local xxx xxx, off = string.unpack(">xs2", buf, off)
    return off
  end,
  [242] = function(buf, off, t)
    local xxx xxx, off = string.unpack(">xs3", buf, off)
    return off
  end,
  [243] = function(buf, off, t)
    local xxx xxx, off = string.unpack(">xs4", buf, off)
    return off
  end,
  [244] = function(buf, off, t)
    local yyy yyy, off = string.unpack(">xI4", buf, off)
    return off
  end,
  [247] = function(buf, off, t)
    local ident
    ident, t.comment, t.designsize, t.checksum, t.hppp, t.vppp, off = string.unpack(">xBs1I4I4I4I4", buf, off)
    if ident ~= 89 then
      error[[Not a PK file]]
    end
    return off
  end,
}
local function parse_commands(buf, off, t)
  local cmd = buf:byte(off)
  assert(cmd == 247)
  repeat
    if cmd < 240 then
      local form = cmd & 0x07
      local chr, newoff, length
      if form < 4 then
        length, chr, newoff = string.unpack(">xBB", buf, off)
        length = length + ((form & 3)<<8)
      elseif form < 7 then
        length, chr, newoff = string.unpack(">xHB", buf, off)
        length = length + ((form & 3)<<16)
      else
        length, chr, newoff = string.unpack(">xI4I4", buf, off)
      end
      newoff = newoff + length
      t[chr] = decode_char(buf:sub(off, newoff))
      off = newoff
    else
      local handler = commands[cmd]
      if not handler then
        print([[Unknown command ]] .. cmd)
        return off-1
      end
      off = handler(buf, off, t)
    end
    cmd = buf:byte(off)
  until cmd == 245
  return off
end
return function(data)
  local res = {}
  local off = parse_commands(data, 1, res)
  -- assert(off == #pk+1) -- TODO: Check that only fillup bytes follow
  return res
end
