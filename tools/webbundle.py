#!/usr/bin/env python3
"""把 lua/(不含 golden / tools / check)打包成浏览器可 require 的模块表 → lua/web/sync5.bundle.js。

    python3 tools/webbundle.py

lua/web/index.html 用 Fengari(Lua 5.3 的 JS 实现)在浏览器里跑 Lua 镜像:逻辑全在 Lua, JS 只画画布与接鼠标。
这是参考渲染器, 也是 lua/app/CONTRACT.md 的可运行范例。生成物不进仓库(.gitignore)。
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUA = os.path.join(ROOT, "lua")
OUT = os.path.join(LUA, "web", "sync5.bundle.js")
SKIP_DIRS = {"golden", "tools", "web"}
SKIP_FILES = {"check.lua", "selftest.lua"}


def main():
    mods = {}
    for dirpath, dirnames, filenames in os.walk(LUA):
        rel = os.path.relpath(dirpath, LUA)
        top = rel.split(os.sep)[0] if rel != "." else ""
        if top in SKIP_DIRS:
            continue
        for fn in sorted(filenames):
            if not fn.endswith(".lua") or (rel == "." and fn in SKIP_FILES):
                continue
            path = os.path.join(dirpath, fn)
            name = fn[:-4] if rel == "." else rel.replace(os.sep, ".") + "." + fn[:-4]
            with open(path, encoding="utf-8") as fh:
                mods[name] = fh.read()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write("// 由 tools/webbundle.py 生成 —— 手改无效\nwindow.SYNC5_SOURCES = ")
        fh.write(json.dumps(mods, ensure_ascii=False))
        fh.write(";\n")
    print("webbundle: %d modules → lua/web/sync5.bundle.js (%d KB)" % (len(mods), os.path.getsize(OUT) // 1024))
    return 0


if __name__ == "__main__":
    sys.exit(main())
