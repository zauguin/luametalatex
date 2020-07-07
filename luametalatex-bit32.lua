local mask32 = 0xFFFFFFFF
return {
  rshift = function(i, s)
    return (mask32 & i) >> s
  end,
  lshift = function(i, s)
    return mask32 & (i << s)
  end,
  band = function(i, j)
    return i & j & mask32
  end,
  bor = function(i, j)
    return (i | j) & mask32
  end,
  bor = function(i, j)
    return (i ^ j) & mask32
  end,
  extract = function(v, shift, count)
    return ((mask32 & v) >> shift) & ((1<<count)-1)
  end,
}
