#!/usr/bin/env python3
"""覆盖门(docs/design/mirror.md §7):core/*.gd 的每个文件、每个公开函数在 lua/core/ 里都要有同名孪生。

    python3 tools/mirror.py --check     # 缺一个红(退 1);进秒级预检行
    python3 tools/mirror.py             # 同上, 另打印覆盖清单

判据是机械的:`^(static )?func name(` ↔ `function Class.name(` / `function Class:name(` / `Class.name = function`。
⚠ 这道门守的是「规则在游戏里、不在镜像里、而且不报错」—— 本项目栽过五次的形状在这条线上的翻版。
豁免与清单写在下面的表里, 每条都要有理由;别顺手加豁免。
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 整文件豁免(理由必填)
SKIP_FILES = {
    "uplink.gd": "回传通道缺省关、等端点;镜像不搬(mirror.md §2)",
}
# 按文件的函数豁免:{文件: {函数名: 理由}}
SKIP_FUNCS = {
    "db.gd": "只搬访问器 —— 校验是测试期门禁, 数据在 Godot 侧过检后共享(mirror.md §2)",
    "save.gd": {
        "_data": "文件 I/O 由注入的 storage 承担", "_flush": "同上", "_read_json": "同上",
        "_wants_fresh": "命令行开关, 镜像用 SaveState.fresh 字段", "_is_probe": "镜像用 SaveState.probe 字段",
        "_day_key": "镜像是注入字段 SaveState.day_key", "_migrate": "已镜像(名字相同, 见 lua)",
    },
    "lingo.gd": {"_resolve": "已镜像"},
    "tape.gd": {"_mute_set": "构造时内联", "_now": "已镜像", "_stamp": "已镜像"},
}
# db.gd 只查这些访问器
DB_ACCESSORS = ["load_error", "run", "economy", "faces", "boons", "jokers", "consumables", "sim", "ui", "tape",
    "tutorial", "profile", "lingo", "ranking", "ranking_tiers", "director", "patterns"]

# view/phrase.gd 的编排函数 → lua/app 里的孪生(名字可不同;None = 豁免, 理由在值里)
APP_MANIFEST = {
    "start_run": "start_run", "_start_phrase": "_start_phrase", "_settle": "_settle", "_advance": "_advance",
    "_next_section": "_next_section", "_begin_run": "_begin_run", "_reset_run": "_reset_run",
    "_resume_run": "_resume_run", "_feed_director": "_feed_director", "_note_tutorial": "_note_tutorial",
    "_open_draft": "_open_draft", "_on_shop_bought": "buy", "_on_shop_replace": "replace",
    "_on_shop_skipped": "leave", "_on_shop_reroll": "reroll", "_on_slot_tapped": "replace",
    "_on_consumable_bought": "buy_consumable", "_apply_shop_action": "apply_shop_action",
    "_apply_consumable": "apply_consumable", "_anvil": "anvil", "_roll_consumables": "roll_consumables",
    "_perkeo_on_exit": "perkeo_on_exit", "_consumable_effective": "consumable_effective",
    "_fire_due_consumables": "_fire_due_consumables", "_acted_early": "_acted_early",
    "_seconds_left": "_seconds_left", "_discard_open": "_discard_open", "_swap_open": "_swap_open",
    "_on_hand_sort": "sort", "_on_hand_swap": "drag_swap", "_on_hand_discard": "discard",
    "_on_hand_single_discard": "discard_one", "_action_feedback": "_action_feedback",
    "_note_discard_time": "_note_discard_time", "_notify_discard": "_notify_discard",
    "_deny_discard_why": "_deny_discard_why", "_deny_swap_why": "_deny_swap_why",
    "_faces_encountered": "_faces_encountered", "_final_target_id": "_final_target_id",
    "_shop_route": "_shop_route", "_blind_status": "_blind_status", "_roll_note": "_roll_note",
    "_on_end_next": "end_next", "_on_end_retry": "restart", "_on_end_home": "end_home",
    "_on_intro_done": "skip_intro", "_on_pause": "pause", "_on_resume": "resume", "_on_quit_run": "quit_run",
    "_enter_section": "_enter_section", "_tape_section": "_tape_section", "_process": "tick",
}

FUNC_RE = re.compile(r"^(?:static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", re.M)
CLASS_RE = re.compile(r"^class_name\s+([A-Za-z_][A-Za-z0-9_]*)", re.M)
INNER_CLASS_RE = re.compile(r"^class\s+\w+", re.M)


def gd_funcs(path):
    """顶层函数(不含内部 class 的方法)。"""
    src = open(path, encoding="utf-8").read()
    # 砍掉内部 class 块(缩进的 func 不算顶层)
    out = []
    for m in FUNC_RE.finditer(src):
        out.append(m.group(1))
    cls = CLASS_RE.search(src)
    return (cls.group(1) if cls else None), out


def lua_defs(path):
    src = open(path, encoding="utf-8").read()
    names = set()
    for m in re.finditer(r"^function\s+([A-Za-z_][A-Za-z0-9_]*)\s*[.:]\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(", src, re.M):
        names.add(m.group(2))
    for m in re.finditer(r"^([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function", src, re.M):
        names.add(m.group(2))
    for m in re.finditer(r"^local\s+function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", src, re.M):
        names.add(m.group(1))
    return names


def main():
    check = "--check" in sys.argv
    problems = []
    covered = 0
    for gd in sorted(glob.glob(os.path.join(ROOT, "core", "*.gd"))):
        base = os.path.basename(gd)
        if base in SKIP_FILES:
            continue
        cls, funcs = gd_funcs(gd)
        lua = os.path.join(ROOT, "lua", "core", base[:-3] + ".lua")
        if not os.path.exists(lua):
            problems.append("%s: 没有孪生 lua/core/%s.lua" % (base, base[:-3]))
            continue
        defs = lua_defs(lua)
        skip = SKIP_FUNCS.get(base, {})
        for f in funcs:
            if base == "db.gd":
                if f not in DB_ACCESSORS:
                    continue
            elif isinstance(skip, dict) and f in skip:
                continue
            elif f.startswith("_") and f != "_init":
                continue   # 私有函数不查(实现细节可以不同形)
            if f == "_init":
                f_lua = "new"
            else:
                f_lua = f
            if f_lua not in defs:
                problems.append("%s: 公开函数 `%s` 在 lua/core/%s.lua 里没有孪生" % (base, f, base[:-3]))
            else:
                covered += 1
    # 编排层清单
    app_dir = os.path.join(ROOT, "lua", "app")
    app_defs = set()
    for lp in glob.glob(os.path.join(app_dir, "*.lua")):
        app_defs |= lua_defs(lp)
    phrase_gd = os.path.join(ROOT, "view", "phrase.gd")
    if os.path.exists(phrase_gd):
        _, pfuncs = gd_funcs(phrase_gd)
        for g, l in APP_MANIFEST.items():
            if g not in pfuncs:
                problems.append("view/phrase.gd: 清单里的 `%s` 已不存在(改名了?更新 tools/mirror.py 的 APP_MANIFEST)" % g)
            elif l is None:
                continue
            elif l not in app_defs:
                problems.append("view/phrase.gd: 编排函数 `%s` 的孪生 `%s` 在 lua/app/ 里没有" % (g, l))
            else:
                covered += 1
    # 数据文件一一对应
    for js in glob.glob(os.path.join(ROOT, "data", "*.json")):
        stem = os.path.basename(js)[:-5]
        if not os.path.exists(os.path.join(ROOT, "lua", "data", stem + ".lua")):
            problems.append("data/%s.json 没有 lua/data/%s.lua(跑 python3 tools/luagen.py)" % (stem, stem))
    if problems:
        print("mirror --check: %d 处未覆盖" % len(problems))
        for p in problems:
            print("  x " + p)
        return 1
    print("mirror --check: %d 个公开函数/编排函数全部有孪生" % covered)
    return 0


if __name__ == "__main__":
    sys.exit(main())
