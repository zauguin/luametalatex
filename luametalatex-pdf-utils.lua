local l = lpeg or require'lpeg'
local trailing_zeros = l.P'0'^0 * -l.R'09'
local strip_floats_patt = l.Cs((1-l.R'09' +
  (l.R'09')^1 * (l.P'.' * trailing_zeros / '' + l.P'.' * (l.R'09'-trailing_zeros)^1 * (trailing_zeros/''))^-1)^0)
local match = l.match

local function strip_floats(s)
  return match(strip_floats_patt, s)
end

local function to_bp(sp)
  return sp/65781.76
end

local function to_sp(bp)
  return (bp*65781.76+.5)//1
end

return {
  strip_floats = strip_floats,
  to_bp = to_bp,
  to_sp = to_sp,
}
