local callbacks = require'luametalatex-callbacks'

local direct = node.direct
local todirect = direct.todirect
local tonode = direct.tonode
local mlisttohlist = direct.mlisttohlist

local mapping = {
  display = 0,
  crampeddisplay = 0,
  text = 0,
  crampedtext = 0,
  script = 1,
  crampedscript = 1,
  scriptscript = 2,
  crampedscriptscript = 2,
}
local style_names = {
  D = 'display',
  T = 'text',
  S = 'script',
  SS = 'scriptscript',
}
local style = lpeg.Cg(lpeg.S'DTS' * lpeg.P'S'^-1 / style_names * lpeg.C"'"^-1)
local styles = lpeg.Cf(lpeg.Ct'' * style * (', ' * style)^0, function(t, name, cramped) t[(cramped and 'cramped' or '') .. name] = true return t end)
local splitted_styles = setmetatable({}, {__index = function(t, names)
  local splitted
  if #names == 0 then
    splitted = t["D, D', T, T', S, S', SS, SS'"]
  else
    splitted = styles:match(names)
  end
  t[names] = splitted
  return splitted
end})
local function mathfamily(fam)
  local fonts = {}
  return function(i, style)
    style = style or 'text'
    local f = fonts[style]
    if not f then
      f = tex.getfontoffamily(fam, mapping[style])
      fonts[style] = f
    end
    local ok, value = pcall(font.getfontdimen, f, i)
    if ok then return value end
    return nil
  end
end
local function set_math(style)
  return function(name, value, styles)
    styles = splitted_styles[styles]
    value = value // 1
  
    if styles[style] and not tex.getmath(name, style) then
      tex.setmath('local', name, style, value)
    end
  end
end

local abs = math.abs

