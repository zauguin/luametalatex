local white = (lpeg.S'\0\9\10\12\13\32' + '%' * (1 - lpeg.S'\r\n')^0)^1 -- Whitespace

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

local boolean = (lpeg.P'true' + 'false')/{["true"] = true, ["false"] = false}

-- Everything above this line works pretty reliable and can be understood by reading the PostScript specs.

-- This is Type1 specific. The only thing which might need adjustment is adding alternative spellings for -|, RD, |-, |, etc.
local binary_bytes = lpeg.Cmt(number*white^-1*(lpeg.P'-| ' + 'RD '), function(s, p, l)return p+l, s:sub(p, p+l-1) end)*white^-1*(lpeg.P"|-"+"|"+"ND"+"NP")
-- Attention: The |-, |, ND, NP already contain an implicit `def`

local function decrypt(key, n, cipher)
  -- Generally you should never implement your own crypto. So we call a well known, peer reviewed,
  -- high-quality cryptographic library. --- Ha-Ha, of course we are implementing by ourselves.
  -- That might be completely unsecure, but given that the encryption keys are well known constants
  -- documented in the T1 Spec, there is no need to worry about it.
  -- Also I do not think any cryptographic library would implement this anyway, it doesn't even
  -- really deserve the term encryption.
  local decoded = {string.byte(cipher, 1,-1)}
  for i=1,#decoded do
    local c = decoded[i]
    decoded[i] = c ~ (key>>8)
    key = (((c+key)&0xFFFF)*52845+22719)&0xFFFF
  end
  return string.char(table.unpack(decoded, n+1))
end

local anytype = {
      hexstring
    + literalstring
    + number
    + lname
    + boolean
    + lpeg.V'array'
    + name,
  array = lpeg.Ct( '[' * (white^-1 * lpeg.V(1))^0 * white^-1 * ']' -- Arrays have two possible syntaxes
                 + '{' * (white^-1 * lpeg.V(1))^0 * white^-1 * '}') * (white * "executeonly")^-1
}

local function skip_until(p)
  if type(p) == 'string' then p = p * -name end
  return (white + anytype - p)^0/0
end
local skip_to_begin = skip_until'begin' * 'begin'

local def_like = (lpeg.P'def' + 'ND' + '|-') * -name

local encoding = '/' * lpeg.C'Encoding' * -name
               * skip_until'dup'
               * lpeg.Cf(lpeg.Ct''
                 * lpeg.Cg("dup"*white*number*white^-1*lname*white^-1*"put"*white)^0
                 , rawset)
               * ("readonly"*white)^-1 * "def"

local charstr = '/' * lpeg.C'CharStrings' * -name
            * skip_until(lname) -- sometimes we get weird stuff in between. Just make sure that we don't swallow a charname
            * lpeg.Cf(lpeg.Ct''
              * lpeg.Cg(lname*white^-1*binary_bytes*white)^0 -- Remember: binary_bytes includes a `def`
              , rawset)
            * lpeg.P"end"*white

local subrs = '/' * lpeg.C'Subrs' * -name
            * skip_until'dup'
            * lpeg.Cf(lpeg.Ct''
              * lpeg.Cg("dup"*white^-1*number*white^-1*binary_bytes*white)^0
              , rawset)
            * (lpeg.P"readonly"*white)^-1 * (lpeg.P"noaccess"*white)^-1*(lpeg.P"def"+"ND"+"|-")

-- lpeg.V(2) == dict_entries
local dict = skip_to_begin * lpeg.V(2) * white^-1 * 'end' * white * ('readonly' * white)^-1 * ('noaccess' * white)^-1 * def_like
local dict_entry = encoding + subrs +
                   '/' * lpeg.C'FontInfo' * dict +
                   lname   -- key
                 * white^-1
                 * anytype -- value
                 * ((white + anytype - (def_like + 'dict' + 'array') * -name)/0 * white^-1)^0 -- Sometimes we get Postscript code in between.
                 * def_like
local dict_entries = lpeg.P{
  lpeg.Cf(lpeg.Carg(1) * lpeg.Cg(white^-1*lpeg.V(3))^0, rawset),
  lpeg.Cf(lpeg.Ct'' * lpeg.Cg(white^-1*lpeg.V(3))^0, rawset),
  dict_entry,
}
local function parse_private(offset, str)
  local mydict, found
  offset = (skip_to_begin * lpeg.Cp()):match(str, offset)

  -- Scan the dictionary
  mydict, offset = (dict_entries*lpeg.Cp()):match(str, offset, {})
  return mydict, offset
end
local function continue_maintable(offset, str, mydict)
  mydict, offset = (dict_entries*lpeg.Cp()):match(str, offset, mydict)
  local found = (white^-1*lname):match(str, offset)
  if found == "Private" then -- Scanned separatly because it isn't always ended in a regular way
    mydict.Private, offset = parse_private(offset, str)
    return continue_maintable(offset, str, mydict)
  elseif found == "CharStrings" then -- This could be included in normal scanning, but it is our signal to terminate
    found, mydict.CharStrings, offset = (charstr*lpeg.Cp()):match(str, offset)
    return mydict
  else
    local newoffset = ((white+name)^1/0*lpeg.Cp()):match(str, offset)
    if newoffset and offset <= #str then
      return continue_maintable(newoffset, str, mydict)
    end
  end
  error[[Unable to read Type 1 font]]
end
local function parse_maintable(offset, str)
  local found
  offset = (skip_to_begin * lpeg.Cp()):match(str, offset)
  return continue_maintable(offset, str, {})
end

return function(data)
  local preface, private = string.unpack("<xxs4xxs4", data)
  private = decrypt(55665, 4, private)
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
