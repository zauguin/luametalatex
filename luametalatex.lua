local format = os.selfname -- or os.selfcore, I couldn't find a difference yet
local ourname = arg[0] -- This might not be os.selfarg[0]
-- We want to drop arg[0] aka. ourname from the arguments to avoid recursion
if os.selfarg[0] == ourname then
  ourname = nil
end
for i, a in ipairs(os.selfarg) do
  if a == ourname then -- Avoid recursion
    table.remove(os.selfarg, i)
    ourname = nil
    a = os.selfarg[i]
  end
  if a == "--" then break end -- This convention is not respected by luametatex itself
  -- LuaMetaTeX needs -- to introduce parameters,
  -- but fmtutil uses just -. Let's rewrite this on the fly:
  a = a:gsub("^%-%-?", "--")
  os.selfarg[i] = a
  if a:sub(1, 11) == "--progname=" then
    format = a:sub(12)
  end
end
os.setenv("engine", status.luatex_engine)
local kpse_call = io.popen(string.format("kpsewhich -progname %s -format lua -must-exist %s-init.lua", format, format))
local file = kpse_call:read()
if not kpse_call:close() then
  error(file)
end
local args = os.selfarg[1] and " \"" .. table.concat(os.selfarg, "\" \"") .. "\"" or ""
os.exit(os.execute(string.format("luametatex \"--lua=%s\" --arg0=\"%s\"%s", file, os.selfarg[0], args)))
