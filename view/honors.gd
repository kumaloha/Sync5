class_name HonorsScreen
extends Control

## 荣誉页(成就 + 排行双子页),自 docs/mockups/荣誉.dc.html(该屏权威)。
## ⚠ 这是一页**壳**:成就要存档系统、排行要联网,两者都不存在,所以列表
## 数据是清清楚楚的占位 mock(同 home.gd 的 PROFILE 先例)—— 但词汇全部
## 对齐真游戏:成就说的是真机制(60 张小丑牌/8 位主角/4 场巡演),排行的
## 关卡就是真的 4 场演出(GameConfig.gig_name / section_target / 档位色),
## 牌型名是真的十种。接入存档后只换数据源,不动画法。
## 设计稿的 18 关排行/全球排名皆按此原则收敛到真实结构。

signal menu_pressed(idx: int)

const W := 720.0
const H := 1280.0
const ACC := StageTheme.GOLD
const TIER_COL := {"铜": Color("c98b5a"), "银": Color("c6d3e6"),
	"金": Color("ffd36e"), "白金": Color("9ff0ff")}

# 占位成就(无存档;done/cur 是假的,机制与数目是真的)
const ACHV := [
	{"name": "首次登台", "desc": "完成第一场演出", "tier": "铜", "cur": 1, "max": 1, "glyph": "★"},
	{"name": "雨夜常客", "desc": "累计游玩 50 局", "tier": "铜", "cur": 50, "max": 50, "glyph": "♪"},
	{"name": "满堂彩", "desc": "单拍得分超过 1500", "tier": "银", "cur": 1500, "max": 1500, "glyph": "◆"},
	{"name": "同花之夜", "desc": "用同花通关一个段落", "tier": "银", "cur": 1, "max": 1, "glyph": "♥"},
	{"name": "小丑收藏家", "desc": "一局同时持有 4 张小丑牌", "tier": "金", "cur": 3, "max": 4, "glyph": "♣"},
	{"name": "全员登台", "desc": "用 8 位主角各通关一次", "tier": "金", "cur": 5, "max": 8, "glyph": "♠"},
	{"name": "风暴征服者", "desc": "通关整场巡演(4 场演出)", "tier": "金", "cur": 0, "max": 1, "glyph": "⚡"},
	{"name": "霓虹之王", "desc": "解锁全部成就", "tier": "白金", "cur": 6, "max": 8, "glyph": "✦"},
]
const NAMES := ["ECHO_9", "MIRA", "夜鸦", "K.LUX", "SABLE", "雨宫零", "NOCT",
	"NEON PLAYER", "V-01", "RAIN", "GLITCH", "白噪", "TEMPO"]
const HANDS := ["皇家同花顺", "同花顺", "四条", "葫芦", "同花", "顺子", "三条",
	"两对", "对子", "高牌"]
const WHENS := ["2 小时前", "今天", "昨天", "3 天前", "本周"]

var sub := 0          # 0 成就 / 1 排行
var level := 0        # 排行页选中的演出

var _t := 0.0
var _sub_rects: Array = []
var _chip_rects: Array = []


func _ready() -> void:
	position = Vector2.ZERO
	size = Vector2(W, H)
	z_index = 85
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _gui_input(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT
			and not ev.pressed):
		return
	var p: Vector2 = ev.position
	for i in range(_sub_rects.size()):
		if (_sub_rects[i] as Rect2).has_point(p):
			sub = i
			return
	for i in range(_chip_rects.size()):
		if (_chip_rects[i] as Rect2).grow(4.0).has_point(p):
			level = i
			return
	var tabs := Chrome.tab_rects()
	for i in range(tabs.size()):
		if (tabs[i] as Rect2).has_point(p) and i != 3:
			menu_pressed.emit(i)
			return


func _draw() -> void:
	draw_rect(Rect2(0, 0, W, H), Color("000000"), true)
	var done := _done_count()
	Chrome.page_bar(self, "荣 誉", "成就 %d/%d · 巡演 %d 场" %
		[done, ACHV.size(), GameConfig.SECTIONS_PER_RUN], ACC)
	_draw_subtabs()
	if sub == 0:
		_draw_achievements(done)
	else:
		_draw_ranks()
	Chrome.draw_tabs(self, 3, ACC)
	Chrome.rain(self, _t)


func _done_count() -> int:
	var n := 0
	for a in ACHV:
		if int(a["cur"]) >= int(a["max"]):
			n += 1
	return n


