#!/use/bin/env texlua

module = "luametalatex"

tdsroot = "luametatex" -- Would be luametalatex but we use the same files for luametaplain

installfiles = {"luameta*.lua", "luameta*.ini", "*.so", "*.dll", "*.dylib", "*texconfig.tex", "luametalatex-ltexpl-hook.tex", "luametalatex-*.sty"}
sourcefiles = {"luameta*.lua", "luameta*.ini", "*.so", "*.dll", "*.dylib", "*texconfig.tex", "luametalatex-ltexpl-hook.tex", "luametalatex-*.sty"}
