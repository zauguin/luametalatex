# (unofficial) LaTeX format for LuaMetaTeX

## Warning:
This code is in early stages of development and contains more bugs than features. _Do not_ expect it to be compatible with normal documents. Also later versions will contain many breaking changes.

## Prerequisites
You need an up-to-date TeX Live installation and the latest version of LuaMetaTeX. Additionally a current development version of luaotfload is required. (Of course, luaotfload is not necessary if you only want to use `luametaplain` without Unicode fonts.)

IF you are not using Linux x64 or Windows x64, you additionally need to compile a special library version of LuaTeX's kpathsea Lua binding. The source is available under https://github.com/zauguin/luametalatex-kpse . After compiling, the resulting `kpse.so` or `kpse.dll` has to be stored in the main directory of luametalatex (the same directory where `luametalatex-init.lua` is stored)

## How to install (automatically)
Obtain `luametatex` from ConTeXt, drop the binary into the same location where your `luatex` binary is installed and then run `install.sh`.

## How to install (manually)
Obtain `luametatex` from ConTeXt, drop the binary into the same location where your `luatex` binary is installed and copy (or sym-link) the file `luametalatex.lua` into the same directory. Additionally create a sym-link `luametalatex` to `luametatex` in the same directory. Then install `luametalatex` into your texmf tree by running `l3build install` in this repository.

Finally add the lines (on Windows, `$(luametalatex.lua)` has to be replaced by the full path to `luametalatex.lua`)
```
luametalatex luametatex language.dat,language.dat.lua --lua="$(kpsewhich luametalatex.lua)" luametalatex.ini
```
to your local `fmtutil.cnf` and configure paths for luametalatex in your `texmf.cnf`. Then you should be able to run `mktexlsr` followed by `fmtutil-sys --byfmt luametalatex` to generate the format.

If this worked you can built (simple) LaTeX documents using the command `luametalatex`.

You can then repeat the same instructions with `luametalatex-dev` and `luametaplain` to also get access to development and plain TeX formats
