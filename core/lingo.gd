class_name Lingo
extends RefCounted

## 语言层(1.1 英文化, 2026-08-19)。**主战场是美国, TapTap 只留简中试玩位**(用户拍板),
## 所以这一层从第一天就是双语并存, 不是「翻译一版另发一个包」。
##
## ⚑ 机制 = **gettext 式单表**(`data/lingo.json` 的 `table`: 中文原文 → 英文):
## · `data/ui.json` / `tutorial.json` / `run.json` 的展示串 —— DB 载入后整树替换
##   (`localize()`), 23 个 `DB.ui()` 消费点零改动;
## · 代码里的字面量 —— 包 `Lingo.t()`(`t_lingo` 有源码扫描断言锁着这条纪律);
## · 实体名(joker/face/boon/ticket)—— **不进表**:数据里本来就有英文 `name` 字段,
##   构造时 `pick()` 按语言挑(characters 没有 name 字段, cn/title/fx 走表)。
##
## ⚑ 语言的解析顺序(**探针钉死 cn 是刻意的**):
##   1. `SYNC5_LANG` 环境变量(cn/en)—— 给英文截图探针与桌面自测用;
##   2. 探针 ⇒ 恒 "cn" —— 单测/截图/sim 的读数不许跟宿主机的系统语言走
##      (否则同一棵树在中英文两台机器上探针产物不同, 正是 flow_probe 存档事故的形状);
##   3. 存档 `lang` 键(SaveState)—— 给未来的设置页开关留的口, UI 还没有;
##   4. 系统语言:zh* ⇒ cn, 其余 ⇒ en。
##
## ⚠ 表里查不到的串**原样返回**(中文顶上), 不 push_error —— 漏翻是文案债不是崩溃项,
## 完整性由 `t_lingo` 在测试期守(与 db.gd「测试期门禁」同一个取舍)。
## ⚠ Tape 打点**不走这一层**:日志记事实, `character.cn_name` 等照旧记中文,
## 换语言不许让两台机器的日志长得不一样。

static var _lang := ""
static var _loc_cache: Dictionary = {}


static func lang() -> String:
	if _lang == "":
		_lang = _resolve()
	return _lang


static func _resolve() -> String:
	var env := OS.get_environment("SYNC5_LANG")
	if env == "cn" or env == "en":
		return env
	if SaveState.is_probe():
		return "cn"
	var saved := SaveState.lang()
	if saved == "cn" or saved == "en":
		return saved
	return "cn" if OS.get_locale_language().begins_with("zh") else "en"


## 测试与设置页用:强制切语言并清缓存(_loc_cache 是按语言算的, 必须一起清)。
static func force(l: String) -> void:
	_lang = l
	_loc_cache.clear()


## 单串翻译(代码字面量的出口)。cn 模式零开销原样返回。
static func t(zh: String) -> String:
	if lang() != "en":
		return zh
	return String(DB.lingo().get("table", {}).get(zh, zh))


## 实体显示名:en 用数据里现成的 `name` 字段, 缺了退回 cn(别渲染空串)。
static func pick(e: Dictionary) -> String:
	if lang() == "en":
		var n := String(e.get("name", ""))
		if n != "":
			return n
	return String(e.get("cn", e.get("name", "")))


## 整树翻译(DB 的 ui/tutorial/run 出口)。cn 模式原样返回同一个对象;
## en 模式返回**深拷贝**的翻译副本并按 cache_key 缓存(文件一次运行内不变, 只走一遍)。
## `_` 前缀键(注释)整棵跳过 —— 它们是 dev-facing, 翻它纯烧时间。
static func localize(d: Dictionary, cache_key: String) -> Dictionary:
	if lang() != "en":
		return d
	if _loc_cache.has(cache_key):
		return _loc_cache[cache_key]
	var out: Dictionary = _walk(d)
	_loc_cache[cache_key] = out
	return out


static func _walk(v):
	match typeof(v):
		TYPE_DICTIONARY:
			var o := {}
			for k in v:
				o[k] = v[k] if String(k).begins_with("_") else _walk(v[k])
			return o
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(_walk(x))
			return a
		TYPE_STRING:
			return String(DB.lingo().get("table", {}).get(v, v))
		_:
			return v
