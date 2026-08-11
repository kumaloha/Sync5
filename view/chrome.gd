class_name Chrome
extends RefCounted

## 四屏共用的全局 chrome:首页 + 主角/小丑牌/荣誉三个图鉴页(2026-08-11,
## resources/主角|小丑牌|荣誉.dc.html 三份设计稿实装时从 home.gd 迁出成单源)。
## 这里只放「每个页面都要画的那几件」:底部页签轨、页标题栏、货币章、斜雨、
## 霓虹字、头像圆盘。页面自己的内容各回各家。

const W := 720.0
const H := 1280.0
const TABS := ["关卡", "主角", "小丑牌", "荣誉"]

# 轨几何与 home.gd 原值一致(卡片外框 24 + 44 = 68 起)
const TAB_X0 := 68.0
const TAB_W := 146.0          # (672 - 88) / 4
const TAB_Y := 1143.0
const TAB_ICON_DY := 48.0
const TAB_LABEL_DY := 100.0
const TAB_UNDER_DY := 114.0
const TAB_H := 172.0


static func tab_rects() -> Array:
	var out: Array = []
	for i in range(TABS.size()):
		out.append(Rect2(TAB_X0 + float(i) * TAB_W, TAB_Y, TAB_W, TAB_H))
	return out


## 底部页签轨。active 高亮 + 档位/页面主色下划线。
## 底部**不要**加板:那里本来就是黑的(用户 2026-08-05 拍板)。
static func draw_tabs(ci: CanvasItem, active: int, acc: Color) -> void:
	for i in range(TABS.size()):
		var r := Rect2(TAB_X0 + float(i) * TAB_W, TAB_Y, TAB_W, TAB_H)
		var on := i == active
		var col: Color = Color("ffffff") if on else Color(0.73, 0.78, 0.91, 0.78)
		var ic: Color = acc if on else Color(0.55, 0.67, 1.0, 0.35)
		tab_icon(ci, i, r.position + Vector2(TAB_W * 0.5, TAB_ICON_DY), ic)
		ci.draw_string(StageTheme.zh(), Vector2(r.position.x, r.position.y + TAB_LABEL_DY),
			TABS[i], HORIZONTAL_ALIGNMENT_CENTER, TAB_W, 20, col)
		if on:
			var u := Rect2(r.position.x + TAB_W * 0.5 - 16.0, r.position.y + TAB_UNDER_DY,
				32.0, 2.5)
			ci.draw_style_box(StageTheme.box(acc, Color(0, 0, 0, 0), 0, 2), u)


## 四个页签的线稿图标(设计稿 SVG path 的简化临摹)。scale 给荣誉页的
## 奖杯小图复用(1.0 = 页签原尺寸,约 42px 见方)。
static func tab_icon(ci: CanvasItem, i: int, c: Vector2, col: Color, scale := 1.0) -> void:
	var wd := 2.0 * scale
	var s := scale
	match i:
		0:      # 关卡: a card with a diamond
			ci.draw_rect(Rect2(c - Vector2(15, 20) * s, Vector2(30, 40) * s), col, false, wd)
			ci.draw_polyline(PackedVector2Array([c + Vector2(0, -9) * s, c + Vector2(9, 0) * s,
				c + Vector2(0, 9) * s, c + Vector2(-9, 0) * s, c + Vector2(0, -9) * s]),
				col, wd, true)
		1:      # 主角: head + shoulders
			ci.draw_arc(c + Vector2(0, -10) * s, 10.0 * s, 0, TAU, 26, col, wd, true)
			ci.draw_arc(c + Vector2(0, 22) * s, 18.0 * s, PI, TAU, 22, col, wd, true)
		2:      # 小丑牌: the jester crown
			ci.draw_polyline(PackedVector2Array([c + Vector2(-18, 14) * s, c + Vector2(-12, -12) * s,
				c + Vector2(-4, 2) * s, c + Vector2(0, -16) * s, c + Vector2(4, 2) * s,
				c + Vector2(12, -12) * s, c + Vector2(18, 14) * s, c + Vector2(-18, 14) * s]),
				col, wd, true)
		_:      # 荣誉: a trophy
			ci.draw_polyline(PackedVector2Array([c + Vector2(-10, -18) * s, c + Vector2(10, -18) * s,
				c + Vector2(10, -6) * s, c + Vector2(0, 4) * s, c + Vector2(-10, -6) * s,
				c + Vector2(-10, -18) * s]), col, wd, true)
			ci.draw_arc(c + Vector2(-15, -13) * s, 6.0 * s, PI * 0.5, PI * 1.5, 12, col, wd, true)
			ci.draw_arc(c + Vector2(15, -13) * s, 6.0 * s, PI * 1.5, PI * 2.5, 12, col, wd, true)
			ci.draw_line(c + Vector2(0, 4) * s, c + Vector2(0, 12) * s, col, wd, true)
			ci.draw_line(c + Vector2(-9, 18) * s, c + Vector2(9, 18) * s, col, wd, true)


