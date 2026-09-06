#!/usr/bin/env python3
"""data/*.json → lua/data/<name>.lua(docs/design/mirror.md §4)。

    python3 tools/luagen.py            # 重生成全部
    python3 tools/luagen.py --check    # 比对「重生成 == 已提交」, 不一致退 1(进秒级预检行)

生成物是仪器输出, 手改无效。语义:JSON 数组 → Lua 序列(1 基), 对象 → 字符串键表(键序保持),
int / float 按 JSON 原样(3 与 3.0 不互转), 字符串按 UTF-8 原样写入(只转义 \\ " 换行 制表 控制字符)。
⚠ 数组里的 null 会截断 Lua 序列 —— 目前 data/ 无 null(已核实);出现时这里直接报错而不是静默写 nil。
"""
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "data")
DST = os.path.join(ROOT, "lua", "data")
HEADER = "-- 由 tools/luagen.py 从 data/%s 生成 —— 仪器输出, 手改无效(docs/design/mirror.md §4)\n"


def lstr(s):
    out = ['"']
    for ch in s:
        o = ord(ch)
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif o < 32 or o == 127:
            out.append("\\%03d" % o)
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def emit(v, ind, path):
    pad = "\t" * ind
    if v is None:
        raise SystemExit("luagen: null at %s —— Lua 序列容不下 nil, 先在 JSON 里消掉它" % path)
    if v is True:
        return "true"
    if v is False:
        return "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        r = repr(v)
        if r in ("inf", "-inf", "nan"):
            raise SystemExit("luagen: non-finite float at %s" % path)
        return r
    if isinstance(v, str):
        return lstr(v)
    if isinstance(v, list):
        if not v:
            return "{}"
        items = [pad + "\t" + emit(e, ind + 1, "%s[%d]" % (path, i)) + ",\n" for i, e in enumerate(v)]
        return "{\n" + "".join(items) + pad + "}"
    if isinstance(v, dict):
        if not v:
            return "{}"
        items = [pad + "\t[" + lstr(k) + "] = " + emit(e, ind + 1, "%s.%s" % (path, k)) + ",\n" for k, e in v.items()]
        return "{\n" + "".join(items) + pad + "}"
    raise SystemExit("luagen: unsupported type %s at %s" % (type(v).__name__, path))


def render(name, obj):
    return HEADER % name + "return " + emit(obj, 0, name) + "\n"


def main():
    check = "--check" in sys.argv
    files = sorted(glob.glob(os.path.join(SRC, "*.json")))
    bad = []
    os.makedirs(DST, exist_ok=True)
    expected = set()
    for f in files:
        name = os.path.basename(f)
        stem = name[:-5]
        with open(f, encoding="utf-8") as fh:
            obj = json.load(fh)
        body = render(name, obj)
        out = os.path.join(DST, stem + ".lua")
        expected.add(stem + ".lua")
        if check:
            cur = open(out, encoding="utf-8").read() if os.path.exists(out) else None
            if cur != body:
                bad.append(stem + ".lua")
        else:
            with open(out, "w", encoding="utf-8") as fh:
                fh.write(body)
    # 孤儿:data/ 里删了的文件, lua/data/ 里还躺着
    for g in glob.glob(os.path.join(DST, "*.lua")):
        if os.path.basename(g) not in expected:
            if check:
                bad.append(os.path.basename(g) + " (orphan)")
            else:
                os.remove(g)
    if check:
        if bad:
            print("luagen --check: 与 data/*.json 不一致:", ", ".join(bad), "—— 跑 python3 tools/luagen.py")
            return 1
        print("luagen --check: %d files in sync" % len(files))
        return 0
    print("luagen: wrote %d files to lua/data/" % len(files))
    return 0


if __name__ == "__main__":
    sys.exit(main())
