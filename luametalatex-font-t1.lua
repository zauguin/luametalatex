local white = (lpeg.S'\0\9\10\12\13\32' + '%' * (1 - lpeg.S'\r\n')^0)^1
local regular = 1-lpeg.S'()<>[]{}/%\0\9\10\12\13\32'
local lastbase = '123456789abcdefghiklmnopqrstuvwxyz'
local number = lpeg.Cmt(lpeg.R'09'^1/tonumber * '#', function(s, p, base)
                 if base < 2 then return end
                 local pattern
                 if base <= 10 then
                   pattern = lpeg.R('0' .. lastbase:sub(base-1, base-1))
                 else
                   pattern = lpeg.R'09' + lpeg.R('a' .. lastbase:sub(base-1, base-1)) + lpeg.R('A' .. lastbase:sub(base-1, base-1):upper())
                 end
                 local num, p = (lpeg.C(pattern^1) * lpeg.Cp()):match(s, p)
                 return p, num and tonumber(num, base)
               end)
             + (lpeg.S'+-'^-1 * ('.' * lpeg.R'09'^1 + lpeg.R'09'^1 * lpeg.P'.'^-1 * lpeg.R'09'^0) * (lpeg.S'eE' * lpeg.S'+-'^-1 * lpeg.R'09'^1)^-1)/tonumber
local literalstring = lpeg.P{'(' * lpeg.Cs((
    lpeg.P'\\n'/'\n'+lpeg.P'\\r'/'\r'+lpeg.P'\\t'/'\t'+lpeg.P'\\b'/'\b'+lpeg.P'\\f'/'\f'
    +'\\'*lpeg.C(lpeg.R'07'*lpeg.R'07'^-2)/function(n)return string.char(tonumber(n, 8))end
    +'\\'*('\n' + ('\r' * lpeg.P'\n'^-1))/''
    +'\\'*lpeg.C(1)/1
    +('\n' + ('\r' * lpeg.P'\n'^-1))/'\n'
    +(1-lpeg.S'()\\')+lpeg.V(1))^0) * ')'}
local hexstring = '<' * lpeg.Cs((
  lpeg.C(lpeg.R'09'+lpeg.R'af'+lpeg.R'AF')*(lpeg.C(lpeg.R'09'+lpeg.R'af'+lpeg.R'AF')+lpeg.Cc'0')/function(a,b)return string.char(tonumber(a..b, 16))end)^0) * '>'
local name = lpeg.C(regular^1)
local lname = '/' * name / 1
local function decrypt(key, n, cipher)
  -- Generally you should never implement your own crypto. So we call a well known, peer reviewed,
  -- high-quality cryptographic library. --- Ha-Ha, of course we are implementing by ourselves.
  -- That might be completely unsecure, but given that the encryption keys are well known constants
  -- documented in the T1 Spec, there is no need to worry about it.
  -- Also I do not think any cryptorgraphic library would implement this anyway, it doesn't even
  -- really deserve the term encryption.
  local decoded = {string.byte(cipher, 1,-1)}
  for i=1,#decoded do
    local c = decoded[i]
    decoded[i] = c ~ (key>>8)
    key = (((c+key)&0xFFFF)*52845+22719)&0xFFFF
  end
  return string.char(table.unpack(decoded, n+1))
end

-- io.stdout:write(decrypt(55665, 4, string.sub(io.stdin:read'a', 7)))
local boolean = (lpeg.P'true' + 'false')/{["true"] = true, ["false"] = false}
local anytype = {hexstring + literalstring + number + lname + boolean + lpeg.V(2) + name, lpeg.Ct('[' * (white^-1 * lpeg.V(1))^0 * white^-1 * ']' + '{' * (white^-1 * lpeg.V(1))^0 * white^-1 * '}' * white^-1 * lpeg.P"executeonly"^-1)}
local dict = lpeg.Cf(lpeg.Carg(1) * lpeg.Cg(white^-1*lname*white^-1*(anytype)*white^-1*lpeg.P"readonly"^-1*white^-1*lpeg.P"noaccess"^-1*white^-1*(lpeg.P"def"+"ND"+"|-"))^0, rawset)
local encoding = (white+anytype-("dup"*white))^0/0
               * lpeg.Cf(lpeg.Ct''
                 * lpeg.Cg("dup"*white*number*white^-1*lname*white^-1*"put"*white)^0
                 , rawset)
               * lpeg.P"readonly"^-1*white*"def"
