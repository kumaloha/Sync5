class_name HomeScreen
extends Control

## The game's front page, 1:1 from the user's mock in docs/mockups/home.html
## (the authority for this screen, like success/fail.html are for the result
## screens).
##
## Layout: 无框顶栏(♪盘/LV/NEON PLAYER/EXP/⚡体力/分享)→ the big glass STAGE CARD
## → tab rail。顶栏两端的视觉边缘对齐卡的玻璃亮边(x 56/664, 2026-08-24 实量)。The card is the
## same object as the in-game blind board (`Widgets.StageCard` +
## `Widgets.BlindBoard`) because a level IS a blind — swiping it browses the
## tour's 12 blinds, it does NOT pick one: 盲注不可跳过 is user-locked, so
## 开始游戏 always starts a fresh tour at BLIND 01.
##
## Everything is drawn in _draw() driven by _process; hit-testing lives in
## _gui_input (children would paint over the card, per the project rule).
## `frame-glass4.png` from the mock is not in the repo — the frame is drawn.

signal start_pressed          # 开始游戏 → run starts
signal menu_pressed(idx: int) # 页签 → 图鉴页(1 小丑牌)
signal share_pressed          # 顶栏分享按钮(打点在编排器, 铁律)

const W := 720.0
const H := 1280.0

# card geometry, straight from the mock
## 卡片与页签整体比设计稿下移 64:两者相对距离不变(页签仍压在卡片下沿上 20),
## 页签的文字/下划线因此贴到屏幕底部(用户 2026-08-05:「让 menu 到屏幕底部」「还可以
## 下移一点」)。卡片同时加宽 —— 它的霓虹轨要和顶部信息栏**等宽**(见下)。
const CARD := Rect2(24.0, 172.0, 672.0, 972.0)
const PAD_L := 78.0                       # card inner padding (left/right)
const PAD_T := 82.0
const CARD_INSET := 24.0                  # 霓虹轨距外框(玻璃的可见边)
## 竖向节奏一次对齐(用户:「上下的间距可以一致吗」)——四个间距全部核过:
##   屏幕上边距 26 → 信息栏(可见高 122) → **48** → 卡片(可见高 924) → **48**
##   → 页签块(高 ~88) → 屏幕下边距 ~24
## 即卡片上下各 48、屏幕上下各 ~25。改任何一个都要重算其余三个:
## 总高 = 2×外边距 + 信息栏 + 2×48 + 924 + 页签块 = 1280。
# 页签轨几何在 Chrome(2026-08-11 三个图鉴页实装时迁出成四屏单源);
# 下缝 51 比上缝多 3px 的理由不变:抵消倒影的光填缝带来的偏紧观感。

var section_idx := 0          # which blind the card is showing
var tab := 0

var _t := 0.0
var _drag_from := -1.0        # x where the current drag started, -1 = idle
var _drag_dx := 0.0
var _stamp := ""          # build_stamp.txt(commit+时间), 没有就空 = 不画
var _btn_rect := Rect2()
var _dot_rects: Array = []
var _tab_rects: Array = []
var _share_rect := Rect2() # 顶栏分享按钮的点击区(_draw_player_bar 排版时记下)
var _share_t := 0.0        # 「已复制」提示的剩余秒数(动效层画, 见 draw_fx)

static var _bg: GradientTexture2D = null
static var _sheen: GradientTexture2D = null   # 115° 斜光带(v5 稿 line 25)
var _tail: Control = null
var _fx: Control = null          # 动效层:雨 / 均衡器 / 脉冲按钮 / 扫描线(唯一每帧重画的层)
var _eq_rect := Rect2()          # 静态层排版时记下, 动效层照着画
var _key: Dictionary = {}        # 静态层上次重画时的状态键(Chrome.dirty)


## 倒影层。必须是**独立子节点 + shader 遮罩**: 渐隐要统一作用在 StyleBox 上,
## 盖一张渐变矩形只能糊颜色、盖不住 alpha(docs/design/ui_meta.md 渲染手法)。
## 注意 z_index 不能设成负的: 子节点会因此画在父节点 _draw() **之前**,
## 而 _draw_bg() 是铺满整屏的, 会把倒影整个盖掉(踩过)。留默认值即可 ——
## 子节点本来就画在 _draw() 之后, 倒影很淡, 盖在页签上正是设计稿的样子。
class TailLayer:
	extends Control
	var home: HomeScreen = null
	func _draw() -> void:
		if home != null:
			home.draw_tail(self)


## 动效层(2026-08-21 评审:首页此前每帧整屏重画 —— 程序化玻璃 + 3 个 neon + ~40 次 draw_string
## 每秒 60 遍, 而真正在动的只有雨 / 均衡器 / 按钮脉冲 / 扫描线。手机上首页是停留最久的屏)。
## 这四样搬到这层每帧画;本体只在状态键变了才重画(`_process` 里的 `Chrome.dirty`)。
## ⚠ 层序:它加在倒影层之后 ⇒ 雨压在倒影上(此前雨在倒影下), 倒影极淡、肉眼不可辨。
class FxLayer:
	extends Control
	var home: HomeScreen = null
	func _draw() -> void:
		if home != null:
			home.draw_fx(self)


