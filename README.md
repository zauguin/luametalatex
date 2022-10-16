# (unofficial) LaTeX format for LuaMetaTeX

## Warning:
This code is in early stages of development and contains more bugs than features. _Do not_ expect it to be compatible with normal documents. Also later versions will contain many breaking changes.

## Prerequisites
You need an up-to-date TeX Live installation.

Currently LuaMetaLaTeX uses a patched version of LuaMetaTeX for which the source can be found at https://github.com/zauguin/luametatex and a support C library for which sources can be found at https://git.math.hamburg/marcel/luametalatex-c.
I recommend using prebuild binaries, but you can also build them yourself and then use them instead of using the installer in the installation instructions.

## How to install
  * Run `l3build install` in this directory to install the Lua files.
  * Additionally the engine and the support library for your platform is needed. Downlaod the right installer for your platform from https://lmltx.typesetting.eu/, extract it and run `installer`. If your current user does not have permission to write into the binary directory of your TeX Live installation (this is typically the case if you have a multi user installation) then you need to run the installer with administrator rights and pass the absolute path of this directory to the installer.
