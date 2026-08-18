class_name HeroesScreen
extends Control

## 主角图鉴,1:1 自 docs/mockups/主角.dc.html(该屏权威)。
## 结构:页标题栏 → 详情大卡(立绘 + 称号 + 被动)→ 8 职业宫格 → 页签轨。
## 设计稿的数据是 mock(12 人/星级/三条属性条);游戏里主角没有稀有度也没有
## 属性值,这两块**按「做少」原则不放假数**,其余全接真数据:
## data/characters.json(称号/被动)+ assets/characters/manifest.json(主色/头像窗)
## + portrait.png(设计稿的人形水印位换成真立绘 —— 图鉴的意义就是看图)。
## 全员可用,没有解锁系统,锁定遮罩不做。

signal menu_pressed(idx: int)

const W := 720.0
const H := 1280.0
const CARD := Rect2(44.0, 118.0, 632.0, 560.0)
const GRID_Y := 700.0
const CELL_H := 190.0
const GAP := 14.0

var sel := 0

var _t := 0.0
var _roster: Array = []            # Character
var _colors: Array = []            # 各职业主色(manifest primary)
var _crops: Array = []             # avatar_crop(归一化 Rect2)
var _avatars: Array = []           # 懒加载:null 未试 / false 缺图 / Texture2D
var _portraits: Array = []
var _cell_rects: Array = []


