local format = os.selfname -- or os.selfcore, I couldn't find a difference yet
local ourname = arg[0] -- This might not be os.selfarg[0]
-- We want to drop arg[0] aka. ourname from the arguments to avoid recursion
if os.selfarg[0] == ourname then
  ourname = nil
end
local run

local arg_pattern, late_arg_pattern do
  local l = lpeg or require'lpeg'
  -- We intepret two arguments directly
  local early_args = 'run' * l.Cmt(l.P'=' + -1, function() run = true return true end)
                   + 'progname=' * l.Cmt(0, function(s, off) format = s:sub(off) return true end)
  -- LuaMetaTeX needs -- to introduce parameters,
  -- but fmtutil uses just -. Let's rewrite this on the fly:
  local maybe_option = ('-' * ('-' + l.Cc'-') * #(early_args^-1))^-1
  local quote = l.Cc(os.type == 'windows' and '"' or "'")
  local escape
  if os.type == 'windows' then
    -- Windows: " -> "^"" The ^ is for cmd escaping, the """ is for command line splitting escaping,
    -- backslashes still have to be escaped, but only in front of " or \
    -- WARNING: This works with luametatex's argument splitting, but don't generally rely
    -- on it for other Windows programs. There are two standard Windows ways which are incompatible...
    escape = '\\' * #l.S'\\"' * l.Cc'\\' + '"' * l.Cc'^""' + 1
  else
    -- POSIX: We escape with single quotes, so only single quotes need escaping
    escape = "'" * l.Cc"\\''" + 1
  end
  arg_pattern = l.Cs(l.Cc' ' * maybe_option * quote * escape^0 * quote)
  late_arg_pattern = l.Cs(l.Cc' ' * quote * escape^0 * quote)
end

for i, a in ipairs(os.selfarg) do
  if a == ourname then -- Avoid recursion
    table.remove(os.selfarg, i)
    ourname = nil
    a = os.selfarg[i]
  end
  if a == "--" then arg_pattern = late_arg_pattern end -- This convention is not respected by luametatex itself
  os.selfarg[i] = arg_pattern:match(a)
end
os.setenv("engine", status.luatex_engine)

local kpse_call = io.popen(string.format("kpsewhich -progname%s -format lua -all -must-exist%s-init.lua", late_arg_pattern:match(format), late_arg_pattern:match(format)))
local file
repeat
  file = kpse_call:read()
until not file:match('^%.')
if not kpse_call:close() then
  error(file)
end

local geterrorcode
if os.type == 'windows' then
  function geterrorcode(ec) return ec end
else
  function geterrorcode(ec) return ec & 0xFF == 0 and ec >> 8 or 0xFF end
end

local firstargs = string.format("luametatex%s%s", late_arg_pattern:match('--lua=' .. file), late_arg_pattern:match('--arg0=' .. os.selfarg[0]))
local args = table.concat(os.selfarg)
if run then -- The user wants to take care of everything
  os.exit(geterrorcode(os.execute(firstargs .. args)))
else
  for i = 1, 5 do
    local status = geterrorcode(os.execute(string.format("%s --run=%i%s", firstargs, i, args)))
    if status ~= 75 then
      os.exit(status)
    end
  end
  os.exit(75)
end