func _ready() -> void:
	position = Vector2.ZERO
	size = Vector2(W, H)
	var sf := FileAccess.open("res://build_stamp.txt", FileAccess.READ)
	if sf != null:
		_stamp = sf.get_as_text().strip_edges()
		sf.close()
	# above the battle scene's own z_index users(局内组件用到 z 20 一带)
	z_index = 80
	# 玻璃壳走素材时(assets/frames/glass.png,2026-08-12 用户拍板换素材)
	# 倒影已经烘在图里(y 1197–1355 那段),再挂镜像层就是双影 —— 跳过。
	if Widgets.StageCard.glass_tex(true) == null:
		_tail = TailLayer.new()
		_tail.home = self
		_tail.position = Vector2.ZERO
		_tail.size = Vector2(W, H)
		_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 渐隐从霓虹轨底边起算, 和镜像轴对齐。带高按卡高的 6%——再长就会把整排页签
		# 圈进去、读成"第二块板"(用户两次都指出过)。
		_tail.material = Widgets.StageCard.mirror_material(
			CARD.end.y - CARD_INSET, CARD.size.y * Widgets.StageCard.TAIL_RATIO, 0.62)
		add_child(_tail)
	_fx = FxLayer.new()
	_fx.home = self
	_fx.position = Vector2.ZERO
	_fx.size = Vector2(W, H)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx)
	# 背景纹理提前建 + 生成完补一次重画(GradientTexture2D 像素生成延迟, 首帧可能是白占位;
	# 本层又只按状态键重画, 不补这一枪白就钉住了 —— 2026-08-24 二分抓到的形状)
	_ensure_bg_textures()
	get_tree().create_timer(0.1).timeout.connect(queue_redraw)
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	# the swipe eases back once released
	if _drag_from < 0.0 and absf(_drag_dx) > 0.5:
		_drag_dx = lerpf(_drag_dx, 0.0, minf(1.0, delta * 14.0))
	if _fx != null:
		_fx.queue_redraw()
	if _share_t > 0.0:
		_share_t = maxf(0.0, _share_t - delta)
	# 静态层与倒影:状态键变了才重画。键里放的是 _draw 读到的全部可变量(漏一个 = 那个量变了不刷新)
	if Chrome.dirty(_key, [section_idx, tab, snappedf(_drag_dx, 0.25), _stamp,
			SaveState.energy(), SaveState.profile()]):
		queue_redraw()
		if _tail != null:
			_tail.queue_redraw()


# ============================== INPUT ==============================

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_drag_from = ev.position.x
			_drag_dx = 0.0
		else:
			var moved := absf(_drag_dx)
			var from := _drag_from
			_drag_from = -1.0
			if moved > 60.0:
				_step(1 if _drag_dx < 0.0 else -1)
				_drag_dx = 0.0
				return
			if from >= 0.0 and moved < 12.0:
				_tap(ev.position)
	elif ev is InputEventMouseMotion and _drag_from >= 0.0:
		_drag_dx = clampf(ev.position.x - _drag_from, -90.0, 90.0)


func _step(dir: int) -> void:
	section_idx = posmod(section_idx + dir, GameConfig.SECTIONS_PER_RUN)


func _tap(p: Vector2) -> void:
	if _btn_rect.has_point(p):
		start_pressed.emit()
		return
	if _share_rect.grow(8.0).has_point(p):
		# 分享 v1 = 复制文案进剪贴板(桌面/Web 都通;真正的系统分享面板等平台侧需求)。
		DisplayServer.clipboard_set(Lingo.t("Sync5 · 我的巡演已开 %d 局") % SaveState.runs_total())
		_share_t = 1.8
		share_pressed.emit()
		return
	if PEEK_L.grow(6.0).has_point(p):
		_step(-1)
		return
	if PEEK_R.grow(6.0).has_point(p):
		_step(1)
		return
	for i in range(_dot_rects.size()):
		var r: Rect2 = _dot_rects[i]
		if r.grow(6.0).has_point(p):
			section_idx = i
			return
	for i in range(_tab_rects.size()):
		var tr: Rect2 = _tab_rects[i]
		if not tr.has_point(p):
			continue
		if i == 0:
			tab = 0
		else:
			menu_pressed.emit(i)      # 图鉴页由编排器开(phrase._open_menu)
		return


# ============================== DRAW ==============================

func _draw() -> void:
	_draw_bg()
	_draw_player_bar()
	_draw_card()
	_draw_tabs()
	# 构建戳:一天十个包的节奏下「手机跑的是哪一版」必须一眼可对 ——
	# 「改了但变化不大」的头号嫌疑是浏览器缓存的陈旧 pck, 有戳才分得清。
	if _stamp != "":
		draw_string(StageTheme.num("Medium"), Vector2(10.0, H - 8.0), _stamp,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.25))