func _draw_subtabs() -> void:
	_sub_rects = []
	var zh := StageTheme.zh()
	for i in range(2):
		var r := Rect2(44.0 + float(i) * 322.0, 112.0, 310.0, 46.0)
		_sub_rects.append(r)
		var on := i == sub
		if on:
			draw_style_box(StageTheme.box(Color(ACC.r, ACC.g, ACC.b, 0.10),
				Color(ACC.r, ACC.g, ACC.b, 0.6), 1, 14,
				Color(ACC.r, ACC.g, ACC.b, 0.2), 12), r)
			draw_line(r.position + Vector2(16.0, 0.5), Vector2(r.end.x - 16.0, r.position.y + 0.5),
				Color(1, 1, 1, 0.85), 1.5)
		else:
			draw_style_box(StageTheme.box(Color(0.06, 0.07, 0.14, 0.4),
				Color(0.67, 0.76, 1.0, 0.14), 1, 14), r)
		draw_string(zh, Vector2(r.position.x, r.position.y + 30.0),
			["成 就", "排 行"][i], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 20,
			Color("ffffff") if on else Color("8ea3c8"))


# ============================== 成就 ==============================

func _draw_achievements(done: int) -> void:
	var zh := StageTheme.zh()
	var num := StageTheme.num("Bold")
	# 总览:完成度圆环 + 四档计数
	var panel := Rect2(44.0, 174.0, 632.0, 122.0)
	Widgets.StageCard.draw_card(self, panel, ACC, 20.0, 8.0, false)
	var pc := Vector2(panel.position.x + 74.0, panel.position.y + 61.0)
	var pct := float(done) / float(ACHV.size())
	draw_arc(pc, 42.0, 0, TAU, 48, Color(0.10, 0.12, 0.23, 0.9), 8.0, true)
	if pct > 0.0:
		draw_arc(pc, 42.0, -PI * 0.5, -PI * 0.5 + TAU * pct, 48, ACC, 8.0, true)
	draw_string(num, Vector2(pc.x - 40.0, pc.y + 3.0), "%d%%" % int(round(pct * 100.0)),
		HORIZONTAL_ALIGNMENT_CENTER, 80.0, 22, Color("ffd9a0"))
	draw_string(zh, Vector2(pc.x - 40.0, pc.y + 22.0), "完成度",
		HORIZONTAL_ALIGNMENT_CENTER, 80.0, 10, Color("7487ac"))
	var tiers := ["铜", "银", "金", "白金"]
	for i in range(4):
		var cnt := 0
		for a in ACHV:
			if a["tier"] == tiers[i] and int(a["cur"]) >= int(a["max"]):
				cnt += 1
		var tx := panel.position.x + 170.0 + float(i) * 118.0
		var tc: Color = TIER_COL[tiers[i]] if cnt > 0 else Color("5d7091")
		Chrome.tab_icon(self, 3, Vector2(tx, panel.position.y + 42.0), tc, 0.62)
		draw_string(num, Vector2(tx - 40.0, panel.position.y + 86.0), str(cnt),
			HORIZONTAL_ALIGNMENT_CENTER, 80.0, 19, tc)
		draw_string(zh, Vector2(tx - 40.0, panel.position.y + 106.0), tiers[i],
			HORIZONTAL_ALIGNMENT_CENTER, 80.0, 11, Color("66799f"))

	# 列表(8 条恰好排到页签轨上方,不滚)
	for i in range(ACHV.size()):
		var a: Dictionary = ACHV[i]
		var r := Rect2(44.0, 310.0 + float(i) * 101.0, 632.0, 91.0)
		var got: bool = int(a["cur"]) >= int(a["max"])
		var tc2: Color = TIER_COL[a["tier"]]
		var edge := Color(tc2.r, tc2.g, tc2.b, 0.35) if got else Color(0.67, 0.76, 1.0, 0.12)
		draw_style_box(StageTheme.box(Color(0.07, 0.08, 0.16, 0.45), edge, 1, 14), r)
		if got:
			draw_line(r.position + Vector2(14.0, 0.5), Vector2(r.end.x - 14.0, r.position.y + 0.5),
				Color(tc2.r, tc2.g, tc2.b, 0.55), 1.2)
		# 图标盒
		var ib := Rect2(r.position.x + 16.0, r.position.y + 15.0, 60.0, 60.0)
		draw_style_box(StageTheme.box(Color(0.08, 0.10, 0.20, 0.7),
			Color(tc2.r, tc2.g, tc2.b, 0.6 if got else 0.18), 1, 12), ib)
		draw_string(zh, Vector2(ib.position.x, ib.position.y + 41.0), a["glyph"],
			HORIZONTAL_ALIGNMENT_CENTER, ib.size.x, 28,
			Color(tc2.r, tc2.g, tc2.b, 0.95 if got else 0.4))
		# 名 + 档 + 描述
		var tx2 := ib.end.x + 16.0
		draw_string(zh, Vector2(tx2, r.position.y + 30.0), a["name"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("ffffff") if got else Color("8ea3c8"))
		var nw := zh.get_string_size(a["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_string(zh, Vector2(tx2 + nw + 10.0, r.position.y + 30.0), a["tier"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, tc2 if got else Color("5d7091"))
		draw_string(zh, Vector2(tx2, r.position.y + 52.0), a["desc"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("93a7cf") if got else Color("66799f"))
		# 进度条
		var bar := Rect2(tx2, r.position.y + 66.0, r.end.x - tx2 - 110.0, 5.0)
		draw_style_box(StageTheme.box(Color(0.08, 0.10, 0.21, 0.9),
			Color(0.67, 0.76, 1.0, 0.12), 1, 3), bar)
		var frac := clampf(float(a["cur"]) / float(a["max"]), 0.0, 1.0)
		if frac > 0.0:
			draw_style_box(StageTheme.box(
				tc2 if got else Color(0.55, 0.66, 0.86, 0.7), Color(0, 0, 0, 0), 0, 3),
				Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)))
		draw_string(StageTheme.num("Medium"), Vector2(bar.end.x + 12.0, r.position.y + 72.0),
			"已达成" if got else "%d / %d" % [int(a["cur"]), int(a["max"])],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("7487ac"))


# ============================== 排行 ==============================

func _draw_ranks() -> void:
	_chip_rects = []
	var zh := StageTheme.zh()
	var num := StageTheme.num("Bold")
	var med := StageTheme.num("Medium")
	# 演出选择条:就是真的 4 场(档位色 = StageCard.accent_for,和首页同源)
	for i in range(GameConfig.SECTIONS_PER_RUN):
		var r := Rect2(44.0 + float(i) * 160.5, 174.0, 150.0, 48.0)
		_chip_rects.append(r)
		var on := i == level
		var c := Widgets.StageCard.accent_for(i)
		if on:
			draw_style_box(StageTheme.box(Color(c.r, c.g, c.b, 0.14),
				Color(c.r, c.g, c.b, 0.7), 1, 13), r)
		else:
			draw_style_box(StageTheme.box(Color(0.06, 0.07, 0.14, 0.4),
				Color(0.67, 0.76, 1.0, 0.14), 1, 13), r)
		draw_string(num, Vector2(r.position.x, r.position.y + 21.0), "%02d" % (i + 1),
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 16,
			Color("ffffff") if on else Color("8ea3c8"))
		draw_string(zh, Vector2(r.position.x, r.position.y + 39.0), GameConfig.gig_name(i),
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 12,
			Color(c.r, c.g, c.b, 0.9) if on else Color("5f7196"))

	var acc := Widgets.StageCard.accent_for(level)
	var target := GameConfig.section_target(level)
	# 榜首台:场名 + 目标 + 前三
	var panel := Rect2(44.0, 236.0, 632.0, 204.0)
	Widgets.StageCard.draw_card(self, panel, acc, 20.0, 8.0, false)
	Chrome.neon(self, zh, GameConfig.gig_name(level),
		Vector2(panel.position.x + 24.0, panel.position.y + 40.0), 26, Color("ffffff"), acc)
	draw_string(med, Vector2(panel.position.x, panel.position.y + 38.0),
		"目标 %s · 第 %d 场" % [StageTheme.fmt_thousands(target), level + 1],
		HORIZONTAL_ALIGNMENT_RIGHT, panel.size.x - 24.0, 13,
		Color(acc.r, acc.g, acc.b, 0.62))
	var rows := _rows(target)
	var medal := [Color("ffd76a"), Color("d7e2f2"), Color("d08a4e")]
	var order := [1, 0, 2]
	for k in range(3):
		var idx: int = order[k]
		var row: Dictionary = rows[idx]
		var cx := panel.position.x + 120.0 + float(k) * 196.0
		var rad := 34.0 if idx == 0 else 27.0
		var cy := panel.position.y + 96.0 + (0.0 if idx == 0 else 8.0)
		var mc: Color = medal[idx]
		draw_circle(Vector2(cx, cy), rad, Color(0.07, 0.11, 0.2, 0.9))
		draw_arc(Vector2(cx, cy), rad, 0, TAU, 40, mc, 2.0, true)
		draw_string(num, Vector2(cx - rad, cy + (10.0 if idx == 0 else 8.0)),
			String(row["name"]).substr(0, 1), HORIZONTAL_ALIGNMENT_CENTER, rad * 2.0,
			24 if idx == 0 else 19, mc)
		var badge := Rect2(cx - 11.0, cy + rad - 8.0, 22.0, 18.0)
		draw_style_box(StageTheme.box(mc, Color(0, 0, 0, 0), 0, 6), badge)
		draw_string(num, Vector2(badge.position.x, badge.position.y + 14.0),
			str(idx + 1), HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, 12, Color("08101c"))
		draw_string(zh, Vector2(cx - 80.0, cy + rad + 28.0), row["name"],
			HORIZONTAL_ALIGNMENT_CENTER, 160.0, 14, Color("e6f0ff"))
		draw_string(num, Vector2(cx - 80.0, cy + rad + 48.0),
			StageTheme.fmt_thousands(int(row["score"])),
			HORIZONTAL_ALIGNMENT_CENTER, 160.0, 16, mc)

	# 名次列表(占位:无联网。「NEON PLAYER」是首页 PROFILE 那套 mock 的本人)
	for i in range(3, rows.size()):
		var row2: Dictionary = rows[i]
		var r2 := Rect2(44.0, 454.0 + float(i - 3) * 66.0, 632.0, 58.0)
		var me: bool = row2["me"]
		var edge := Color(acc.r, acc.g, acc.b, 0.6) if me else Color(0.67, 0.76, 1.0, 0.12)
		draw_style_box(StageTheme.box(
			Color(acc.r, acc.g, acc.b, 0.08) if me else Color(0.07, 0.08, 0.16, 0.4),
			edge, 1, 12), r2)
		draw_string(num, Vector2(r2.position.x + 20.0, r2.position.y + 36.0),
			str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 19,
			Color("ffffff") if me else Color("8ea3c8"))
		draw_circle(Vector2(r2.position.x + 84.0, r2.position.y + 29.0), 18.0,
			Color(0.07, 0.11, 0.2, 0.9))
		draw_arc(Vector2(r2.position.x + 84.0, r2.position.y + 29.0), 18.0, 0, TAU, 30,
			Color(acc.r, acc.g, acc.b, 0.8) if me else Color(0.67, 0.76, 1.0, 0.2), 1.5, true)
		draw_string(zh, Vector2(r2.position.x + 66.0, r2.position.y + 35.0),
			String(row2["name"]).substr(0, 1), HORIZONTAL_ALIGNMENT_CENTER, 36.0, 14,
			acc if me else Color("8ea3c8"))
		draw_string(zh, Vector2(r2.position.x + 116.0, r2.position.y + 26.0), row2["name"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("ffffff") if me else Color("b9cbe8"))
		draw_string(zh, Vector2(r2.position.x + 116.0, r2.position.y + 45.0), row2["hand"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("5f7196"))
		draw_string(num, Vector2(r2.position.x, r2.position.y + 30.0),
			StageTheme.fmt_thousands(int(row2["score"])),
			HORIZONTAL_ALIGNMENT_RIGHT, r2.size.x - 20.0, 18,
			Color("ffffff") if me else Color("cddcf2"))
		draw_string(zh, Vector2(r2.position.x, r2.position.y + 47.0), row2["when"],
			HORIZONTAL_ALIGNMENT_RIGHT, r2.size.x - 20.0, 10, Color("5f7196"))


## 占位榜单:名字/名次是 mock,分数尺度锚在该场真实目标分上(design 稿同款公式)。
func _rows(target: int) -> Array:
	var out: Array = []
	var base := float(target) * 4.2
	for i in range(13):    # 前 3 上台,列表 10 行,恰好排到页签轨上方
		var nm: String = NAMES[(i + level * 3) % NAMES.size()]
		out.append({
			"name": nm,
			"score": int(round(base * pow(0.93, i) / 5.0)) * 5,
			"hand": HANDS[(i + level) % HANDS.size()],
			"when": WHENS[(i + level) % WHENS.size()],
			"me": nm == "NEON PLAYER",
		})
	return out
