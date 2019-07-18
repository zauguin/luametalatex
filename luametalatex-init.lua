do
  ffi.cdef[[
    typedef enum
    {
      kpse_gf_format,
      kpse_pk_format,
      kpse_any_glyph_format,
      kpse_tfm_format,
      kpse_afm_format,
      kpse_base_format,
      kpse_bib_format,
      kpse_bst_format,
      kpse_cnf_format,
      kpse_db_format,
      kpse_fmt_format,
      kpse_fontmap_format,
      kpse_mem_format,
      kpse_mf_format,
      kpse_mfpool_format,
      kpse_mft_format,
      kpse_mp_format,
      kpse_mppool_format,
      kpse_mpsupport_format,
      kpse_ocp_format,
      kpse_ofm_format,
      kpse_opl_format,
      kpse_otp_format,
      kpse_ovf_format,
      kpse_ovp_format,
      kpse_pict_format,
      kpse_tex_format,
      kpse_texdoc_format,
      kpse_texpool_format,
      kpse_texsource_format,
      kpse_tex_ps_header_format,
      kpse_troff_font_format,
      kpse_type1_format,
      kpse_vf_format,
      kpse_dvips_config_format,
      kpse_ist_format,
      kpse_truetype_format,
      kpse_type42_format,
      kpse_web2c_format,
      kpse_program_text_format,
      kpse_program_binary_format,
      kpse_miscfonts_format,
      kpse_web_format,
      kpse_cweb_format,
      kpse_enc_format,
      kpse_cmap_format,
      kpse_sfd_format,
      kpse_opentype_format,
      kpse_pdftex_config_format,
      kpse_lig_format,
      kpse_texmfscripts_format,
      kpse_lua_format,
      kpse_fea_format,
      kpse_cid_format,
      kpse_mlbib_format,
      kpse_mlbst_format,
      kpse_clua_format,
      kpse_ris_format,
      kpse_bltxml_format,
      kpse_last_format /* one past last index */
    } kpse_file_format_type;

    typedef enum {
      kpse_glyph_source_normal,
      kpse_glyph_source_alias,
      kpse_glyph_source_maketex,
      kpse_glyph_source_fallback_res,
      kpse_glyph_source_fallback
    } kpse_glyph_source_type;

    typedef enum {
      kpse_src_implicit,
      kpse_src_compile,
      kpse_src_texmf_cnf,
      kpse_src_client_cnf,
      kpse_src_env,
      kpse_src_x,
      kpse_src_cmdline
    } kpse_src_type;

    typedef struct {
      const char *name;
      unsigned dpi;
      kpse_file_format_type format;
      kpse_glyph_source_type source;
    } kpse_glyph_file_type;

    void *kpathsea_new(void);
    void kpathsea_set_program_name(void*, const char*, const char*);
    void kpathsea_init_prog(void*, const char*, unsigned, const char *, const char *);
    const char *kpathsea_find_file(void*, const char *, kpse_file_format_type, int);
    const char *kpathsea_find_glyph(void*, const char *, unsigned, kpse_file_format_type, kpse_glyph_file_type*);
    const char *kpathsea_brace_expand(void*, const char *);
    const char *kpathsea_path_expand(void*, const char *);
    const char *kpathsea_var_expand(void*, const char *);
    const char *kpathsea_var_value(void*, const char *);
    void kpathsea_set_program_enabled (void *, kpse_file_format_type, int, kpse_src_type);
    int kpathsea_in_name_ok(void*, const char *);
    int kpathsea_out_name_ok(void*, const char *);
    void kpathsea_finish(void*);
    const char *kpathsea_version_string;
  ]]
  local kpse_glyph_file_type = ffi.typeof'kpse_glyph_file_type'
  local type_remap = {
    -- These are the command line/LuaTeX names
    gf = "kpse_gf_format",
    pk = "kpse_pk_format",
    ["bitmap font"] = "kpse_any_glyph_format",
    tfm = "kpse_tfm_format",
    afm = "kpse_afm_format",
    base = "kpse_base_format",
    bib = "kpse_bib_format",
    bst = "kpse_bst_format",
    cnf = "kpse_cnf_format",
    ["ls-R"] = "kpse_db_format",
    fmt = "kpse_fmt_format",
    map = "kpse_fontmap_format",
    mem = "kpse_mem_format",
    mf = "kpse_mf_format",
    mfpool = "kpse_mfpool_format",
    mft = "kpse_mft_format",
    mp = "kpse_mp_format",
    mppool = "kpse_mppool_format",
    ["MetaPost support"] = "kpse_mpsupport_format",
    ocp = "kpse_ocp_format",
    ofm = "kpse_ofm_format",
    opl = "kpse_opl_format",
    otp = "kpse_otp_format",
    ovf = "kpse_ovf_format",
    ovp = "kpse_ovp_format",
    ["graphic/figure"] = "kpse_pict_format",
    tex = "kpse_tex_format",
    ["TeX system documentation"] = "kpse_texdoc_format",
    texpool = "kpse_texpool_format",
    ["TeX system sources"] = "kpse_texsource_format",
    ["PostScript header"] = "kpse_tex_ps_header_format",
    ["Troff fonts"] = "kpse_troff_font_format",
    ["type1 fonts"] = "kpse_type1_format",
    vf = "kpse_vf_format",
    ["dvips config"] = "kpse_dvips_config_format",
    ist = "kpse_ist_format",
    ["truetype fonts"] = "kpse_truetype_format",
    ["type42 fonts"] = "kpse_type42_format",
    ["web2c files"] = "kpse_web2c_format",
    ["other text files"] = "kpse_program_text_format",
    ["other binary files"] = "kpse_program_binary_format",
    ["mics fonts"] = "kpse_miscfonts_format",
    web = "kpse_web_format",
    cweb = "kpse_cweb_format",
    ["enc files"] = "kpse_enc_format",
    ["cmap files"] = "kpse_cmap_format",
    ["subfont definition files"] = "kpse_sfd_format",
    ["opentype fonts"] = "kpse_opentype_format",
    ["pdftex config"] = "kpse_pdftex_config_format",
    ["lig files"] = "kpse_lig_format",
    texmfscripts = "kpse_texmfscripts_format",
    lua = "kpse_lua_format",
    ["font feature files"] = "kpse_fea_format",
    ["cid maps"] = "kpse_cid_format",
    mlbib = "kpse_mlbib_format",
    mlbst = "kpse_mlbst_format",
    clua = "kpse_clua_format",
    ris = "kpse_ris_format",
    bltxml = "kpse_bltxml_format",
    -- Some additional aliases to make naming more consistant
    any_glyph = "kpse_any_glyph_format",
    db = "kpse_db_format",
    fontmap = "kpse_fontmap_format",
    mpsupport = "kpse_mpsupport_format",
    pict = "kpse_pict_format",
    texdoc = "kpse_texdoc_format",
    texsource = "kpse_texsource_format",
    tex_ps_header = "kpse_tex_ps_header_format",
    troff_font = "kpse_troff_font_format",
    type1 = "kpse_type1_format",
    dvips_config = "kpse_dvips_config_format",
    truetype = "kpse_truetype_format",
    type42 = "kpse_type42_format",
    web2c = "kpse_web2c_format",
    program_text = "kpse_program_text_format",
    program_binary = "kpse_program_binary_format",
    miscfonts = "kpse_miscfonts_format",
    enc = "kpse_enc_format",
    cmap = "kpse_cmap_format",
    sfd = "kpse_sfd_format",
    opentype = "kpse_opentype_format",
    pdftex_config = "kpse_pdftex_config_format",
    lig = "kpse_lig_format",
    fea = "kpse_fea_format",
    cid = "kpse_cid_format",
    -- And some other aliases
    eps = "kpse_pict_format",
    pfb = "kpse_type1_format",
    ttc = "kpse_truetype_format",
    ttf = "kpse_truetype_format",
    otf = "kpse_opentype_format",
    text = "kpse_program_text_format",
    binary = "kpse_program_binary_format",
  }
  local kpselib = ffi.load("kpathsea")
  local realarg0
  if arg[1]:sub(1,7) == "--arg0=" then
    realarg0 = arg[1]:sub(8)
  else
    local i = 0
    while arg[i] do
      realarg0 = arg[i]
      i = i-1
    end
  end
  local file_format = ffi.typeof'kpse_file_format_type'
  local NULL = ffi.new("const char*", nil)
  local function get_string(s) return s ~= NULL and ffi.string(s) end
  local function set_program_name (t, arg0, progname)
    kpselib.kpathsea_set_program_name(t.cdata, arg0 or realarg0, progname)
    return t
  end
  local methods = {
    init_prog = function(t, prefix, dpi, mode, fallback)
      kpselib.kpathsea_init_prog(t.cdata, prefix, dpi, mode, fallback)
    end,
    find_file = function(t, name, ...)
      local ftype, must_exist = "kpse_tex_format", 0
      for i=select('#', ...),1,-1 do
        local arg = select(i, ...)
        local argtype = type(arg)
        if argtype == "string" then
          ftype = arg
        elseif argtype == "number" then
          must_exist = arg
        elseif argtype == "boolean" then
          must_exist = arg and 1 or 0
        end
      end
      ftype = type_remap[ftype] or ftype
      if ftype == "kpse_gf_format" or ftype == "kpse_pk_format"
          or ftype == "kpse_any_glyph_format" then
        local glyph_file = kpse_glyph_file_type()
        local res = kpselib.kpathsea_find_glyph(t.cdata, name, must_exist, ftype, glyph_file)
        if res ~= NULL then
          return ffi.string(res), ffi.string(glyph_file.name), glyph_file.dpi, glyph_file.format, glyph_file.source
        end
      else
        return get_string(kpselib.kpathsea_find_file(t.cdata, name, ftype, must_exist > 0 and 1 or 0))
      end
    end,
    -- show_path = function(t, ftype)
    --   error [[Not yet implemented]]
    -- end,
    expand_braces = function(t, path)
      return get_string(kpselib.kpathsea_brace_expand(t.cdata, path))
    end,
    expand_path = function(t, path)
      return get_string(kpselib.kpathsea_path_expand(t.cdata, path))
    end,
    expand_var = function(t, var)
      return get_string(kpselib.kpathsea_var_expand(t.cdata, var))
    end,
    var_value = function(t, var)
      return get_string(kpselib.kpathsea_var_value(t.cdata, var))
    end,
    set_maketex = function(t, ftype, value, src)
      ftype = type_remap[ftype] or ftype
      kpselib.kpathsea_set_program_enabled(t.cdata, ftype, value and 1 or 0, src or "kpse_src_cmdline")
    end,
    finish = function(t)
      if t.cdata then
        kpselib.kpathsea_finish(t.cdata)
      end
    end,
  }
  local meta = {
    __index = methods,
    __gc = methods.finish,
  }
  local global_kpse = setmetatable({cdata = kpselib.kpathsea_new()}, meta)
  kpse = {
    set_program_name = function(...)
      set_program_name(global_kpse, ...)
    end,
    set_maketex = function(...)
      return global_kpse:set_maketex(...)
    end,
    init_prog = function(...)
      return global_kpse:init_prog(...)
    end,
    new = function(...)
      return set_program_name(setmetatable({cdata = kpselib.kpathsea_new()}, meta), ...)
    end,
    expand_braces = function(...)
      return global_kpse:expand_braces(...)
    end,
    expand_path = function(...)
      return global_kpse:expand_path(...)
    end,
    expand_var = function(...)
      return global_kpse:expand_var(...)
    end,
    var_value = function(...)
      return global_kpse:var_value(...)
    end,
    find_file = function(...)
      return global_kpse:find_file(...)
    end,
    version = function()
      return ffi.string(kpselib.kpathsea_version_string)
    end,
  }