## 夜色渐变 + 三团角落柔光 + 115° 斜光带 —— 逐值取自 `docs/mockups/home.html`(v5,
## 2026-08-24 用户:「顶部没有边框之后背景是纯黑, 但我给你发的图里面不是纯黑的」+
## 「参考这个 html 代码实现」)。⚑ 这三件套正是 08-06「背景归黑/柔光全删」拍板删掉的
## 结构, v5 设计稿把它请回首页;**局内**背景仍按归黑拍板走(stage_bg 不动)。
func _draw_bg() -> void:
	if _bg == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 0.78, 1.0])
		# 稿:linear-gradient(180deg,#070a1a 0%,#0a0d22 45%,#05060f 78%,#03030a 100%)
		g.colors = PackedColorArray([Color("070a1a"), Color("0a0d22"),
			Color("05060f"), Color("03030a")])
		_bg = GradientTexture2D.new()
		_bg.gradient = g
		_bg.width = 8
		_bg.height = 512
		_bg.fill_from = Vector2(0, 0)
		_bg.fill_to = Vector2(0, 1)
	draw_texture_rect(_bg, Rect2(0, 0, W, H), false)
	# 角落柔光三团(稿 line 24, 椭圆半径×2 = rect 尺寸, 圆心按百分比):
	#   520×300 @ (10%,0%) 青 .16 · 560×320 @ (92%,4%) 粉 .15 · 500×420 @ (50%,46%) 紫 .10
	# ⚠⚠ 纹理**不许在 _draw 里现建**:GradientTexture2D 的像素生成是延迟的, 现建现画
	# 上屏的是**白色占位图**, 而本层只在状态键变化时重画 ⇒ 整屏钉在白上(2026-08-24
	# 二分抓到:基线渐变正确、开柔光即全白)。⇒ 三团 + 斜光带全部建一次缓存在 static。
	_ensure_bg_textures()
	draw_texture_rect(_glows[0], Rect2(72.0 - 520.0, 0.0 - 300.0, 1040.0, 600.0), false)
	draw_texture_rect(_glows[1], Rect2(662.4 - 560.0, 51.2 - 320.0, 1120.0, 640.0), false)
	draw_texture_rect(_glows[2], Rect2(360.0 - 500.0, 588.8 - 420.0, 1000.0, 840.0), false)
	# 115° 斜光带(稿 line 25)。⚠ 必须是**软边渐变**, 硬边 draw_line 会把上半屏洗白
	# (第一版就是这么糊的, 截图当场抓到)。按 CSS 停点建一条横向渐变, 旋到 115° 轴铺满;
	# CSS 115deg 的渐变线长 ≈ 720·sin115° + 1280·cos115°(取绝对值)= 1193, 轴过屏心。
	draw_set_transform(Vector2(360.0, 640.0), 0.4363)
	draw_texture_rect(_sheen, Rect2(-597.0, -1100.0, 1194.0, 2200.0), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static var _glows: Array = []

static func _ensure_bg_textures() -> void:
	if not _glows.is_empty() and _sheen != null:
		return
	_glows = [
		StageTheme.radial(Color(53.0 / 255, 232.0 / 255, 224.0 / 255, 0.16)),
		StageTheme.radial(Color(1.0, 79.0 / 255, 163.0 / 255, 0.15)),
		StageTheme.radial(Color(165.0 / 255, 107.0 / 255, 1.0, 0.10)),
	]
	var sg := Gradient.new()
	sg.offsets = PackedFloat32Array([0.18, 0.32, 0.39, 0.50, 0.64, 0.76, 0.88])
	sg.colors = PackedColorArray([
		Color(0.627, 0.784, 1.0, 0.0), Color(0.627, 0.784, 1.0, 0.04),
		Color(1.0, 1.0, 1.0, 0.07), Color(1.0, 1.0, 1.0, 0.0),
		Color(0.627, 0.784, 1.0, 0.0), Color(0.627, 0.784, 1.0, 0.05),
		Color(0.627, 0.784, 1.0, 0.0)])
	_sheen = GradientTexture2D.new()
	_sheen.gradient = sg
	_sheen.width = 512
	_sheen.height = 8
	_sheen.fill_from = Vector2(0, 0)
	_sheen.fill_to = Vector2(1, 0)


## (柔光层已于 2026-08-06 整体删除:「柔光层全部给我去掉」。
## 曾有 _draw_soft_light —— 两团 620/900px 的档位色光罩住整张卡, 那才是用户
## 三次说的"光晕"的真身;我却一直在改 StageCard 的边辉光, 所以"毫无变化"。)


## 顶栏(2026-08-24 参考图重做):**无边框、融入黑底** —— 不再画玻璃板,
## 元素直接躺在背景上。左 = 圆盘(♪, 主角已删)+ LV 徽章 + NEON PLAYER + EXP 行;
## 右 = ⚡ 体力(上限 − 今日局数, 只显示不拦人)+ 分享按钮(用户:「不是那个 +」)。
## 金币/紫宝石按拍板不放。数字全真:LV/EXP = 累计通关段数推, 体力 = 真局数推。
func _draw_player_bar() -> void:
	# 2026-08-24 用户:「玻璃卡和顶部之间的间距有点大, 把顶部放大一些、调整位置」——
	# 元素整体放大约 1.25 倍, 内容中线从 87 下移到 116(卡的玻璃边 ~208, 空带收到 ~50px)。
	var r := Rect2(CARD.position.x + CARD_INSET, 40.0,
		CARD.size.x - CARD_INSET * 2.0, 152.0)
	var cy := 116.0
	var num := StageTheme.num("Bold")
	var zh := StageTheme.zh()
	var prof := SaveState.profile()
	# ⚑ 配套变色(2026-08-24 用户:「主玻璃板颜色变了, 光晕、顶部头像圆框颜色都会变,
	# 请注意配套」——v5 稿里圆环/LV 徽章用的就是当前档位色):头像环与 LV 徽章跟卡片
	# 同一个 accent 走, 滑动切关整套一起换色(光晕本来就跟着 acc)。
	var bacc := Widgets.StageCard.accent_for(section_idx)

	# avatar disc + 档位色环, 缺口留给 LV 徽章
	# 左端对卡:环外缘(中心 − 半径40.5 − 线宽半)落在卡玻璃亮边 x=56(实量 08-24)
	var c := Vector2(r.position.x + 50.0, cy - 6.0)
	draw_circle(c, 37.0, Color(0.055, 0.09, 0.16, 0.92))
	var aw := zh.get_string_size("♪", HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	draw_string(zh, c + Vector2(-aw * 0.5, 11.0), "♪", HORIZONTAL_ALIGNMENT_LEFT, -1, 32,
		Color(bacc.r * 0.55 + 0.45, bacc.g * 0.55 + 0.45, bacc.b * 0.55 + 0.45))
	draw_arc(c, 40.5, 0, TAU, 64, Color(bacc.r, bacc.g, bacc.b, 0.85), 2.4, true)
	var lv := "LV.%d" % int(prof["level"])
	var lw := num.get_string_size(lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var lb := Rect2(c.x - lw * 0.5 - 9.0, c.y + 30.0, lw + 18.0, 20.0)
	draw_style_box(StageTheme.box(bacc, Color(0, 0, 0, 0), 0, 10), lb)
	draw_string(num, Vector2(lb.position.x, lb.position.y + 14.5), lv,
		HORIZONTAL_ALIGNMENT_CENTER, lb.size.x, 13, Color("0a1420"))

	# name + EXP(参考图的两行;名字是**标签不是存档数据** —— 没有玩家档案系统)
	var tx := r.position.x + 108.0
	draw_string(num, Vector2(tx, cy - 8.0), "N E O N   P L A Y E R",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color("f2f7ff"))
	draw_string(StageTheme.num("Medium"), Vector2(tx, cy + 19.0),
		"EXP %d / %d" % [int(prof["xp"]), int(prof["xp_max"])],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("7487ac"))

	# 分享按钮(最右圆钮)。图标 = 三点两线的 share 形。
	# 右端对卡:分享钮外缘落在卡玻璃亮边 x=664(同一次实量)
	var sc := Vector2(r.end.x - 29.0, cy)
	_share_rect = Rect2(sc - Vector2(20.0, 20.0), Vector2(40.0, 40.0))
	draw_circle(sc, 20.0, Color(1, 1, 1, 0.05))
	draw_arc(sc, 20.0, 0, TAU, 48, Color(1, 1, 1, 0.20), 1.3, true)
	var p1 := sc + Vector2(6.0, -7.5)
	var p2 := sc + Vector2(-6.0, 0.0)
	var p3 := sc + Vector2(6.0, 7.5)
	var sink := Color(0.83, 0.88, 1.0, 0.85)
	draw_line(p2, p1, sink, 1.6, true)
	draw_line(p2, p3, sink, 1.6, true)
	for pt in [p1, p2, p3]:
		draw_circle(pt, 3.1, sink)

	# ⚡ 体力(分享钮左侧;深底小胶囊, 与参考图同族)
	var etxt := "%d/%d" % [SaveState.energy(), SaveState.energy_max()]
	var ew := num.get_string_size(etxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var pill := Rect2(sc.x - 20.0 - 30.0 - (ew + 54.0), cy - 19.0, ew + 54.0, 38.0)
	draw_style_box(StageTheme.box(Color(0.05, 0.06, 0.11, 0.85),
		Color(1, 1, 1, 0.08), 1, 19), pill)
	draw_string(zh, Vector2(pill.position.x + 15.0, cy + 7.0), "⚡",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 19, StageTheme.GOLD)
	draw_string(num, Vector2(pill.position.x + 40.0, cy + 7.5), etxt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("eef3ff"))


## The stage card — one blind of the tour, in the same glass language the
## in-game blind board uses.
func _draw_card() -> void:
	var acc := Widgets.StageCard.accent_for(section_idx)
	var is_wall := GameConfig.is_wall(section_idx)
	var card := Rect2(CARD.position + Vector2(_drag_dx, 0.0), CARD.size)
	# ⚑ 整卡外圈光晕(v5 稿:`filter:drop-shadow(0 0 26px cGlow)`)。
	# ⚠ 三版技法史, 前两版都翻车且截图当场抓到:StyleBox shadow = 整面填充, 半屏泡色;
	# 描边环 = 拐角露缝, 读成「第二个圈」(用户点名)。⇒ 只能做**真模糊剪影**:
	# 低分辨率画圆角矩形剪影 → 双线性缩放来回近似高斯 → 缓存贴图, 画时按档位色调制。
	# 画在壳的真实覆盖区(含倒影尾)外扩 pad×5;掺 22% 白提亮芯, 强度经三轮校淡。
	var hrect := Rect2(card.position - Vector2(120.0, 120.0),
		Vector2(card.size.x + 240.0, card.size.y * 1.132 + 240.0))
	draw_texture_rect(_halo_tex(), hrect, false,
		Color(acc.r * 0.78 + 0.22, acc.g * 0.78 + 0.22, acc.b * 0.78 + 0.22, 0.30))
	# 传外框: 玻璃体的内缩(设计稿 inset:34px)由 StageCard 自己处理,
	# 文字排版按外框算(PAD_L/PAD_T 相对外框), 两边都不用改。
	Widgets.StageCard.draw_card(self, card, acc, 26.0, CARD_INSET, true)
	# 侧条:邻卡玻璃壳「探进屏」的一条边(v5 稿两条 32×520 @y300, opacity .42;
	# 点击切关 —— 命中区在 _tap, 与滑动/圆点同一个 _step 出口)。
	_draw_side_peeks()

	var x := card.position.x + PAD_L
	var cw := card.size.x - PAD_L * 2.0
	var zh := StageTheme.zh()
	var num := StageTheme.num("Bold")
	var med := StageTheme.num("Medium")
	var dim := Color(acc.r, acc.g, acc.b, 0.62)
	var y := card.position.y + PAD_T

	# header row: MODE + the two layout glyphs from the mock
	draw_string(med, Vector2(x, y + 12.0), "MODE: STAGE", HORIZONTAL_ALIGNMENT_LEFT, cw, 14, dim)
	for i in range(2):
		var g := Rect2(x + cw - 51.0 + float(i) * 29.0, y, 22.0, 16.0)
		draw_rect(g, Color(acc.r, acc.g, acc.b, 0.6), false, 1.0)
		if i == 0:
			draw_rect(Rect2(g.position + Vector2(3, 4), Vector2(16, 2)), Color(acc.r, acc.g, acc.b, 0.6), true)
			draw_rect(Rect2(g.position + Vector2(3, 10), Vector2(16, 2)), Color(acc.r, acc.g, acc.b, 0.6), true)
		else:
			for q in range(4):
				draw_rect(Rect2(g.position + Vector2(3.0 + float(q % 2) * 9.0,
					3.0 + float(q / 2) * 6.0), Vector2(7, 4)), Color(acc.r, acc.g, acc.b, 0.6), true)

	# hero row: venue name + blind index
	y += 20.0
	var venue := GameConfig.gig_name(section_idx)
	Chrome.neon(self, zh, venue, Vector2(x, y + 44.0), 48, Color("ffffff"), acc)
	draw_string(med, Vector2(x, y + 44.0), "BLIND %02d/%02d" % [section_idx + 1,
		GameConfig.SECTIONS_PER_RUN], HORIZONTAL_ALIGNMENT_RIGHT, cw, 14, dim)
	# blind tier chip under the name
	y += 56.0
	var tier := Lingo.t("BOSS 墙") if is_wall else GameConfig.blind_name(section_idx)
	var tw := zh.get_string_size(tier, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	var chip := Rect2(x, y, tw + 24.0, 30.0)
	draw_style_box(StageTheme.box(Color(acc.r, acc.g, acc.b, 0.16),
		Color(acc.r, acc.g, acc.b, 0.65), 1, 8), chip)
	draw_string(zh, Vector2(chip.position.x, chip.position.y + 21.0), tier,
		HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, 17, Color("f2fbff"))
	draw_string(zh, Vector2(chip.end.x + 12.0, chip.position.y + 21.0),
		Lingo.t("第 %d 场演出") % [GameConfig.gig_of(section_idx) + 1],
		HORIZONTAL_ALIGNMENT_LEFT, cw, 15, StageTheme.DIM)
	y += 38.0
	Widgets.StageCard.rule_line(self, x, y, cw, acc)

	# the equaliser: the card's biggest visual, exactly as the mock has it
	y += 10.0
	_eq_rect = Rect2(x, y, cw, 372.0)        # 均衡器在动效层画(draw_fx)
	y += 372.0 + 14.0

	# target + reward
	var ttxt := StageTheme.fmt_thousands(GameConfig.section_target(section_idx))
	Chrome.neon(self, num, ttxt, Vector2(x, y + 36.0), 40, Color("ffffff"), acc)
	var tnw := num.get_string_size(ttxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	draw_string(zh, Vector2(x + tnw + 10.0, y + 36.0), Lingo.t("目标分"),
		HORIZONTAL_ALIGNMENT_LEFT, cw, 16, StageTheme.DIM)
	draw_string(med, Vector2(x, y + 34.0), Lingo.t("奖励 ◆%d") % GameConfig.SECTION_CLEAR_REWARD,
		HORIZONTAL_ALIGNMENT_RIGHT, cw, 17,
		Color(StageTheme.GOLD.r, StageTheme.GOLD.g, StageTheme.GOLD.b, 0.95))

	# limits + difficulty stars (tier read, not a save record)
	y += 54.0
	# 弃牌免费(08-06 拍板)—— 此前这里公示「弃牌 ◆0/张」, 是收费时代的遗物(评审)
	draw_string(zh, Vector2(x, y), Lingo.t("%d 乐句 · %.0f 秒/句 · 弃牌免费") %
		[GameConfig.PHRASES_PER_SECTION, GameConfig.phrase_duration(section_idx)],
		HORIZONTAL_ALIGNMENT_LEFT, cw, 16, StageTheme.DIM)
	# 星数 = 段数(tier_stars 返回 1..N);此前写死 3 颗, 第 3/4 段都是 ★★★, 递进断了一档
	var stars := Widgets.StageCard.tier_stars(section_idx)
	var n_star := GameConfig.SECTIONS_PER_RUN
	for i in range(n_star):
		var sc: Color = StageTheme.GOLD if i < stars else Color(0.47, 0.59, 0.78, 0.3)
		draw_string(zh, Vector2(x + cw - 23.0 * float(n_star) + 1.0 + float(i) * 23.0, y), "★",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, sc)
	y += 12.0
	Widgets.StageCard.rule_line(self, x, y, cw, acc, true)

	# boss-rule row: eq icon, the rule text, and two module glyphs
	y += 14.0
	var ib := Rect2(x, y, 42.0, 42.0)
	draw_style_box(StageTheme.box(Color(acc.r, acc.g, acc.b, 0.06),
		Color(acc.r, acc.g, acc.b, 0.7), 1, 10), ib)
	for i in range(3):
		var bh: float = [8.0, 16.0, 12.0][i]
		draw_rect(Rect2(ib.position.x + 11.0 + float(i) * 7.0, ib.end.y - 9.0 - bh, 5.0, bh),
			acc, true)
	draw_string(med, Vector2(x + 54.0, y + 14.0), Lingo.t("BOSS 规则"),
		HORIZONTAL_ALIGNMENT_LEFT, cw - 160.0, 13, dim)
	# the run's faces are rolled at run start and previewed one blind ahead —
	# at home the honest answer is the mechanism, not a fabricated face
	var rule := Lingo.t("开局掷定 · 前一盲注公示预告") if is_wall else Lingo.t("无 · 常规盲注")
	draw_string(zh, Vector2(x + 54.0, y + 36.0), rule,
		HORIZONTAL_ALIGNMENT_LEFT, cw - 160.0, 19, Color("f4f0ff"))
	var c1 := Vector2(x + cw - 63.0, y + 21.0)
	draw_arc(c1, 21.0, 0, TAU, 32, Color(acc.r, acc.g, acc.b, 0.7), 1.5, true)
	draw_string(zh, Vector2(c1.x - 21.0, c1.y + 7.0), "♪", HORIZONTAL_ALIGNMENT_CENTER, 42.0, 18, acc)
	var b2 := Rect2(x + cw - 42.0, y, 42.0, 42.0)
	draw_style_box(StageTheme.box(Color(acc.r, acc.g, acc.b, 0.06),
		Color(acc.r, acc.g, acc.b, 0.7), 1, 10), b2)
	draw_string(zh, Vector2(b2.position.x, b2.position.y + 27.0), "✦",
		HORIZONTAL_ALIGNMENT_CENTER, b2.size.x, 16, acc)

	# 开始游戏 — the mock's pulsing primary
	y += 58.0
	_btn_rect = Rect2(x, y, cw, 76.0)        # 脉冲按钮在动效层画(draw_fx);这里只记点击区

	# blind dots (12) — tap to browse, they never gate the start
	y += 89.0
	_dot_rects = []
	var n := GameConfig.SECTIONS_PER_RUN
	var dw := 8.0
	var sel_w := 28.0
	var gap := 9.0
	var total: float = float(n - 1) * (dw + gap) + sel_w
	var dx := x + (cw - total) * 0.5
	for i in range(n):
		var wid: float = sel_w if i == section_idx else dw
		var dr := Rect2(dx, y, wid, 7.0)
		_dot_rects.append(dr)
		var dc: Color = Widgets.StageCard.accent_for(i) if i == section_idx \
			else Color(0.47, 0.59, 0.78, 0.3)
		if GameConfig.is_wall(i) and i != section_idx:
			dc = Color(StageTheme.PINK.r, StageTheme.PINK.g, StageTheme.PINK.b, 0.45)
		draw_style_box(StageTheme.box(dc, Color(0, 0, 0, 0), 0, 4), dr)
		dx += wid + gap
	draw_string(StageTheme.zh(), Vector2(x, y + 26.0), Lingo.t("← 左右滑动查看整轮赛程 →"),
		HORIZONTAL_ALIGNMENT_CENTER, cw, 13, Color(0.47, 0.59, 0.78, 0.45))

	# tech footer
	y += 42.0
	var foot := Color(acc.r, acc.g, acc.b, 0.42)
	var lines_l := ["NEON RAIN STAGE SYSTEM V2.6",
		"SYNC MODULE · PATTERN %02dB LOADED" % (section_idx + 1),
		"AUDIO LINK ESTABLISHED · 44.1KHZ"]
	var lines_r := ["DECK: STANDARD 52",
		# 2026-08-06: 每场只有一个盲注了, `SECTIONS_PER_GIG` 恒为 1 —— 这行要讲的
		# 是「全程有几档」, 所以读总段数(四档递进), 否则永远显示 ×1
		"BLIND TIER ×%d · BOSS ARMED" % GameConfig.SECTIONS_PER_RUN,
		"STG-%02d-%d ◉" % [section_idx + 1, GameConfig.section_target(section_idx)]]
	for i in range(3):
		draw_string(med, Vector2(x, y + float(i) * 15.0), lines_l[i],
			HORIZONTAL_ALIGNMENT_LEFT, cw, 10, foot)
		draw_string(med, Vector2(x, y + float(i) * 15.0), lines_r[i],
			HORIZONTAL_ALIGNMENT_RIGHT, cw, 10, foot)



## 侧条几何(v5 稿:left/right 0, top 300, 32×520, 圆角只开朝屏内的一侧)。
const PEEK_L := Rect2(0.0, 300.0, 32.0, 520.0)
const PEEK_R := Rect2(688.0, 300.0, 32.0, 520.0)

## 整卡光晕的模糊剪影贴图(白色, 画时按档位色调制)。建一次缓存 —— 纹理不许在
## _draw 里现建现画(白占位坑, 本文件背景那节踩过);像素级生成所以在这里手做模糊。
static var _halo: ImageTexture = null

## ⚑⚑ 真 drop-shadow(2026-08-24 用户三轮反馈定案:「特效方式不对」)——
## 光晕 = **玻璃壳素材自身 alpha 剪影**的高斯模糊, 不是理想圆角矩形:
## 壳的亮檐、顶弧、倒影尾都要在光里, 光强跟着壳的真实形状走(CSS drop-shadow 的定义)。
## 技法史:StyleBox shadow(整面染色)→ 描边环(第二个圈)→ 距离场(形状是假的)→ 本版。
## pad 给足 3σ, 高斯尾在可见度内自然归零(「到边界停了」那条由此消掉)。
const HALO_PAD := 24          # 图内边距(×5 = 屏幕 120px 衰减跑道)

static func _halo_tex() -> ImageTexture:
	if _halo != null:
		return _halo
	var tex := Widgets.StageCard.glass_tex(true)
	var w := 134 + HALO_PAD * 2      # 卡宽 672 × 1/5
	var h := 220 + HALO_PAD * 2      # 卡高含倒影尾 972×1.132 × 1/5
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	if tex != null:
		var sil: Image = tex.get_image()
		sil.resize(134, 220, Image.INTERPOLATE_BILINEAR)
		# 只留 alpha 剪影(drop-shadow 的定义), 颜色由 draw 端的档位色调制
		for y in range(220):
			for x in range(134):
				var a := sil.get_pixel(x, y).a
				if a > 0.0:
					img.set_pixel(x + HALO_PAD, y + HALO_PAD, Color(1, 1, 1, a))
	else:
		# 无素材兜底(探针环境):矩形剪影, 形状糙但流程不断
		img.fill_rect(Rect2i(HALO_PAD, HALO_PAD, 134, 220), Color(1, 1, 1, 1))
	# 多趟双线性缩放 ≈ 高斯(σ ≈ 6 图px = 30 屏px;pad 24 图px = 4σ, 尾部自然归零)
	for _i in range(3):
		img.resize(w / 4, h / 4, Image.INTERPOLATE_BILINEAR)
		img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	_halo = ImageTexture.create_from_image(img)
	return _halo


## 横向渐隐贴图(侧条的暗罩:屏外侧暗 → 屏内侧透)。同样建一次缓存。
static var _peek_fade: GradientTexture2D = null

func _draw_side_peeks() -> void:
	var tex := Widgets.StageCard.glass_tex(true)
	if _peek_fade == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.016, 0.024, 0.063, 0.30))   # 稿 rgba(4,6,16,.7) × 整体 .42
		g.set_color(1, Color(0.016, 0.024, 0.063, 0.0))
		_peek_fade = GradientTexture2D.new()
		_peek_fade.gradient = g
		_peek_fade.width = 64
		_peek_fade.height = 8
		_peek_fade.fill_from = Vector2(0, 0)
		_peek_fade.fill_to = Vector2(1, 0)
	for side in [[PEEK_L, false], [PEEK_R, true]]:
		var r: Rect2 = side[0]
		var right: bool = side[1]
		# 圆角只开朝屏内的一侧;顺时针从左上起, 圆角处用四分之一弧采样
		var rad := 16.0
		var pts := PackedVector2Array()
		if right:   # 右把手:左侧两个圆角
			pts.append(Vector2(r.end.x, r.position.y))
			pts.append(Vector2(r.end.x, r.end.y))
			_peek_arc(pts, Vector2(r.position.x + rad, r.end.y - rad), rad, PI * 0.5, PI)
			_peek_arc(pts, Vector2(r.position.x + rad, r.position.y + rad), rad, PI, PI * 1.5)
		else:       # 左把手:右侧两个圆角
			pts.append(Vector2(r.position.x, r.position.y))
			_peek_arc(pts, Vector2(r.end.x - rad, r.position.y + rad), rad, PI * 1.5, TAU)
			_peek_arc(pts, Vector2(r.end.x - rad, r.end.y - rad), rad, 0.0, PI * 0.5)
			pts.append(Vector2(r.position.x, r.end.y))
		if tex != null:
			# 源区 = 玻璃素材贴屏那一侧的边缘条(邻卡的壳「探进屏」;稿 background-size
			# 640 × 118%, 露出的是靠窗那 32/640)
			var tw := float(tex.get_width())
			var th := float(tex.get_height())
			var sw := tw * 32.0 / 640.0
			var sx := (tw - sw) if not right else 0.0
			var uvs := PackedVector2Array()
			for p in pts:
				uvs.append(Vector2((sx + (p.x - r.position.x) / r.size.x * sw) / tw,
					clampf((p.y - r.position.y) / (r.size.y * 1.18), 0.0, 1.0)))
			var cols := PackedColorArray()
			for _p in pts:
				cols.append(Color(1, 1, 1, 0.42))
			draw_polygon(pts, cols, uvs, tex)
		else:
			draw_colored_polygon(pts, Color(0.06, 0.08, 0.17, 0.35))
		# 暗罩:屏外侧压暗、向屏内渐透(稿 linear-gradient(90/270deg, rgba(4,6,16,.7), transparent))
		var fuv := PackedVector2Array()
		for p in pts:
			var u := (p.x - r.position.x) / r.size.x
			fuv.append(Vector2(u if right else 1.0 - u, 0.5))
		var fcols := PackedColorArray()
		for _p in pts:
			fcols.append(Color(1, 1, 1, 1))
		draw_polygon(pts, fcols, fuv, _peek_fade)


static func _peek_arc(pts: PackedVector2Array, center: Vector2, radius: float,
		from: float, to: float) -> void:
	for i in range(7):
		var a := from + (to - from) * float(i) / 6.0
		pts.append(center + Vector2(cos(a), sin(a)) * radius)


## CRT 扫描线(v5 稿 line 187 逐值):
##   repeating-linear-gradient(168deg, 34px 透明 + 2px rgba(180,220,255,.20)) 周期 37
## + repeating-linear-gradient(172deg, 58px 透明 + 3px rgba(150,200,255,.12)) 周期 62
## 整层 opacity .35;动画 = 每 1.3s 位移 (-80,900) / (-60,760)。
## 实现:线垂直于渐变轴, 沿轴按周期铺满整屏, 相位 = 位移在轴上的投影 / 1.3s。
func _draw_scanlines(ci: CanvasItem) -> void:
	# ⚠ 周期/速度不按 CSS 原值:稿的 720 画布在 Claude Design 里放大显示, 线距滚速
	# 视觉上都被放大过 —— 按原始 px 实现会「更密更快」(2026-08-24 用户对比拍板)。
	# 周期 ×~1.8、速度约减半, 对齐的是**看上去的样子**, 不是 CSS 数字。
	var fams := [
		# [轴向量, 周期, 线宽, 颜色, 每秒沿轴位移]
		# 亮度再砍半(08-24 用户:「比他的显眼, 太显眼了」—— CSS 原值 ×.35 仍偏亮,
		# 这层该是背景噪纹, 察觉得到、盯不住)
		[Vector2(0.20791, 0.97815), 66.0, 2.2, Color(0.706, 0.863, 1.0, 0.034), 300.0],
		[Vector2(0.13917, 0.99027), 110.0, 3.0, Color(0.588, 0.784, 1.0, 0.020), 255.0],
	]
	for f in fams:
		var axis: Vector2 = f[0]
		var period: float = f[1]
		var lw: float = f[2]
		var col: Color = f[3]
		var speed: float = f[4]
		var perp := Vector2(axis.y, -axis.x)
		# 屏幕四角在轴上的投影范围, 铺满即可(原点取 (0,0))
		var max_s := W * absf(axis.x) + H * absf(axis.y)
		var phase := fmod(_t * speed, period)
		var s := -period + phase
		while s < max_s + period:
			var p0 := axis * s
			ci.draw_line(p0 - perp * 1500.0, p0 + perp * 1500.0, col, lw, true)
			s += period
func draw_tail(ci: CanvasItem) -> void:
	var acc := Widgets.StageCard.accent_for(section_idx)
	var card := Rect2(CARD.position + Vector2(_drag_dx, 0.0), CARD.size)
	Widgets.StageCard.draw_mirror(ci, card, acc, 26.0, CARD_INSET)


## 动效层的内容(每帧):均衡器 · 脉冲按钮 · 扫描线 · 雨。位置全部沿用静态层排版时记下的矩形,
## 所以两层永远对得上;静态层还没画过(首帧)就什么都不画。
func draw_fx(ci: CanvasItem) -> void:
	if _eq_rect.size.x <= 0.0:
		return
	var acc := Widgets.StageCard.accent_for(section_idx)
	var card := Rect2(CARD.position + Vector2(_drag_dx, 0.0), CARD.size)
	var zh := StageTheme.zh()
	var med := StageTheme.num("Medium")
	var dim := Color(acc.r, acc.g, acc.b, 0.62)   # 与 _draw_card 同一支笔
	# the equaliser: the card's biggest visual, exactly as the mock has it
	Widgets.StageCard.eq_band(ci, _eq_rect, acc, _t, section_idx, 34)
	# 开始游戏 — the mock's pulsing primary
	var x := _btn_rect.position.x
	var y := _btn_rect.position.y
	var cw := _btn_rect.size.x
	var pulse: float = 0.86 + 0.14 * (0.5 - 0.5 * cos(_t * TAU / 2.4))
	ci.draw_style_box(StageTheme.box(Color(acc.r * 0.28, acc.g * 0.28, acc.b * 0.28, 0.45),
		Color(acc.r, acc.g, acc.b, 0.7 * pulse), 2, 14,
		Color(acc.r, acc.g, acc.b, 0.34 * pulse), 18), _btn_rect)
	ci.draw_line(_btn_rect.position + Vector2(14, 1.0), _btn_rect.position + Vector2(cw - 14, 1.0),
		Color(1, 1, 1, 0.8), 1.5)
	Chrome.neon(ci, zh, Lingo.t("开 始 游 戏"), Vector2(x, y + 40.0), 28, Color("ffffff"), acc, cw)
	ci.draw_string(med, Vector2(x, y + 62.0), Lingo.t("⚡ 全新巡演 · 从 BLIND 01 开始"),
		HORIZONTAL_ALIGNMENT_CENTER, cw, 14, dim)
	# scan sweep across the card (dcscan)
	var su: float = fmod(_t / 5.5, 1.0)
	var sy: float = card.position.y + card.size.y * (0.04 + 0.90 * su)
	var sa: float = 0.6 * sin(PI * su)
	ci.draw_line(Vector2(card.position.x + 24.0, sy), Vector2(card.end.x - 24.0, sy),
		Color(acc.r, acc.g, acc.b, sa), 2.0)
	# 分享回执(复制进剪贴板后 1.8s 渐隐;挂动效层 —— 本体只在状态键变了才重画)
	if _share_t > 0.0 and _share_rect.size.x > 0.0:
		var ta := clampf(_share_t / 0.6, 0.0, 1.0)
		ci.draw_string(zh, Vector2(_share_rect.end.x - 240.0, _share_rect.end.y + 22.0),
			Lingo.t("已复制分享文案"), HORIZONTAL_ALIGNMENT_RIGHT, 240.0, 14,
			Color(StageTheme.CYAN.r, StageTheme.CYAN.g, StageTheme.CYAN.b, 0.9 * ta))
	# CRT 扫描线(v5 稿 line 187 的「rain」层本尊, 2026-08-24 用户:「类似传统闭路电视
	# 没信号的效果, 整个屏幕, 斜着的光扫描」):两族 168°/172° 的重复细线整屏铺、
	# 压在卡之上(稿 z9 > 卡 z6), 按稿的 background-position 动画 1.3s 无限下滚。
	# ⚠ 不是 Chrome.rain(那是雨点短线段, 图鉴页继续用)—— 这层是**连续长线**在滚。
	_draw_scanlines(ci)


## Bottom rail: 关卡 / 小丑牌。画法在 Chrome(两屏单源);
## 三个图鉴页 2026-08-11 起都有真页面了,「尚未开放」角标一起退役。
func _draw_tabs() -> void:
	_tab_rects = Chrome.tab_rects()
	Chrome.draw_tabs(self, tab, Widgets.StageCard.accent_for(section_idx))
