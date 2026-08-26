class_name Chrome
extends RefCounted

## 两屏共用的全局 chrome:首页 + 小丑牌图鉴页(2026-08-11 从 home.gd 迁出成单源;
## 2026-08-24 局外 build 删除后, 主角/荣誉两页与货币章/头像圆盘一起退役)。
## 这里只放「每个页面都要画的那几件」:底部页签轨、页标题栏、斜雨、霓虹字。
## 页面自己的内容各回各家。

const W := 720.0
const H := 1280.0
const TABS := ["关卡", "小丑牌"]

# 轨几何与 home.gd 原值一致(卡片外框 24 + 44 = 68 起);轨总宽恒 584, 均分给页签
const TAB_X0 := 68.0
const TAB_W := 292.0          # (672 - 88) / 2
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
			Lingo.t(TABS[i]), HORIZONTAL_ALIGNMENT_CENTER, TAB_W, 20, col)
		if on:
			var u := Rect2(r.position.x + TAB_W * 0.5 - 16.0, r.position.y + TAB_UNDER_DY,
				32.0, 2.5)
			ci.draw_style_box(StageTheme.box(acc, Color(0, 0, 0, 0), 0, 2), u)


## 页签的线稿图标(设计稿 SVG path 的简化临摹)。
static func tab_icon(ci: CanvasItem, i: int, c: Vector2, col: Color, scale := 1.0) -> void:
	var wd := 2.0 * scale
	var s := scale
	match i:
		0:      # 关卡: a card with a diamond
			ci.draw_rect(Rect2(c - Vector2(15, 20) * s, Vector2(30, 40) * s), col, false, wd)
			ci.draw_polyline(PackedVector2Array([c + Vector2(0, -9) * s, c + Vector2(9, 0) * s,
				c + Vector2(0, 9) * s, c + Vector2(-9, 0) * s, c + Vector2(0, -9) * s]),
				col, wd, true)
		_:      # 小丑牌: the jester crown
			ci.draw_polyline(PackedVector2Array([c + Vector2(-18, 14) * s, c + Vector2(-12, -12) * s,
				c + Vector2(-4, 2) * s, c + Vector2(0, -16) * s, c + Vector2(4, 2) * s,
				c + Vector2(12, -12) * s, c + Vector2(18, 14) * s, c + Vector2(-18, 14) * s]),
				col, wd, true)


## 图鉴页的页标题栏:玻璃条 + 标题/副行。(货币章 2026-08-24 随宝石退役。)
static func page_bar(ci: CanvasItem, title: String, sub: String, acc: Color) -> void:
	var bar := Rect2(44.0, 22.0, W - 88.0, 82.0)
	Widgets.StageCard.draw_card(ci, bar, acc, 22.0, 8.0, false)
	glass_film(ci, bar.grow(-2.0), 20.0)
	var r := bar.grow(-8.0)
	ci.draw_string(StageTheme.zh(), Vector2(r.position.x + 18.0, r.position.y + 30.0), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("eaf6ff"))
	ci.draw_string(StageTheme.zh(), Vector2(r.position.x + 18.0, r.position.y + 52.0), sub,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("7487ac"))


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


## 斜雨(原 home.gd::_draw_rain)。无雨规则只管局内舞台;首页/图鉴/失败屏
## 的设计稿都带雨。
## ⚑ 静态页的「动效层」(2026-08-21 评审:首页/三个图鉴页/荣誉页此前在 `_process` 里每帧
## 无条件 `queue_redraw()` 整屏重画 —— 程序化玻璃 + 几十次 draw_string 每秒 60 遍, 而真正在动的
## 只有雨。手机上首页是停留最久的屏, 这就是发热来源)。
## 用法:页面 `_ready` 里 `add_child(Chrome.RainLayer.new())` 挂在最后(雨要压在所有内容上面);
## `_process` 里只 `tick(delta)` 这一层;自己的静态内容改成**状态键变了才重画**(`Chrome.dirty()`)。
class RainLayer:
	extends Control
	var t := 0.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		position = Vector2.ZERO
		size = Vector2(Chrome.W, Chrome.H)
	func tick(delta: float) -> void:
		t += delta
		queue_redraw()
	func _draw() -> void:
		Chrome.rain(self, t)


## 「状态键变了才重画」的一行判据:页面把会影响自己 _draw 的全部状态放进 key 数组,
## 每帧比一次;变了返回 true(并记住新键)。⚠ 漏放一个量的后果是「那个量变了画面不刷新」——
## 所以 key 宁可多放(读一个 int 的代价远小于整屏重画)。
static func dirty(holder: Dictionary, key: Array) -> bool:
	if holder.get("k", null) == key:
		return false
	holder["k"] = key
	return true


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


