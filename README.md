# (unofficial) LaTeX format for LuaMetaTeX

## Warning:
This code is in early stages of development and contains more bugs than features. _Do not_ expect it too be compatible with normal documents yet. Also later versions will contain many breaking changes.

## Prerequisites
You need an up-to-date TeX Live installation and the latest, not yet released, development versions of [lualibs (branch v2.6701-2019-07-04)](https://github.com/u-fischer/lualibs/tree/v2.6701-2019-07-04) and [luaotfload (branch v2.9901-2019-07-04-PR72)](https://github.com/u-fischer/luaotfload/tree/v2.9901-2019-07-04-PR72).

Also we use a FFI binding of kpathsea, so you need `libkpathsea.so` in you system paths.
If you have installed TeX Live through your package manager this shouldn't be a problem, even if you do not actually use that version.
Otherwise you might have to compile it yourself.

## How to install
Obtain `luametatex` from ConTeXt, drop the binary into the same location where your `luatex` binary is installed and copy (or sym-link) the file `luametalatex.lua` into the same directory. Additionally create a sym-link `luametalatex` to `luametatex` in the same directory. Then copy (or sym-link) this entire repo to `.../texmf-local/tex/lualatex/luametalatex`. 

Finally add the line
```
luametalatex luametatex language.dat,language.dat.lua --lua="$(kpsewhich luametalatex.lua)" luametalatex.ini
```
to your local `fmtutil.cnf`. Then you should be able to run `fmtutil-sys --byfmt luametalatex` to generate the format.

If this worked you can built (simple) LaTeX documents using the command `luametalatex`.