local function parse_encoding(offset, str)
  local found
  found, offset = (encoding*lpeg.Cp()):match(str, offset)
  return found, offset
end
local function parse_fontinfo(offset, str)
  local found
  repeat
    found, offset = ((white+(anytype-name))^0/0*name*lpeg.Cp()):match(str, offset)
  until found == 'begin'
  found, offset = (dict*lpeg.Cp()):match(str, offset, {})
  offset = (white^-1*"end"*white^-1*lpeg.P"readonly"^-1*white^-1*"def"):match(str, offset)
  return found, offset
end
local binary_bytes = lpeg.Cmt(number*white^-1*(lpeg.P'-| ' + 'RD '), function(s, p, l)return p+l, s:sub(p, p+l-1) end)*white^-1*(lpeg.P"|-"+"|"+"ND"+"NP")
local charstr = white^-1*lname*(white^-1*(anytype-lname))^0/0*white^-1
            * lpeg.Cf(lpeg.Ct''
              * lpeg.Cg(lname*white^-1*binary_bytes*white)^0
              , rawset)
            * lpeg.P"end"*white
local subrs = (white^-1*(anytype-("dup"*white)))^0/0*white^-1
              * lpeg.Cf(lpeg.Ct''
                * lpeg.Cg("dup"*white^-1*number*white^-1*binary_bytes*white)^0
                , rawset)
              * (lpeg.P"readonly"*white)^-1 * (lpeg.P"noaccess"*white)^-1*(lpeg.P"def"+"ND"+"|-")
local function parse_private(offset, str)
  local mydict, found
  repeat
    found, offset = ((white+(anytype-name))^0/0*name*lpeg.Cp()):match(str, offset)
  until found == 'begin'
  mydict, offset = (dict*lpeg.Cp()):match(str, offset, {})
  found = (white^-1*lname):match(str, offset)
  if found == "Subrs" then
    mydict.Subrs, offset = (subrs*lpeg.Cp()):match(str, offset)
  end
  return mydict, offset
end
local function continue_maintable(offset, str, mydict)
  mydict, offset = (dict*lpeg.Cp()):match(str, offset, mydict)
  local found = (white^-1*lname):match(str, offset)
  if found == "FontInfo" then
    mydict.FontInfo, offset = parse_fontinfo(offset, str)
    return continue_maintable(offset, str, mydict)
  elseif found == "Encoding" then
    mydict.Encoding, offset = parse_encoding(offset, str)
    return continue_maintable(offset, str, mydict)
  elseif found == "Private" then
    mydict.Private, offset = parse_private(offset, str)
    return continue_maintable(offset, str, mydict)
  elseif found == "CharStrings" then
    mydict.CharStrings, offset = (charstr*lpeg.Cp()):match(str, offset)
    return mydict
  else
    local newoffset = ((white+name)^1/0*lpeg.Cp()):match(str, offset)
    if newoffset and offset <= #str then
      return continue_maintable(newoffset, str, mydict)
    end
  end
  print(str:sub(offset))
  error[[Unable to read Type 1 font]]
end
local function parse_maintable(offset, str)
  local found
  repeat
    found, offset = ((white+(anytype-name))^0/0*name*lpeg.Cp()):match(str, offset)
  until found == 'begin'
  return continue_maintable(offset, str, {})
end

return function(filename)
  local file = io.open(filename)
  local _, length = string.unpack("<I2I4", file:read(6))
  local preface = file:read(length)
  _, length = string.unpack("<I2I4", file:read(6))
  local private = decrypt(55665, 4, file:read(length))
  file:close()
  local after = parse_maintable(1, preface .. private)
  local lenIV = after.Private.lenIV or 4
  local chars = after.CharStrings
  for k, v in pairs(chars) do
    chars[k] = decrypt(4330, lenIV, v)
  end
  local subrs = after.Private.Subrs
  for k, v in pairs(subrs) do
    subrs[k] = decrypt(4330, lenIV, v)
  end
  return after
end
