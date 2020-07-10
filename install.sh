#!/bin/sh
ENGINE="$(which luametatex$EXE_EXT)"
ENGINE_DIR="$(dirname "$ENGINE")"
REPO="$(pwd)"
cd "$(dirname "$ENGINE")"
ln -s luametatex$EXE_EXT luametaplain$EXE_EXT
ln -s luametatex$EXE_EXT luametalatex$EXE_EXT
ln -s luametatex$EXE_EXT luametalatex-dev$EXE_EXT
ln -s "$REPO/luametaplain.lua" .
ln -s "$REPO/luametalatex.lua" .
ln -s "$REPO/luametalatex-dev.lua" .
while [ ! -d texmf ] && [ ! -d texmf-local ]
do
  LASTDIR="$(pwd)"
  cd ..
  if [ "$(pwd)" == "$LASTDIR" ]
  then
    exit 1
  fi
done
if [ -d texmf ]
then cd texmf
else cd texmf-local
fi
mkdir -p tex/luameta{plain,latex{,-dev}}
ln -s "$REPO" tex/luametaplain/base
ln -s "$REPO" tex/luametalatex/base
ln -s "$REPO" tex/luametalatex-dev/base
mkdir -p web2c
cat >> web2c/texmf.cnf << "EOF"
TEXINPUTS.luametaplain    = $TEXMFDOTDIR;$TEXMF/tex/{luametaplain,luametatex,luatex,plain,generic,}//
TEXINPUTS.luametalatex    = $TEXMFDOTDIR;$TEXMF/tex/{luametalatex,lualatex,latex,luametatex,luatex,generic,}//
TEXINPUTS.luametalatex-dev= $TEXMFDOTDIR;$TEXMF/tex/{luametalatex,latex-dev,lualatex,latex,luametatex,luatex,generic,}//

LUAINPUTS.luametaplain    = $TEXMFDOTDIR;$TEXMF/scripts/{$progname,$engine,}/{lua,}//;$TEXMF/tex/{luametaplain,luametatex,luatex,plain,generic,}//
LUAINPUTS.luametalatex    = $TEXMFDOTDIR;$TEXMF/scripts/{$progname,$engine,}/{lua,}//;$TEXMF/tex/{luametalatex,lualatex,latex,luametatex,luatex,generic,}//
LUAINPUTS.luametalatex-dev= $TEXMFDOTDIR;$TEXMF/scripts/{$progname,$engine,}/{lua,}//;$TEXMF/tex/{luametalatex,latex-dev,lualatex,latex,luametatex,luatex,generic,}//
EOF

cat >> web2c/fmtutil.cnf << "EOF"
luametaplain luametatex language.dat,language.dat.lua --lua="$(kpsewhich luametalatex.lua)" luametaplain.ini
luametalatex luametatex language.dat,language.dat.lua --lua="$(kpsewhich luametalatex.lua)" luametalatex.ini
luametalatex-dev luametatex language.dat,language.dat.lua --lua="$(kpsewhich luametalatex-dev.lua)" luametalatex.ini
EOF
echo INSTALLED