## 图鉴页的页标题栏(设计稿三页共用的头):玻璃条 + 标题/副行 + 货币章。
## 货币数值仍是 HomeScreen.PROFILE 那套 mock —— 存档系统接入前四屏共用一份假数。
static func page_bar(ci: CanvasItem, title: String, sub: String, acc: Color,
		gems := -1) -> void:
	var bar := Rect2(44.0, 22.0, W - 88.0, 82.0)
	Widgets.StageCard.draw_card(ci, bar, acc, 22.0, 8.0, false)
	glass_film(ci, bar.grow(-2.0), 20.0)
	var r := bar.grow(-8.0)
	ci.draw_string(StageTheme.zh(), Vector2(r.position.x + 18.0, r.position.y + 30.0), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("eaf6ff"))
	ci.draw_string(StageTheme.zh(), Vector2(r.position.x + 18.0, r.position.y + 52.0), sub,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("7487ac"))
	var cy := r.position.y + r.size.y * 0.5
	var coins := int(HomeScreen.PROFILE["coins"])
	if gems >= 0:
		chip(ci, Rect2(r.end.x - 130.0, cy - 33.0, 122.0, 30.0), StageTheme.AMBER,
			"◆", str(coins), Color("ffd9a0"))
		chip(ci, Rect2(r.end.x - 130.0, cy + 3.0, 122.0, 30.0), StageTheme.VIOLET,
			"◈", str(gems), Color("cdb2ff"))
	else:
		chip(ci, Rect2(r.end.x - 130.0, cy - 15.0, 122.0, 31.0), StageTheme.AMBER,
			"◆", str(coins), Color("ffd9a0"))


## 玻璃「膜」:从首页大卡的素材(assets/frames/glass.png)裁一条反光带,
## 按目标矩形的纵横比取源(不压扁点阵),圆角多边形 + UV 贴上去 ——
## 让顶栏/页标题栏和大卡是**同一块材质**(2026-08-12 用户:「顶部信息栏的
## 光泽感配不上下面的玻璃板」)。素材缺席时静默退回纯程序化,探针照跑。
static func glass_film(ci: CanvasItem, r: Rect2, radius := 18.0, alpha := 0.9) -> void:
	var tex := Widgets.StageCard.glass_tex(true)
	if tex == null:
		return
	# 源带:横向避开 40px 霓虹轨(70..772),纵向从反光楔上沿起取同比例高
	var src := Rect2(70.0, 58.0, 702.0, 702.0 * r.size.y / r.size.x)
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var centers := [
		Vector2(r.end.x - radius, r.position.y + radius),
		Vector2(r.end.x - radius, r.end.y - radius),
		Vector2(r.position.x + radius, r.end.y - radius),
		Vector2(r.position.x + radius, r.position.y + radius),
	]
	for k in range(4):
		for i in range(9):
			var ang := -PI * 0.5 + PI * 0.5 * (float(k) + float(i) / 8.0)
			pts.append(centers[k] + Vector2(cos(ang), sin(ang)) * radius)
	for p in pts:
		var u := src.position + (p - r.position) / r.size * src.size
		uvs.append(Vector2(u.x / tw, u.y / th))
	ci.draw_colored_polygon(pts, Color(1, 1, 1, alpha), uvs, tex)


