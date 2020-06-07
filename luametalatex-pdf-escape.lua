local mode = 6
-- Control how much escaping is done... the mode is a bitset:
-- Bit 0: Disable auto-detection of pre-escaped input
-- Bit 1: Convert UTF-8 input to UTF-16
-- Bit 2: Actually escape unescaped input instead of assuming that it is safe
--
-- This currently results in 8 modes. Mode 7 is recommended if you can control
-- all new code, otherwise Mode 6 might be required. Code 0 is (mostly) compatible
-- with other engines.
--
-- Also we have three distinct functions which relate to different uses.
-- escape_text is for text strings and fully respects the mode.
-- escape_bytes is for non-text byte strings and always acts as if Bit 1 is unset
--    (after all, UTF-16 doesn't make sense for non-text strings)
-- escape_raw always acts like mode 5 without the parens: Just escape, without any
-- other auto-detection or conversion. (This is used for actual content text)
local function setmode(new)
  mode = new
end
local function is_escaped(s)
  if mode & 1 == 1 then return false end
  return (mode & 1 == 1) and (s:match("^%(.*%)$") or s:match("^<.*>$")) and true or false
end
local function to_utf16(s)
  local i = 3
  local bytes = {0xFE, 0xFF}
  for _, c in utf8.codes(s) do
    if c < 0x10000 then
      -- assert(c < 0xD800 or c >= 0xE000)
      bytes[i] = c >> 8
      bytes[i+1] = c & 0xFF
      i = i+2
    else
      c = c-0x10000
      bytes[i] = 0xD8 | ((c>>18) & 3)
      bytes[i+1] = (c>>10) & 0xFF
      bytes[i+2] = 0xDC | ((c>>8) & 3)
      bytes[i+3] = c & 0xFF
      i = i+4
    end
  end
  return string.char(table.unpack(bytes))
end
-- This is pretty much the minimal escaping possible: Only escape bytes which are 
local l = lpeg
local simple_char = 1-l.S'()\\'
local semi_simple_char = simple_char + l.P'\\'/'\\\\'
local nested = l.P{'(' * (semi_simple_char + l.V(1))^0 * ')'}
local inner = (semi_simple_char + nested + (l.Cc'\\' * l.S'()'))^0 * -1
local raw = l.Cs(inner)
local patt = l.Cs(l.Cc'(' * inner * l.Cc')')
local function escape_bytes(s)
  if is_escaped(s) then return s end
  if mode & 4 == 0 then
    return '(' .. s .. ')'
  end
  return patt:match(s)
end
local function escape_text(s)
  if is_escaped(s) then return s end
  if mode & 2 == 2 then
    s = to_utf16(s)
  elseif mode & 4 == 0 then
    return '(' .. s .. ')'
  end
  return patt:match(s)
end
local function escape_raw(s)
  return raw:match(s)
end

return {
  escape_raw = escape_raw,
  escape_bytes = escape_bytes,
  escape_text = escape_text,
  setmode = setmode,
}