func _ready() -> void:
	position = Vector2.ZERO
	size = Vector2(W, H)
	z_index = 85              # 首页 80 之上
	_roster = Character.roster()
	# ⚑ 本页就是唯一的选角处(2026-08-18)—— 进页先对齐存档, 点选即落盘。
	sel = clampi(SaveState.hero(), 0, _roster.size() - 1)
	_colors.resize(_roster.size())
	_crops.resize(_roster.size())
	_avatars.resize(_roster.size())
	_portraits.resize(_roster.size())
	for i in range(_roster.size()):
		_colors[i] = StageTheme.CYAN
		_crops[i] = Rect2(0.0, 0.0, 1.0, 1.0)
	var f := FileAccess.open("res://assets/characters/manifest.json", FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		f.close()
		if d is Dictionary:
			for ch in d.get("characters", []):
				var i := int(ch.get("idx", -1))
				if i < 0 or i >= _roster.size():
					continue
				var prim := String(ch.get("primary", ""))
				var hp := prim.find("#")
				if hp >= 0:
					_colors[i] = Color(prim.substr(hp, 7))
				if ch.has("avatar_crop"):
					var cr: Array = ch["avatar_crop"]
					_crops[i] = Rect2(float(cr[0]), float(cr[1]),
						float(cr[2]), float(cr[3]))
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _avatar(i: int) -> Texture2D:
	if _avatars[i] is Texture2D:
		return _avatars[i]
	if _avatars[i] != null:
		return null
	var p := "res://assets/characters/%s/avatar.png" % Walker.IDS[i]
	_avatars[i] = load(p) if ResourceLoader.exists(p) else false
	return _avatars[i] if _avatars[i] is Texture2D else null


func _portrait(i: int) -> Texture2D:
	if _portraits[i] is Texture2D:
		return _portraits[i]
	if _portraits[i] != null:
		return null
	var p := "res://assets/characters/%s/portrait768.png" % Walker.IDS[i]
	if not ResourceLoader.exists(p):
		p = "res://assets/characters/%s/portrait.png" % Walker.IDS[i]
	_portraits[i] = load(p) if ResourceLoader.exists(p) else false
	return _portraits[i] if _portraits[i] is Texture2D else null


func _gui_input(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT
			and not ev.pressed):
		return
	var p: Vector2 = ev.position
	for i in range(_cell_rects.size()):
		if (_cell_rects[i] as Rect2).has_point(p):
			sel = i
			SaveState.set_hero(i)    # 点了谁, 开局就是谁(唯一的选角动作)
			return
	var tabs := Chrome.tab_rects()
	for i in range(tabs.size()):
		if (tabs[i] as Rect2).has_point(p) and i != 1:
			menu_pressed.emit(i)
			return


func _draw() -> void:
	draw_rect(Rect2(0, 0, W, H), Color("000000"), true)
	var acc: Color = _colors[sel]
	var hero: Character = _roster[sel]
	Chrome.page_bar(self, "主 角 图 鉴", "%d 位主角 · 点选即上场" % _roster.size(), acc,
		int(HomeScreen.PROFILE["gems"]))
	_draw_detail(acc, hero)
	_draw_grid()
	Chrome.draw_tabs(self, 1, acc)
	Chrome.rain(self, _t)


func _draw_detail(acc: Color, hero: Character) -> void:
	Widgets.StageCard.draw_card(self, CARD, acc, 26.0, 14.0, false)
	var x := CARD.position.x + 30.0
	var cw := CARD.size.x - 60.0
	var zh := StageTheme.zh()
	var med := StageTheme.num("Medium")
	var dim := Color(acc.r, acc.g, acc.b, 0.62)

	# 立绘居中(设计稿这里是 28% 透明度的人形水印 —— 那是没素材时的占位,
	# 真立绘就该全亮画出来,pick_walker 的预览同款取窗)
	var tex := _portrait(sel)
	if tex != null:
		var box := Rect2(CARD.position.x + (CARD.size.x - 320.0) * 0.5,
			CARD.position.y + 26.0, 320.0, 400.0)
		var sc := minf(box.size.x / float(tex.get_width()),
			box.size.y / float(tex.get_height()))
		var dsz := Vector2(float(tex.get_width()), float(tex.get_height())) * sc
		var dst := Rect2(box.position + (box.size - dsz) * 0.5, dsz)
		draw_texture_rect(tex, dst, false)
		# 立绘自带纯黑底,矩形边裸在点阵上会读成"黑板子"——一圈发丝线
		# 让它读作贴在玻璃上的海报(和卡画在 joker_slot 里的处理同思路)
		draw_rect(dst.grow(1.0), Color(acc.r, acc.g, acc.b, 0.30), false, 1.0)

	# 左列:称号(设计稿的 TYPE 位);右上:编号
	var ty := CARD.position.y + 58.0
	draw_string(med, Vector2(x, ty), "TITLE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dim)
	draw_string(zh, Vector2(x, ty + 26.0), hero.title, HORIZONTAL_ALIGNMENT_LEFT, -1, 19,
		Color("eaf6ff"))
	draw_string(med, Vector2(x, ty), "NO. %02d / %02d" % [sel + 1, _roster.size()],
		HORIZONTAL_ALIGNMENT_RIGHT, cw, 12, dim)

	# 底部:名字行 → 分隔线 → 被动
	var by := CARD.end.y - 96.0
	var nw := zh.get_string_size(hero.cn_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	# 中文名本身就是拉丁字母的(DJ/RAPPER)不再跟注英文 id,免得念两遍
	var en: String = String(Walker.IDS[sel]).to_upper()
	if en == hero.cn_name.to_upper():
		en = ""
	var ew := 0.0 if en == "" else \
		med.get_string_size(en, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 12.0
	var nx := CARD.position.x + (CARD.size.x - nw - ew) * 0.5
	Chrome.neon(self, zh, hero.cn_name, Vector2(nx, by), 40, Color("ffffff"), acc)
	if en != "":
		draw_string(med, Vector2(nx + nw + 12.0, by), en,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, dim)
	Widgets.StageCard.rule_line(self, x, by + 14.0, cw, acc)
	var py := by + 46.0
	var chip_w := zh.get_string_size("被动", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 24.0
	var chip := Rect2(x, py - 19.0, chip_w, 27.0)
	draw_style_box(StageTheme.box(Color(acc.r, acc.g, acc.b, 0.10),
		Color(acc.r, acc.g, acc.b, 0.55), 1, 10), chip)
	draw_string(zh, Vector2(chip.position.x, py), "被动",
		HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, 13, acc)
	draw_string(zh, Vector2(chip.end.x + 14.0, py), hero.fx_text,
		HORIZONTAL_ALIGNMENT_LEFT, cw - chip_w - 14.0, 17, Color("e8f2ff"))


func _draw_grid() -> void:
	_cell_rects = []
	var cell_w := (CARD.size.x - GAP * 3.0) / 4.0
	var zh := StageTheme.zh()
	for i in range(_roster.size()):
		var col := i % 4
		var row := i / 4
		var r := Rect2(CARD.position.x + float(col) * (cell_w + GAP),
			GRID_Y + float(row) * (CELL_H + GAP), cell_w, CELL_H)
		_cell_rects.append(r)
		var on := i == sel
		var c: Color = _colors[i]
		if on:
			draw_style_box(StageTheme.box(Color(c.r, c.g, c.b, 0.08),
				Color(c.r, c.g, c.b, 0.75), 1, 14,
				Color(c.r, c.g, c.b, 0.25), 12), r)
			draw_line(r.position + Vector2(14.0, 0.5), Vector2(r.end.x - 14.0, r.position.y + 0.5),
				Color(1, 1, 1, 0.85), 1.5)
		else:
			draw_style_box(StageTheme.box(Color(0.07, 0.08, 0.15, 0.45),
				Color(0.67, 0.76, 1.0, 0.14), 1, 14), r)
		var cc := Vector2(r.position.x + r.size.x * 0.5, r.position.y + 62.0)
		var tex := _avatar(i)
		draw_circle(cc, 37.0, Color(0.055, 0.09, 0.16, 0.9))
		if tex != null:
			Chrome.avatar_disc(self, cc, 36.0, tex, _crops[i])
		else:
			draw_string(StageTheme.num("Bold"), Vector2(cc.x - 20.0, cc.y + 8.0),
				Walker.IDS[i].substr(0, 2).to_upper(), HORIZONTAL_ALIGNMENT_CENTER,
				40.0, 20, Color("8ff5ee"))
		draw_arc(cc, 37.0, 0, TAU, 56,
			Color(c.r, c.g, c.b, 0.85 if on else 0.4), 1.8, true)
		var name_col := Color("ffffff") if on else Color("b9cbe8")
		draw_string(zh, Vector2(r.position.x, r.position.y + 132.0),
			(_roster[i] as Character).cn_name, HORIZONTAL_ALIGNMENT_CENTER,
			r.size.x, 16, name_col)
		draw_string(zh, Vector2(r.position.x, r.position.y + 158.0),
			"「%s」" % (_roster[i] as Character).title, HORIZONTAL_ALIGNMENT_CENTER,
			r.size.x, 12, Color(c.r, c.g, c.b, 0.8) if on else Color("66799f"))