end
--
-- unicode = {utf8 = utf8}
-- utf8.byte = utf8.codepoint
do
  local progname
  for _, a in ipairs(arg) do if a:sub(1,11) == "--progname=" then
    progname = a:sub(12)
  end end
  kpse.set_program_name(nil, progname)
end
package.searchers[2] = function(modname)
  local filename = kpse.find_file(modname, "kpse_lua_format", true)
  if not filename then
    return string.format("\n\tno file located through kpse for %s", modname)
  end
  local mod, msg = loadfile(filename)
  if msg then
    error(string.format("error loading module '%s' from file '%s':\n\t%s", modname, filename, msg))
  end
  return mod, filename
end
kpse.set_maketex("kpse_fmt_format", true)
bit32 = require'luametalatex-bit32'
kpse.init_prog("LUATEX", 400, "nexthi", nil)
status.init_kpse = 1
status.safer_option = 0
local read_tfm = require'luametalatex-font-tfm'
read_vf = require'luametalatex-font-vf'
font.read_tfm = read_tfm
font.read_vf = read_vf
local reserved_ids = -1
font.fonts = {}
function font.getfont(id)
  return font.fonts[id]
end
pdf = {
  getfontname = function(id) -- No font sharing
    return id
  end,
}
callback.register('define_font', function(name, size)
  if status.ini_version then
    reserved_ids = font.nextid()-1
    lua.prepared_code[#lua.prepared_code+1] = string.format("font.define(%i, font.read_tfm(%q, %i))", reserved_ids, name, size)
  end
  local f = read_tfm(name, size)
  font.fonts[font.nextid()-1] = f
  return f
end)
local olddefinefont = font.define
function font.define(i, f)
  if not f then
    f = i
    i = font.nextid(true)
  end
  font.fonts[i] = f
  return olddefinefont(i, f)
end
-- do
--   local register = callback.register
--   function callback.register(...)
--     print('callback.register', ...)
--     return register(...)
--   end
-- end
callback.register('find_log_file', function(name) return name end)
callback.register('find_data_file', function(name)  return kpse.find_file(name, 'kpse_tex_format', true) end)
callback.register('find_format_file', function(name) return kpse.find_file(name, 'kpse_fmt_format', true) end)
callback.register('show_warning_message', function()
  texio.write_nl('WARNING Tag: ' .. status.lastwarningtag)
  texio.write_nl(status.lastwarningstring)
end)
callback.register('show_error_message', function()
  if status.lasterrorcontext then
    texio.write_nl('ERROR Context: ' .. status.lasterrorcontext)
  end
  texio.write_nl(status.lasterrorstring)
end)
callback.register('pre_dump', function()
  -- for k,v in pairs(callback.list()) do print('CB', k,v) end
  lua.bytecode[1], msg = load("do local id "
                             .. "repeat id = font.nextid(true) "
                             .. "until id == " .. reserved_ids
                             .. " end "
                             .. table.concat(lua.prepared_code, ' '))
end)
if status.ini_version then
  lua.prepared_code = {}
  local code = package.searchers[2]('luametalatex-firstcode')
  if type(code) == "string" then error(string.format("Initialization code not found %s", code)) end
  lua.bytecode[2] = code
end
