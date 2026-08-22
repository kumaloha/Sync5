extends RefCounted

# --- 语言层(1.1 英文化)—— core/lingo.gd + data/lingo.json 的契约 ---
#
# 四层守卫, 每层堵一种「静默漏翻」:
# ① 数据完整性:ui/tutorial/run 的非注释中文叶子、characters 的 cn/title/fx,
#    必须都在对照表里 —— 否则 en 模式那一块**上屏中文而不报错**。
# ② 源码纪律:view/*.gd 与 core/run.gd 里带中文的字符串字面量, 要么包着
#    Lingo.t()/pick(), 要么本身是表键(const 数据表, 显示点另行包裹), 要么在
#    豁免形状里(注释 / push_error / print / `.get(` 兜底)—— 新写一个裸中文
#    字面量在这里直接红。
# ③ Lingo.t() 的**实参**必须是表键 —— 包了却没进表, en 模式原样返回中文, 也是漏。
# ④ 行为:en/cn 两态的 t/pick/localize, 以及缓存清理。
# (表本身的硬校验 —— 值混中文 / % 占位符两边不齐 —— 在 db.gd validate_lingo,
#  由 t_db 的 load_error 断言覆盖, 这里不重复。)

# ⚠ 不用 \p{Han}:PCRE2 按 script-extensions 把「·」(U+00B7) 也算进 Hani(db.gd 同注)。
var _han := RegEx.create_from_string("[\\x{4e00}-\\x{9fff}\\x{3400}-\\x{4dbf}\\x{f900}-\\x{faff}]")
var _quoted := RegEx.create_from_string("\"([^\"\\\\]|\\\\.)*\"")
var _t_call := RegEx.create_from_string("Lingo\\.t\\(\\s*\"([^\"\\\\]|\\\\.)*\"")


func run(t) -> void:
	var table: Dictionary = DB.lingo().get("table", {})
	t.check(table.size() >= 250, "table is populated (got %d)" % table.size())

	# ---- ① 数据完整性 ----
	_walk_data(t, table, DB.ui(), "ui", ["tutor_focus"])
	_walk_data(t, table, DB.tutorial(), "tutorial", [])
	_walk_data(t, table, DB.run(), "run", [])
	for c in DB.characters():
		for k in ["cn", "title", "fx"]:
			var v := String(c.get(k, ""))
			if _han.search(v) != null:
				t.check(table.has(v), "characters %s '%s' translated" % [k, v])
	# 资产表的 cn_fx(显示行走 Lingo.t;cn/name 走 pick, 不进表)
	for a in DB.assets().get("assets", []):
		var fxv := String(a.get("cn_fx", ""))
		if _han.search(fxv) != null:
			t.check(table.has(fxv), "asset cn_fx '%s' translated" % fxv)
	# 美术线 manifest **只查 amount**(数额章是唯一上屏字段;cn/art_subject/trigger_zh
	# 是 dev 数据源或有 ui.json 优先级压着, 整树扫会把不上屏的字段全误伤)
	var mf := FileAccess.open("res://assets/jokers/manifest.json", FileAccess.READ)
	if mf != null:
		var md = JSON.parse_string(mf.get_as_text())
		var entries: Array = md if md is Array else (md.get("cards", []) if md is Dictionary else [])
		for e in entries:
			if e is Dictionary and _han.search(String(e.get("amount", ""))) != null:
				t.check(table.has(String(e["amount"])),
					"manifest amount '%s' translated" % e["amount"])

	# ---- ② 源码纪律 + ③ t() 实参在表 ----
	var files: Array = []
	for f in DirAccess.get_files_at("res://view"):
		if String(f).ends_with(".gd"):
			files.append("res://view/" + String(f))
	files.append("res://core/run.gd")
	t.check(files.size() > 20, "source scan sees the view directory")
	for path in files:
		_scan_source(t, table, path)

	# ---- ④ 行为 ----
	Lingo.force("en")
	t.eq(Lingo.t("弃牌"), "Discard", "t() translates in en")
	t.eq(Lingo.t("不在表里的串"), "不在表里的串", "missing key falls through untouched")
	t.eq(Lingo.pick({"cn": "拔电", "name": "Unplugged"}), "Unplugged", "pick() prefers name in en")
	t.eq(Lingo.pick({"cn": "只有中文"}), "只有中文", "pick() falls back to cn when name missing")
	t.eq(DB.ui()["patterns"]["1"], "Pair", "DB.ui() localized in en")
	t.eq(String(DB.run()["gig_names"][0]), "Small Bar", "DB.run() gig names localized in en")
	Lingo.force("cn")
	t.eq(Lingo.t("弃牌"), "弃牌", "t() is identity in cn")
	t.eq(Lingo.pick({"cn": "拔电", "name": "Unplugged"}), "拔电", "pick() prefers cn in cn")
	t.eq(DB.ui()["patterns"]["1"], "对子", "DB.ui() raw in cn (loc cache cleared by force)")
	# 复位:回到「未解析」, 下一个消费者按解析顺序重来(探针 ⇒ cn)。
	Lingo.force("")
	t.eq(Lingo.lang(), "cn", "probes resolve to cn (deterministic across host locales)")


## 数据侧:非 `_` 键下的中文串叶子必须都是表键。skip = 整棵跳过的子树
## (ui.json 的 tutor_focus 值是 dev 备注, 从不上屏)。
func _walk_data(t, table: Dictionary, v, path: String, skip: Array) -> void:
	match typeof(v):
		TYPE_DICTIONARY:
			for k in v:
				if String(k).begins_with("_") or skip.has(String(k)):
					continue
				_walk_data(t, table, v[k], path + "/" + String(k), skip)
		TYPE_ARRAY:
			for x in v:
				_walk_data(t, table, x, path, skip)
		TYPE_STRING:
			if _han.search(v) != null:
				t.check(table.has(v), "%s: '%s' translated" % [path, v])


func _scan_source(t, table: Dictionary, path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		t.check(false, "cannot open %s" % path)
		return
	var lineno := 0
	while not f.eof_reached():
		var line := f.get_line()
		lineno += 1
		var stripped := line.strip_edges()
		if stripped.begins_with("#"):
			continue
		# ③ Lingo.t("...") 的实参必须在表里(包了没进表 = en 模式静默中文)
		for m in _t_call.search_all(line):
			var arg := m.get_string().substr(m.get_string().find("\""))
			arg = arg.substr(1, arg.length() - 2).c_unescape()
			if _han.search(arg) != null:
				t.check(table.has(arg), "%s:%d Lingo.t arg '%s' in table" % [path, lineno, arg])
		# ② 裸中文字面量
		if line.find("Lingo.t(") != -1 or line.find("Lingo.pick(") != -1:
			continue
		if line.find("push_error") != -1 or line.find("push_warning") != -1 \
				or line.find("print(") != -1 or line.find(".get(") != -1:
			continue
		for m in _quoted.search_all(line):
			var lit := m.get_string()
			lit = lit.substr(1, lit.length() - 2).c_unescape()
			if _han.search(lit) == null:
				continue
			t.check(table.has(lit),
				"%s:%d bare CN literal '%s' — wrap in Lingo.t() or add to lingo.json" \
				% [path, lineno, lit])
