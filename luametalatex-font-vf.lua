local readfile = require'luametalatex-readfile'

local fontcmds = {
  [243] = ">I1I4I4I4BB",
  [244] = ">I2I4I4I4BB",
  [245] = ">I3I4I4I4BB",
  [246] = ">I4I4I4I4BB",
}
local function read_fonts(buf, i, fonts, size)
  local cmd = fontcmds[string.byte(buf, i)]
  if not cmd then return i end
  local fid, check, scale, designsize, arealen, namelen, i =
    string.unpack(cmd, buf, i + 1)
  fid = fid + 1 -- We prefer 1-based arrays
  local fsize = size * scale >> 20
  if fonts[fid] then error[[font number reused in VF file]] end
  fonts[fid] = {
    area = arealen > 0 and string.sub(buf, i, i+arealen-1) or nil,
    name = string.sub(buf, i+arealen, i+arealen+namelen-1),
    size = fsize,
    designsize = designsize >> 4,
    checksum = check,
  }
  return read_fonts(buf, i+arealen+namelen, fonts, size)
end
local Cmds = {
  [1] = ">I1",
  [2] = ">I2",
  [3] = ">I3",
  [4] = ">I4",
}
local cmds = {
  [1] = ">i1",
  [2] = ">i2",
  [3] = ">i3",
  [4] = ">i4",
}
local xxx = {
  [239] = ">s1",
  [240] = ">s2",
  [241] = ">s3",
  [242] = ">s4",
}
local function read_chars(buf, i, characters, size)
  local cmd = string.byte(buf, i)
  if cmd > 242 then return i end
  local code, tfmwidth
  if cmd == 242 then
    cmd, code, tfmwidth, i = string.unpack(">I4I4I4", buf, i + 1)
  else
    code, tfmwidth, i = string.unpack(">BI3", buf, i + 1)
  end
  local commands = {}
  local character = {
    width = tfmwidth, -- Unscaled for compatibility with LuaTeX
    commands = commands,
  }
  characters[code] = character
  local after = i + cmd
  local w, x, y, z, stack = 0, 0, 0, 0, {}
  while i < after do
    local cmd = string.byte(buf, i)
    if cmd <= 131 then
      if cmd >= 128 then
        cmd, i = string.unpack(Cmds[cmd-127], buf, i + 1)
      else
        i = i + 1
      end
      commands[#commands + 1] = { "char", cmd }
    elseif cmd == 132 then
      local height, width
      height, width, i = string.unpack(">I4I4", buf, i + 1)
      commands[#commands + 1] =
        { "rule", height * size >> 20, width * size >> 20 }
    elseif cmd <= 136 then
      cmd, i = string.unpack(Cmds[cmd-132], buf, i + 1)
      commands[#commands + 1] = { "push" }
      commands[#commands + 1] = { "char", cmd }
      commands[#commands + 1] = { "pop" }
    elseif cmd == 137 then
      local height, width
      height, width, i = string.unpack(">I4I4", buf, i + 1)
      commands[#commands + 1] = { "push" }
      commands[#commands + 1] =
        { "rule", height * size >> 20, width * size >> 20 }
      commands[#commands + 1] = { "pop" }
    elseif cmd == 138 then -- NOP
      i = i + 1
    elseif cmd <= 140 then
      error[[Invalid command in packet]]
    elseif cmd == 141 then
      stack[#stack+1] = {w, x, y, z}
      commands[#commands + 1] = { "push" }
      i = i + 1
    elseif cmd == 142 then
      local top = stack[#stack]
      if not top then error[[Attempt to pop with empty stack]] end
      stack[#stack] = nil
      w, x, y, z = top[1], top[2], top[3], top[4]
      commands[#commands + 1] = { "pop" }
      i = i + 1
    elseif cmd <= 146 then
      cmd, i = string.unpack(cmds[cmd-142], buf, i + 1)
      commands[#commands + 1] = { "right", (cmd * size >> 20) | (cmd < 0 and 0xFFFFFFFF00000000 or 0) }
    elseif cmd == 147 then
      commands[#commands + 1] = { "right", w }
      i = i + 1
    elseif cmd <= 151 then
      cmd, i = string.unpack(cmds[cmd-147], buf, i + 1)
      w = (cmd * size >> 20) | (cmd < 0 and 0xFFFFFFFF00000000 or 0)
      commands[#commands + 1] = { "right", w }
    elseif cmd == 152 then
      commands[#commands + 1] = { "right", x }
      i = i + 1
    elseif cmd <= 156 then
      cmd, i = string.unpack(cmds[cmd-152], buf, i + 1)
      x = (cmd * size >> 20) | (cmd < 0 and 0xFFFFFFFF00000000 or 0)
      commands[#commands + 1] = { "right", x }
    elseif cmd <= 160 then
      cmd, i = string.unpack(cmds[cmd-156], buf, i + 1)
      commands[#commands + 1] = { "down", (cmd * size >> 20) | (cmd < 0 and 0xFFFFFFFF00000000 or 0) }
    elseif cmd == 161 then
      commands[#commands + 1] = { "down", y }
      i = i + 1
    elseif cmd <= 165 then
      cmd, i = string.unpack(cmds[cmd-161], buf, i + 1)
      y = (cmd * size >> 20) | (cmd < 0 and 0xFFFFFFFF00000000 or 0)
      commands[#commands + 1] = { "down", y }
    elseif cmd == 166 then
      commands[#commands + 1] = { "down", z }
      i = i + 1
    elseif cmd <= 170 then
      cmd, i = string.unpack(cmds[cmd-166], buf, i + 1)
      z = (cmd * size >> 20) | (cmd < 0 and 0xFFFFFFFF00000000 or 0)
      commands[#commands + 1] = { "down", z }
    elseif cmd <= 238 then
      if cmd >= 235 then
        cmd, i = string.unpack(Cmds[cmd-234], buf, i + 1)
      else
        cmd, i = cmd - 171, i + 1
      end
      commands[#commands + 1] = { "font", cmd + 1 } -- 1-based fonts
    elseif xxx[cmd] then
      cmd, i = string.unpack(xxx[cmd], buf, i + 1)
      commands[#commands + 1] = { "special", cmd }
    else
      error[[Invalid command in packet]]
    end
  end
  if i > after then error[[Ill-formed packet]] end
  return read_chars(buf, after, characters, size)
end
local function parse_vf(buf, i, size)
  local font = {}
  local magic, designsize
  magic, font.header, font.checksum, designsize, i =
    string.unpack(">Hs1I4I4", buf, i)
  if magic ~= 247*256+202 then error[[Not a VF file]] end
  font.designsize = designsize >> 4

  local fonts, characters = {}, {}
  font.fonts, font.characters = fonts, characters
  
  i = read_fonts(buf, i, fonts, size)
  i = read_chars(buf, i, characters, size)

  return font
end
local basename = ((1-lpeg.S'\\/')^0*lpeg.S'\\/')^0*lpeg.C((1-lpeg.P'.tfm'*-1)^0)
return function(name, size, must_exist)
  local file <close> = readfile('vf', name)
  if not file then return end
  local result = parse_vf(file(), 1, size)
  result.name = basename:match(name)
  return result
end