## 货币章(原 home.gd::_chip)。
static func chip(ci: CanvasItem, r: Rect2, acc: Color, glyph: String, val: String,
		ink: Color) -> void:
	ci.draw_style_box(StageTheme.box(Color(acc.r * 0.22, acc.g * 0.16, acc.b * 0.10, 0.45),
		Color(acc.r, acc.g, acc.b, 0.45), 1, 13), r)
	var mid := r.position.y + r.size.y * 0.5
	ci.draw_string(StageTheme.zh(), Vector2(r.position.x + 12.0, mid + 6.0), glyph,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, acc)
	ci.draw_string(StageTheme.num("Bold"), Vector2(r.position.x + 36.0, mid + 7.0), val,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 19, ink)
	ci.draw_arc(Vector2(r.end.x - 18.0, mid), 9.0, 0, TAU, 22,
		Color(acc.r, acc.g, acc.b, 0.6), 1.2, true)
	ci.draw_string(StageTheme.num("Medium"), Vector2(r.end.x - 26.0, mid + 6.0), "+",
		HORIZONTAL_ALIGNMENT_CENTER, 16.0, 15, acc)


## 斜雨(原 home.gd::_draw_rain)。无雨规则只管局内舞台;首页/图鉴/失败屏
## 的设计稿都带雨。
static func rain(ci: CanvasItem, t: float) -> void:
	var col := Color(0.71, 0.86, 1.0, 0.20 * 0.35)
	var drift: float = fmod(t / 1.3, 1.0)
	for i in range(58):
		var bx: float = fmod(float(i) * 47.0 - drift * 80.0, W + 200.0) - 100.0
		var by: float = fmod(float(i) * 131.0 + drift * 900.0, H + 300.0) - 150.0
		ci.draw_line(Vector2(bx, by), Vector2(bx - 7.0, by + 34.0), col, 1.4, true)
	var col2 := Color(0.59, 0.78, 1.0, 0.12 * 0.35)
	for i in range(34):
		var bx2: float = fmod(float(i) * 79.0 - drift * 60.0, W + 200.0) - 100.0
		var by2: float = fmod(float(i) * 211.0 + drift * 760.0, H + 300.0) - 150.0
		ci.draw_line(Vector2(bx2, by2), Vector2(bx2 - 6.0, by2 + 58.0), col2, 1.2, true)


## 辉光 + 实心字(原 home.gd::_neon,设计稿 text-shadow 0 0 12px / 0 0 34px)。
static func neon(ci: CanvasItem, font: Font, txt: String, at: Vector2, fs: int,
		core: Color, glow: Color, width := -1.0) -> void:
	var align := HORIZONTAL_ALIGNMENT_LEFT if width < 0.0 else HORIZONTAL_ALIGNMENT_CENTER
	var w: float = width if width > 0.0 else -1.0
	for ring in [[3.2, 8, 0.12], [1.6, 6, 0.14]]:
		var rad: float = float(ring[0])
		var n: int = int(ring[1])
		var a: float = float(ring[2])
		for i in range(n):
			var ang := TAU * float(i) / float(n)
			ci.draw_string(font, at + Vector2(cos(ang), sin(ang)) * rad, txt, align, w, fs,
				Color(glow.r, glow.g, glow.b, a))
	ci.draw_string(font, at, txt, align, w, fs, core)


## 头像圆盘:把 512×512 头像按 manifest 的 avatar_crop 取最大内切圆,
## UV 多边形贴出来(原 home.gd 内联的那段)。
static func avatar_disc(ci: CanvasItem, c: Vector2, rad: float, tex: Texture2D,
		crop: Rect2) -> void:
	var ucx := crop.position.x + crop.size.x * 0.5
	var ucy := crop.position.y + crop.size.y * 0.5
	var ur := minf(crop.size.x, crop.size.y) * 0.5
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in range(40):
		var a := TAU * float(i) / 40.0
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
		uvs.append(Vector2(ucx + cos(a) * ur, ucy + sin(a) * ur))
	ci.draw_colored_polygon(pts, Color.WHITE, uvs, tex)
