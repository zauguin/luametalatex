#!/use/bin/env texlua

module = "luametalatex"

tdsroot = "luametatex" -- Would be luametalatex but we use the same files for luametaplain

installfiles = {"luameta*.lua", "luameta*.ini", "*.so", "*.dll", "luametatexconfig.tex", "luametalatex-ltexpl-hook.tex"}
sourcefiles = {"luameta*.lua", "luameta*.ini", "*.so", "*.dll", "luametatexconfig.tex", "luametalatex-ltexpl-hook.tex"}
