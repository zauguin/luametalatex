#!/bin/sh
luametatex --credits >/dev/null || exit 1
l3build install
ENGINE="$(which luametatex$EXE_EXT)"
ENGINE_DIR="$(dirname "$ENGINE")"
REPO="$(pwd)"
cd "$(dirname "$ENGINE")"
ln -fs luametatex$EXE_EXT luametaplain$EXE_EXT
ln -fs luametatex$EXE_EXT luametalatex$EXE_EXT
ln -fs luametatex$EXE_EXT luametalatex-dev$EXE_EXT
ln -fs "$REPO/luametaplain.lua" luametaplain.lua
ln -fs "$REPO/luametalatex.lua" luametalatex.lua
ln -fs "$REPO/luametalatex-dev.lua" luametalatex-dev.lua
cd "$(kpsewhich -var-value TEXMFLOCAL)"
mkdir -p web2c
if kpsewhich -var-value LUAINPUTS.luametalatex > /dev/null
then
  echo 'LUAINPUTS for luametalatex already set. In case of issues, please verify that the entries are correct.'
else
  cat >> web2c/texmf.cnf << "EOF"
TEXINPUTS.luametaplain    = $TEXMFDOTDIR;$TEXMF/tex/{luametaplain,luametatex,luatex,plain,generic,}//
TEXINPUTS.luametalatex    = $TEXMFDOTDIR;$TEXMF/tex/{luametalatex,lualatex,latex,luametatex,luatex,generic,}//
TEXINPUTS.luametalatex-dev= $TEXMFDOTDIR;$TEXMF/tex/{luametalatex,latex-dev,lualatex,latex,luametatex,luatex,generic,}//

LUAINPUTS.luametaplain    = $TEXMFDOTDIR;$TEXMF/scripts/{$progname,$engine,}/{lua,}//;$TEXMF/tex/{luametaplain,luametatex,luatex,plain,generic,}//
LUAINPUTS.luametalatex    = $TEXMFDOTDIR;$TEXMF/scripts/{$progname,$engine,}/{lua,}//;$TEXMF/tex/{luametalatex,lualatex,latex,luametatex,luatex,generic,}//
LUAINPUTS.luametalatex-dev= $TEXMFDOTDIR;$TEXMF/scripts/{$progname,$engine,}/{lua,}//;$TEXMF/tex/{luametalatex,latex-dev,lualatex,latex,luametatex,luatex,generic,}//
EOF
fi

if fmtutil-user --listcfg|grep -q '^luametalatex '
then
  echo 'luametalatex format already known. In case of issues, please verify that the entries are correct.'
else
  cat >> web2c/fmtutil.cnf << "EOF"
luametaplain luametatex language.dat,language.dat.lua --lua="$(kpsewhich luametaplain.lua)" luametaplain.ini
luametalatex luametatex language.dat,language.dat.lua --lua="$(kpsewhich luametalatex.lua)" luametalatex.ini
luametalatex-dev luametatex language.dat,language.dat.lua --lua="$(kpsewhich luametalatex-dev.lua)" luametalatex.ini
EOF
fi

echo INSTALLED
