local function rewrite(t)
  local function handler(old, new)
    t[old] = t[old] or t[new]
    if not t[old] then print('!!!', old) end
    return handler
  end
  return handler
end

rewrite(tex)
  ('runtoks', 'runlocal')

rewrite(language)
  ('clear_hyphenation', 'clearhyphenation')
  ('clear_patterns', 'clearpatterns')

rewrite(node)
  ('copy_list', 'copylist')
  ('flush_list', 'flushlist')
  ('flush_node', 'flushnode')
  ('get_properties_table', 'getpropertiestable')
  ('has_field', 'hasfield')
  ('insert_after', 'insertafter')
  ('insert_before', 'insertbefore')
  ('is_node', 'isnode')

rewrite(node.direct)
  ('copy_list', 'copylist')
  ('effective_glue', 'effectiveglue')
  ('end_of_math', 'endofmath')
  ('find_attribute', 'findattribute')
  ('first_glyph', 'firstglyph')
  ('flush_list', 'flushlist')
  ('flush_node', 'flushnode')
  ('get_attribute', 'getattribute')
  ('get_properties_table', 'getpropertiestable')
  ('has_field', 'hasfield')
  ('has_glyph', 'hasglyph')
  ('insert_after', 'insertafter')
  ('insert_before', 'insertbefore')
  ('is_char', 'ischar')
  ('is_direct', 'isdirect')
  ('is_glyph', 'isglyph')
  ('is_node', 'isnode')
  ('is_zero_glue', 'iszeroglue')
  ('last_node', 'lastnode')
  ('make_extensible', 'makeextensible')
  ('mlist_to_hlist', 'mlisttohlist')
  ('protect_glyph', 'protectglyph')
  ('protect_glyphs', 'protectglyphs')
  ('traverse_char', 'traversechar')
  ('traverse_list', 'traverselist')
  ('traverse_id', 'traverseid')
  ('unprotect_glyph', 'unprotectglyph')
  ('unprotect_glyphs', 'unprotectglyphs')
  ('uses_font', 'usesfont')

rewrite(token)
  ('get_next', 'scannext')
  ('put_next', 'putnext')
  ('scan_argument', 'scanargument')
  ('scan_box', 'scanbox')
  ('scan_code', 'scancode')
  ('scan_csname', 'scancsname')
  ('scan_dimen', 'scandimen')
  ('scan_float', 'scanfloat')
  ('scan_glue', 'scanglue')
  ('scan_int', 'scaninteger')
  ('scan_keyword', 'scankeyword')
  ('scan_keywordcs', 'scankeywordcs')
  ('scan_real', 'scanreal')
  ('scan_string', 'scanstring')
  ('scan_token', 'scannextexpanded')
  ('scan_toks', 'scantoks')
  ('scan_word', 'scanword')
  ('set_lua', 'setlua')
  ('set_macro', 'setmacro')
  ('set_char', 'setchar')
  ('is_defined', 'isdefined')

do
  lang = {}
  for k,v in next, language do
    lang[k] = v
  end
  local patterns = language.patterns
  function lang.patterns(l, patt)
    if not patt then
      return patterns(l)
    end
    patt = patt:gsub('%s', ' ')
    return patterns(l, patt)
  end
end

do
  local l = lpeg or require'lpeg'
  local match = l.match
  local P = l.P
  local C = l.C
  local sub = string.sub
  local any = C(P(1)^0)
  local char = C(1)
  function string.explode(s, delim)
    delim = delim or ' +'
    if s == '' then
      return {s}
    else
      local patt
      if delim == '' then -- Split into individual characters
        patt = char
      else
        local del = P(sub(delim, 1, 1))
        if sub(delim, 2, 2) == '+' then
          local elem = C((1-del)^1)
          patt = del^0 * elem * (del^1 * elem)^0
        else
          local elem = C((1-del)^0)
          patt = elem * (del * elem)^0
        end
      end
      return {match(patt, s)}
    end
  end
end