local function set_math_param_fallbacks()
  local mathnolimitsmode = tex.mathnolimitsmode
  tex.mathnolimitsmode = 1

  for _, style in pairs{'display', 'text', 'script', 'scriptscript'} do
    local mathsy = mathfamily(2, style)
    local mathex = mathfamily(3, style)
    local math_x_height = mathsy(5)
    local math_quad     = mathsy(6)
    local num1          = mathsy(8)
    local num2          = mathsy(9)
    local num3          = mathsy(10)
    local denom1        = mathsy(11)
    local denom2        = mathsy(12)
    local sup1          = mathsy(13)
    local sup2          = mathsy(14)
    local sup3          = mathsy(15)
    local sub1          = mathsy(16)
    local sub2          = mathsy(17)
    local sup_drop      = mathsy(18)
    local sub_drop      = mathsy(19)
    local delim1        = mathsy(20)
    local delim2        = mathsy(21)
    local axis_height   = mathsy(22)

    local default_rule_thickness = mathex(8)
    local big_op_spacing1        = mathex(9)
    local big_op_spacing2        = mathex(10)
    local big_op_spacing3        = mathex(11)
    local big_op_spacing4        = mathex(12)
    local big_op_spacing5        = mathex(13)

    for _, style in pairs{style, 'cramped' .. style} do
      local set_math = set_math(style)
      set_math('axis', axis_height, "") 
      set_math('fractiondelsize', delim1, "D, D'") 
      set_math('fractiondelsize', delim2, "T, T', S, S', SS, SS'") 
      set_math('fractiondenomdown', denom1, "D, D'") 
      set_math('fractiondenomdown', denom2, "T, T', S, S', SS, SS'") 
      set_math('fractiondenomvgap', 3*default_rule_thickness, "D, D'") 
      set_math('fractiondenomvgap', default_rule_thickness, "T, T', S, S', SS, SS'") 
      set_math('fractionnumup', num1, "D, D'") 
      set_math('fractionnumup', num2, "T, T', S, S', SS, SS'") 
      set_math('fractionnumvgap', 3*default_rule_thickness, "D, D'") 
      set_math('fractionnumvgap', default_rule_thickness, "T, T', S, S', SS, SS'") 
      set_math('fractionrule', default_rule_thickness, "") 
      -- set_math('skewedfractionhgap', math_quad/2, "") 
      -- set_math('skewedfractionvgap', math_x_height, "") 
      set_math('skewedfractionhgap', 0, "") 
      set_math('skewedfractionvgap', 0, "") 
      set_math('limitabovebgap', big_op_spacing3, "") 
      set_math('limitabovekern', big_op_spacing5, "") 
      set_math('limitabovevgap', big_op_spacing1, "") 
      set_math('limitbelowbgap', big_op_spacing4, "") 
      set_math('limitbelowkern', big_op_spacing5, "") 
      set_math('limitbelowvgap', big_op_spacing2, "") 
      set_math('overdelimitervgap', big_op_spacing1, "") 
      set_math('overdelimiterbgap', big_op_spacing3, "") 
      set_math('underdelimitervgap', big_op_spacing2, "") 
      set_math('underdelimiterbgap', big_op_spacing4, "") 
      set_math('overbarkern', default_rule_thickness, "") 
      set_math('overbarrule', default_rule_thickness, "") 
      set_math('overbarvgap', 3*default_rule_thickness, "") 
      set_math('quad', math_quad, "") 
      set_math('radicalkern', default_rule_thickness, "") 
      set_math('radicalvgap', default_rule_thickness+abs(math_x_height)/4, "D, D'") 
      set_math('radicalvgap', default_rule_thickness+abs(default_rule_thickness)/4, "T, T', S, S', SS, SS'") 
      set_math('spaceafterscript', tex.scriptspace, "") 
      set_math('stackdenomdown', denom1, "D, D'") 
      set_math('stackdenomdown', denom2, "T, T', S, S', SS, SS'") 
      set_math('stacknumup', num1, "D, D'") 
      set_math('stacknumup', num3, "T, T', S, S', SS, SS'") 
      set_math('stackvgap', 7*default_rule_thickness, "D, D'") 
      set_math('stackvgap', 3*default_rule_thickness, "T, T', S, S', SS, SS'") 
      set_math('subshiftdown', sub1, "") 
      set_math('subsupshiftdown', sub1, "") -- ! In LuaTeX defaults to subshiftdown, done here only for legacy.
      set_math('subshiftdrop', sub_drop, "") 
      set_math('subtopmax', abs(math_x_height*4)/5, "") 
      set_math('subsupvgap', 4*default_rule_thickness, "") 
      set_math('supbottommin', abs(math_x_height/4), "") 
      set_math('supshiftdrop', sup_drop, "") 
      set_math('supshiftup', sup1, "D") 
      set_math('supshiftup', sup2, "T, S, SS,") 
      set_math('supshiftup', sup3, "D', T', S', SS'") 
      set_math('supsubbottommax', abs(math_x_height*4)/5, "") 
      set_math('underbarkern', default_rule_thickness, "") 
      set_math('underbarrule', default_rule_thickness, "") 
      set_math('underbarvgap', 3*default_rule_thickness, "") 
      set_math('connectoroverlapmin', 0, "") 

      set_math('accentbaseheight', math_x_height, "") -- Was specific to accent font in LuaTeX and earlier

      set_math('accentbaseheight', math_x_height, "") -- Was specific to accent font in LuaTeX and earlier

      -- HACK to get legacy like nolimits placement on italic operators
      if mathnolimitsmode == 0 then
        set_math('nolimitsupfactor', 1000, "") -- HACK
        set_math('nolimitsubfactor', 0, "") -- HACK
      elseif mathnolimitsmode == 1 then -- Here the font should normally have set them, we just change the default a bit
        set_math('nolimitsupfactor', 1000, "")
        set_math('nolimitsubfactor', 1000, "")
      elseif mathnolimitsmode == 2 then
        set_math('nolimitsupfactor', 1000, "")
        set_math('nolimitsubfactor', 1000, "")
      elseif mathnolimitsmode == 3 then
        set_math('nolimitsupfactor', 1000, "")
        set_math('nolimitsubfactor', 500, "")
      elseif mathnolimitsmode == 4 then
        set_math('nolimitsupfactor', 1500, "")
        set_math('nolimitsubfactor', 500, "")
      else
        set_math('nolimitsupfactor', 1000, "")
        set_math('nolimitsubfactor', mathnolimitsmode > 15 and 1000 - mathnolimitsmode or 1000, "")
      end
    end
  end
end

local function default_mlist_to_hlist(head, style, penalties, beginclass, endclass)
  return tonode(mlisttohlist(todirect(head), style, penalties, beginclass, endclass))
end

function callbacks.mlist_to_hlist(head, style, penalties, beginclass, endclass, mathlevel)
  set_math_param_fallbacks()
  return (callbacks.mlist_to_hlist or default_mlist_to_hlist)(head, style, penalties, beginclass, endclass, mathlevel)
end
callbacks.__freeze('mlist_to_hlist', true)
