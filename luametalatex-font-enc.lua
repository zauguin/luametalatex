local white = (lpeg.S'\0\9\10\12\13\32' + '%' * (1 - lpeg.S'\r\n')^0)^1
local regular = 1-lpeg.S'()<>[]{}/%\0\9\10\12\13\32'
local name = lpeg.C(regular^1)
local lname = '/' * name / 1
local namearray = lpeg.Ct('['*white^0*lpeg.Cg(lname*white^0, 0)^-1*(lname*white^0)^0*']')
local encfile = white^0*lname*white^0*namearray*white^0*'def'*white^0*-1
return function(filename)
  local file = io.open(filename, 'r')
  local name, encoding = encfile:match(file:read'a')
  file:close()
  return encoding, name
end
