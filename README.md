# (unofficial) LaTeX format for LuaMetaTeX

## Warning:
This code is in early stages of development and contains more bugs than features. _Do not_ expect it to be compatible with normal documents. Also later versions will contain many breaking changes.

## Prerequisites
You need an up-to-date TeX Live installation and the latest version of LuaMetaTeX.

Additionally a special library version of LuaTeX's kpathsea Lua binding is needed which is provided as a binary for Linux x64. For other platforms you might have to compile it yourself. Drop me a line if you need any instructions. (The source can be found under https://github.com/zauguin/luametalatex-kpse)

## How to install (automatically)
Obtain `luametatex` from ConTeXt, drop the binary into the same location where your `luatex` binary is installed and then run `install.sh`.

## How to install (manually)
Obtain `luametatex` from ConTeXt, drop the binary into the same location where your `luatex` binary is installed and copy (or sym-link) the file `luametalatex.lua` into the same directory. Additionally create a sym-link `luametalatex` to `luametatex` in the same directory. Then copy (or sym-link) this entire repo to `.../texmf-local/tex/lualatex/luametalatex`. 

Finally add the line
```
luametalatex luametatex language.dat,language.dat.lua --lua="$(kpsewhich luametalatex.lua)" luametalatex.ini
```
to your local `fmtutil.cnf` and configure paths for luametalatex in your `texmf.cnf`. Then you should be able to run `fmtutil-sys --byfmt luametalatex` to generate the format.

If this worked you can built (simple) LaTeX documents using the command `luametalatex`.

You can then repeat the same instructions with `luametalatex-dev` and `luametaplain` to also get access to development and plain TeX formats
