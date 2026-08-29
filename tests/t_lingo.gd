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
	# 阈值 2026-08-24 下调 250 → 200:局外 build 删除带走了主角/券/荣誉/资产四族 ~60 条
	t.check(table.size() >= 200, "table is populated (got %d)" % table.size())

	# ---- ① 数据完整性 ----
	_walk_data(t, table, DB.ui(), "ui", ["tutor_focus"])
	_walk_data(t, table, DB.tutorial(), "tutorial", [])
	_walk_data(t, table, DB.run(), "run", [])
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

	# ---- ⑤⑥ 排版预算 ----
	_check_blindcard_fit(t)
	_check_jokercard_fit(t)


## ⑤ 局内盲注卡的 command **必须放得进两行**。
##
## `Widgets.BlindCard._draw` 用 `draw_multiline_string(..., max_lines = 2)` ——
## 超出的部分**直接不画, 不报错**。2026-08-28 实测:58 条里有 7 条在被截,
## 而截掉的恰恰是句子的后半 —— 也就是**惩罚幅度与解法**:
##   `trilogy` 丢「+25%」(不知道罚多少) · `callout` 丢「打出后商店多一张」(奖励没了)
##   `patchin` 丢「打出开拍时的缓存牌可全效」(**解法整个没了, 只剩惩罚**)
## 这直接违反 versus.md 的「盲注 = 条件 + 惩罚 + 有解法」——设计写了, UI 吃掉了。
##
## ⚑ **两态各量各的字体**(2026-08-28 起):`BlindCard._draw` 在 en 态改用
## `StageTheme.num()`(Rajdhani)—— 中文字体画拉丁走 CJK 度量, 一行只剩 ~12 个字符,
## 同一批文案 en 态曾有 **10 条**被截, 换字体后只剩 2 条(那 2 条已缩)。
## **病在字体选择, 不是英文句子太长** —— 所以修的是渲染侧, 不是让作者砍英文。
## ⇒ 这里必须**按语言取对应的字体**量, 否则锁的是一个不存在的组合。
func _check_blindcard_fit(t) -> void:
	# 尺寸取 view/layout.gd 的真值:高 216, 宽按目录 118:176 比例 —— 抄死数字就会漂。
	var card_h := 216.0
	var card_w := card_h * 118.0 / 176.0
	var s := card_w / 118.0
	# 文字预算 = 结果脚 fr2 的宽再内缩(`_draw` 里 fr2.size.x - 10s, fr2 宽 = w - 14s)
	var avail := card_w - 24.0 * s
	var fs := int(10.0 * s)
	for lang in ["cn", "en"]:
		Lingo.force(lang)
		var font: Font = StageTheme.zh() if lang == "cn" else StageTheme.num("Medium")
		for k in DB.ui().get("blindcard", {}):
			if String(k).begins_with("_"):
				continue
			var cmd := String(DB.ui()["blindcard"][k].get("command", ""))
			if cmd == "":
				continue
			# 无限行 vs 两行:高度一样 = 没被截。
			var full := font.get_multiline_string_size(cmd, HORIZONTAL_ALIGNMENT_LEFT, avail, fs, -1)
			var two := font.get_multiline_string_size(cmd, HORIZONTAL_ALIGNMENT_LEFT, avail, fs, 2)
			t.check(full.y <= two.y + 0.5,
				"[%s] blindcard '%s' 的 command 放不进两行, 后半会被静默截掉: %s" % [lang, k, cmd])
	Lingo.force("")   # 复位:探针一律解析成 cn


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

## ⑥ 小丑牌卡面的 trigger **必须放得进一行**(2026-08-28,与 ⑤ 同一个坑的第二处)。
##
## `JokerSlotView._draw` 的底部触发词是**单行** `draw_string` + 自适应缩字
## (13s 缩到 9s 为止)——**缩到最小仍放不下就被裁掉尾部, 不报错**。
## 单行是用户 2026-08-11 拍板的形状(「图标太小、字的区域太大」的正解), 所以
## **修法是缩文案, 不是改成两行**。
##
## 实测(2026-08-28,**渲染验收才发现的** —— 数字量不出来, 得看图):三种真实尺寸下
## 各有 12~15 / 77 条在被裁, 裁掉的是句子尾部 = **数额和后置条件**:
## 预支丢「还不上 = 演出失败」(**死亡条件**)· 镜面丢整个效果说明 · 超级百搭丢半个机制。
## 病根是「奖励分+目标分的NN%」这个说法本身太长(13 张卡共用),已全族统一成「+目标分 NN%」。
##
## ⚠ **大卡反而更容易裁**:缩字下限是 `9.0 * s` 而 `s = 卡高/172` —— 卡越大最小字号越大。
## 所以三种尺寸都要量,不能只量最窄的那个。
func _check_jokercard_fit(t) -> void:
	var zh := StageTheme.zh()
	# [卡宽, 卡高, 名字]。三处真实尺寸:data/ui.json 的 card_w / card_w_4 与 layout.gd 的装备槽。
	for spec in [[156.0, 171.6, "窄版货架(联票 4 张)"],
			[200.0, 220.0, "常规货架(3 张)"],
			[165.0, 172.0, "装备槽(HUD 常驻)"]]:
		var w: float = float(spec[0])
		var s: float = float(spec[1]) / 172.0
		var pad: float = 8.0 * s
		var avail: float = (w - pad * 2.0) - 10.0 * s   # JokerSlotView._draw 的 tr 宽再内缩
		var fs_min: int = int(9.0 * s)                  # 自适应缩字的下限
		for k in DB.ui().get("jokercard", {}):
			if String(k).begins_with("_"):
				continue
			var trig := String(DB.ui()["jokercard"][k].get("trigger", ""))
			if trig == "":
				continue
			t.check(zh.get_string_size(trig, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_min).x <= avail,
				"jokercard '%s' 的 trigger 在%s上放不下一行, 尾部会被静默裁掉: %s"
				% [k, spec[2], trig])
