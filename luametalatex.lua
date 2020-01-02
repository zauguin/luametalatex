-- Some helpers based on Penlight
local absdir, dirsep
do
  local sep = package.config:sub(1,1)
  local is_windows = sep == "\\"
  dirsep = lpeg.S(is_windows and '\\/' or '/')
  local anchor_pattern = lpeg.Cs(is_windows
    and lpeg.P'\\\\' + dirsep/'\\' + 1*lpeg.P':'*dirsep^-1/'\\'
    or  lpeg.P'//' + dirsep^1/'/')
  function isabs(P)
    return P:sub(1,1) == '/' or (is_windows and (P:sub(1,1)=='\\' or P:sub(2,2)==':'))
  end
  local insert, remove, concat = table.insert, table.remove, table.concat
  function normpath(P)
    -- Split path into anchor and relative path.
    local anchor, P = ((anchor_pattern + lpeg.Cc'') * lpeg.C(lpeg.P(1)^0)):match(P)
    if is_windows then
      P = P:gsub('/','\\')
    end
    local parts = {}
    for part in P:gmatch('[^'..sep..']+') do
      if part == '..' then
        if #parts ~= 0 and parts[#parts] ~= '..' then
          remove(parts)
        else
          insert(parts, part)
        end
      elseif part ~= '.' then
        insert(parts, part)
      end
    end
    P = anchor..concat(parts, sep)
    if P == '' then P = '.' end
    return P
  end
  function join(p1,p2,...)
    if select('#',...) > 0 then
      local p = join(p1,p2)
      return join(p, ...)
    end
    if isabs(p2) then return p2 end
    local endc = p1:sub(#p1,#p1)
    if endc ~= "/" and (not is_windows or endc ~= "\\") and endc ~= "" then
      p1 = p1..sep
    end
    return p1..p2
  end
  function absdir(P,pwd)
    local use_pwd = pwd ~= nil
    pwd = pwd or lfs.currentdir()
    if not isabs(P) then
      P = join(pwd,P)
    elseif is_windows and not use_pwd and P:sub(2,2) ~= ':' and P:sub(2,2) ~= '\\' then
      P = pwd:sub(1,2)..P -- attach current drive to path like '\\fred.txt'
    end
    return normpath(P) .. sep
  end
end
-- Who are we anyway?
local format = os.selfname -- or os.selfcore, I couldn't find a difference yet
local ourname = arg[0] -- This might not be os.selfarg[0]
if os.selfarg[0] == ourname then
  ourname = nil
end
for i, a in ipairs(os.selfarg) do
  -- LuaMetaTeX needs -- to introduce parameters,
  -- but fmtutil uses just -. Let's rewrite this on the fly:
  if a == ourname then -- Avoid recursion
    table.remove(os.selfarg, i)
    ourname = nil
    a = os.selfarg[i]
  end
  if a == "--" then break end
  a = a:gsub("^%-%-?", "--")
  os.selfarg[i] = a
  if a:sub(1, 11) == "--progname=" then
    format = a:sub(12)
  elseif a == '--ini' then
    is_initex = true
  end
end
local dir = absdir(os.selfdir)
local dirseparators = {((lpeg.S'\\/'^1 + 1 * lpeg.P':' * lpeg.S'\\/'^-1) * lpeg.Cp() * ((1-lpeg.S'\\/')^0*lpeg.S'\\/'*lpeg.Cp())^0):match(dir)}
-- First step: Find our actual format.
local init_script = format .. "-init.lua"
local texmf_dir = "tex/luametalatex/" .. format .. '/' .. init_script
local paths = {
  init_script,
  "share/texmf-local/" .. texmf_dir,
  "share/texmf-dist/" .. texmf_dir,
  "share/texmf/" .. texmf_dir,
  "texmf-local/" .. texmf_dir,
  "texmf-dist/" .. texmf_dir,
  "texmf/" .. texmf_dir,
}
for i = #dirseparators, 1, -1 do
  dir = dir:sub(1, dirseparators[i] - 1)
  for _, subdir in ipairs(paths) do
    local full_path = dir .. subdir
    local attr = lfs.attributes(full_path)
    if attr then
      dir = full_path
      goto FOUND
    end
  end
end
error[[CRITICAL: Initialization script not found]]
::FOUND::
-- table.insert(arg, 1, "--lua=" .. dir)
-- table.insert(arg, 1, "luametatex")
-- arg[0] = nil
-- local _, msg = os.exec(arg)
-- error(msg)
os.setenv("engine", status.luatex_engine)
local ret_value
if is_initex then
  ret_value = os.execute(string.format("luametatex \"--lua=%s\" --arg0=\"%s\" \"%s\"", dir, os.selfarg[0], table.concat(os.selfarg, "\" \"")))
else
  ret_value = os.execute(string.format("luametatex \"--fmt=%s\" \"--lua=%s\" --arg0=\"%s\" \"%s\"", format, dir, os.selfarg[0], table.concat(os.selfarg, "\" \"")))
end
os.exit(x)
