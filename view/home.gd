class_name HomeScreen
extends Control

## The game's front page, 1:1 from the user's mock in resources/home.html
## (the authority for this screen, like success/fail.html are for the result
## screens).
##
## Layout: player bar → the big glass STAGE CARD → tab rail. The card is the
## same object as the in-game blind board (`Widgets.StageCard` +
## `Widgets.BlindBoard`) because a level IS a blind — swiping it browses the
## tour's 12 blinds, it does NOT pick one: 盲注不可跳过 is user-locked, so
## 开始游戏 always starts a fresh tour at BLIND 01.
##
## Everything is drawn in _draw() driven by _process; hit-testing lives in
## _gui_input (children would paint over the card, per the project rule).
## `frame-glass4.png` from the mock is not in the repo — the frame is drawn.

signal start_pressed          # 开始游戏 → run starts (protagonist pick first)
signal menu_pressed(idx: int) # 页签 → 图鉴页(1 主角 / 2 小丑牌 / 3 荣誉)

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

# meta-progression placeholders: design/ui_meta.md is NOT implemented, so the profile
# numbers are static here on purpose — one dict, clearly fake, easy to wire up
# once a save system exists.
const PROFILE := {"name": "NEON PLAYER", "title": "雨夜俱乐部 VIP", "level": 12,
	"xp": 340, "xp_max": 500, "coins": 2480, "gems": 86}

var section_idx := 0          # which blind the card is showing
var tab := 0

var _t := 0.0
var _avatar_tex: Texture2D = null   # 职业头像(512×512 圆裁);档案栏 mock 期跟 DJ 走
var _avatar_tried := false
## manifest 的 avatar_crop([x,y,w,h] 归一化)——头像是四分之三身像,脸区窗口由美术线
## 在 assets/characters/manifest.json 里给,运行时只读。圆盘取窗口内最大内切圆保纵横比。
var _avatar_crop := Rect2(0.0, 0.0, 1.0, 1.0)
var _drag_from := -1.0        # x where the current drag started, -1 = idle
var _drag_dx := 0.0
var _toast := ""
var _toast_t := 0.0
var _btn_rect := Rect2()
var _dot_rects: Array = []
var _tab_rects: Array = []

static var _bg: GradientTexture2D = null
var _tail: Control = null


## 倒影层。必须是**独立子节点 + shader 遮罩**: 渐隐要统一作用在 StyleBox 上,
## 盖一张渐变矩形只能糊颜色、盖不住 alpha(design/ui_meta.md 渲染手法)。
## 注意 z_index 不能设成负的: 子节点会因此画在父节点 _draw() **之前**,
## 而 _draw_bg() 是铺满整屏的, 会把倒影整个盖掉(踩过)。留默认值即可 ——
## 子节点本来就画在 _draw() 之后, 倒影很淡, 盖在页签上正是设计稿的样子。
class TailLayer:
	extends Control
	var home: HomeScreen = null
	func _draw() -> void:
		if home != null:
			home.draw_tail(self)


func _ready() -> void:
	position = Vector2.ZERO
	size = Vector2(W, H)
	# above the battle scene's own z_index users — the hand-frame Walker sits
	# at 20 and would otherwise walk across the front page
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
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	if _tail != null:
		_tail.queue_redraw()
	if _toast_t > 0.0:
		_toast_t = maxf(0.0, _toast_t - delta)
	# the swipe eases back once released
	if _drag_from < 0.0 and absf(_drag_dx) > 0.5:
		_drag_dx = lerpf(_drag_dx, 0.0, minf(1.0, delta * 14.0))
	queue_redraw()


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
			menu_pressed.emit(i)      # 三个图鉴页由编排器开(phrase._open_menu)
		return


func _float(msg: String) -> void:
	_toast = msg
	_toast_t = 1.6


# ============================== DRAW ==============================

func _draw() -> void:
	_draw_bg()
	_draw_player_bar()
	_draw_card()
	_draw_tabs()
	Chrome.rain(self, _t)
	if _toast_t > 0.0:
		var a: float = minf(1.0, _toast_t / 0.4)
		draw_string(StageTheme.zh(), Vector2(0, Chrome.TAB_Y - 30.0), _toast,
			HORIZONTAL_ALIGNMENT_CENTER, W, 18, Color(1.0, 0.72, 0.82, a))


## Vertical night gradient + three corner glows + the 115° sheen sweep.
func _draw_bg() -> void:
	if _bg == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 0.78, 1.0])
		# 2026-08-06 用户:「我们卡牌底下, 那个背景, 做成黑色吧」——
		# 参考图的五张玻璃卡全躺在纯黑上, 霓虹只有贴在黑上才炸。
		# 底色归零, 画面里的光全部交给角落柔光/扫描线/雨这些**光效层**。
		g.colors = PackedColorArray([Color("000000"), Color("020204"),
			Color("000000"), Color("000000")])
		_bg = GradientTexture2D.new()
		_bg.gradient = g
		_bg.width = 8
		_bg.height = 512
		_bg.fill_from = Vector2(0, 0)
		_bg.fill_to = Vector2(0, 1)
	draw_texture_rect(_bg, Rect2(0, 0, W, H), false)
	# 2026-08-06 用户:「柔光层全部给我去掉」—— 角落柔光、档位色柔光、全屏 sheen
	# 三层**全部删除**。背景就是纯黑, 画面里的光只来自卡片自己那条霓虹边。


func _glow(at: Vector2, sz: Vector2, col: Color, a: float) -> void:
	draw_texture_rect(PaperCard.glow_tex(), Rect2(at - sz * 0.5, sz), false,
		Color(col.r, col.g, col.b, a))


## (柔光层已于 2026-08-06 整体删除:「柔光层全部给我去掉」。
## 曾有 _draw_soft_light —— 两团 620/900px 的档位色光罩住整张卡, 那才是用户
## 三次说的"光晕"的真身;我却一直在改 StageCard 的边辉光, 所以"毫无变化"。)


## Player bar: avatar + LV badge, name/title, XP track, coin and gem chips.
func _draw_player_bar() -> void:
	# 和卡片**等宽**: 卡片的霓虹轨在 x 70..650(外框 40..680 内缩 30), 所以信息栏
	# 的线也要落在 70..650 —— 它自己的内缩是 8, 外框就得往外让 8。
	# **与卡片等宽**: 两者的"线"都落在 x 48..672(卡片外框 24..696 内缩 24)。
	# 信息栏自己的内缩是 8, 所以它的外框再往外让 8。
	# 高度**吃满卡片上方腾出来的空间**(离卡片留 24), 否则卡片下移后上面会空一块
	# (用户:「信息栏没有把下面腾出来的位置补上」)。
	# 顶栏是**全局 chrome**(玩家身份/货币), 不属于任何一关 —— 所以它固定中性近黑,
	# 不跟着盲注档位变色(用户 2026-08-05 提的:「他一直蓝色, 但卡片颜色一直换,
	# 很奇怪」)。这样整屏唯一会变的就是卡片的档位色, 焦点自然落在卡片上。
	# 语义自带颜色的小件不受影响: 头像环、金币金、宝石紫。
	var bar_ins := 8.0
	var bar_top := 18.0
	var r := Rect2(CARD.position.x + CARD_INSET - bar_ins, bar_top,
		CARD.size.x - CARD_INSET * 2.0 + bar_ins * 2.0,
		CARD.position.y - 16.0 - bar_top)
	# 2026-08-06 用户:「顶部信息栏跟下面颜色不同, 好突兀」。根因是**两套做法**:
	# 卡片走新的玻璃体(档位色 from_hsv), 顶栏还是 SLATE 蓝灰 + 半透黑 override,
	# 色温也差着(SLATE 217° vs 青档 174°)。
	# 解法不是让它跟着档位变艳(那条旧拍板还成立: 顶栏是玩家身份/货币, 不属于任何
	# 一关, 滑赛程时整屏换色会吵), 而是**色相跟随、饱和度压到极低** —— 它仍读作
	# "无色玻璃", 但和卡片同一个色温, 并肩放不打架。
	var tier := Widgets.StageCard.accent_for(section_idx)
	# 明度压到 0.42:顶栏是 chrome, 要**退到卡片后面**。给 0.70 时它的灰白线和
	# 渗光在纯黑背景上比档位色卡片还抢眼(实测), 反客为主。
	var acc := Color.from_hsv(tier.h, tier.s * 0.20, 0.42)
	# body 交给统一的玻璃体算法(背景已归黑, 它本来就近黑) —— 不再用 override,
	# 否则顶栏永远是"另一块材质"。
	Widgets.StageCard.draw_card(self, r, acc, 18.0, bar_ins, false)
	# 内容锚在**线**那一圈(= 卡片轨的 70..650), 且按它的中线排 —— 直接 grow 会把
	# 可用高度压掉 16, 右侧两个货币章会被下边线切掉。
	r = r.grow(-bar_ins)
	var cy := r.position.y + r.size.y * 0.5

	# avatar disc —— 2026-08-11 起贴职业头像(512×512 圆裁贴多边形 UV);
	# 档案栏还是 mock(NEON PLAYER/LV),头像跟着 mock 的 DJ 走,选角接入后由所选主角驱动。
	# 缺图退回字母盘 —— 无素材环境的截图探针照跑。
	var c := Vector2(r.position.x + 56.0, cy)
	draw_circle(c, 34.0, Color(0.055, 0.09, 0.16, 0.9))
	var num := StageTheme.num("Bold")
	var zh := StageTheme.zh()
	if _avatar_tex == null and not _avatar_tried:
		_avatar_tried = true
		var ap := "res://assets/characters/dj/avatar.png"
		if ResourceLoader.exists(ap):
			_avatar_tex = load(ap)
			var mf := FileAccess.open("res://assets/characters/manifest.json", FileAccess.READ)
			if mf != null:
				var md = JSON.parse_string(mf.get_as_text())
				mf.close()
				if md is Dictionary:
					for ch in md.get("characters", []):
						if String(ch.get("id", "")) == "dj" and ch.has("avatar_crop"):
							var cr: Array = ch["avatar_crop"]
							_avatar_crop = Rect2(float(cr[0]), float(cr[1]), float(cr[2]), float(cr[3]))
	if _avatar_tex != null:
		Chrome.avatar_disc(self, c, 33.0, _avatar_tex, _avatar_crop)
	else:
		var aw := num.get_string_size("DJ", HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		draw_string(num, c + Vector2(-aw * 0.5, 9.0), "DJ", HORIZONTAL_ALIGNMENT_LEFT, -1, 26,
			Color("8ff5ee"))
	draw_arc(c, 34.0, 0, TAU, 56, Color(StageTheme.CYAN.r, StageTheme.CYAN.g, StageTheme.CYAN.b, 0.8), 1.8, true)
	var lv := "LV.%d" % int(PROFILE["level"])
	var lw := num.get_string_size(lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var lb := Rect2(c.x - lw * 0.5 - 10.0, c.y + 27.0, lw + 20.0, 19.0)
	draw_style_box(StageTheme.box(StageTheme.CYAN, Color(0, 0, 0, 0), 0, 8), lb)
	draw_string(num, Vector2(lb.position.x, lb.position.y + 14.5), lv,
		HORIZONTAL_ALIGNMENT_CENTER, lb.size.x, 13, Color("03302c"))

	# name + title
	var tx := r.position.x + 104.0
	draw_string(num, Vector2(tx, cy - 10.0), String(PROFILE["name"]),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color("eaf6ff"))
	var nw := num.get_string_size(String(PROFILE["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 23).x
	draw_string(zh, Vector2(tx + nw + 10.0, cy - 8.0), String(PROFILE["title"]),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("7487ac"))

	# xp track
	var bar := Rect2(tx, cy + 8.0, 300.0, 8.0)
	draw_style_box(StageTheme.box(Color(0.078, 0.10, 0.21, 0.9),
		Color(0.47, 0.59, 0.78, 0.18), 1, 4), bar)
	var frac: float = float(PROFILE["xp"]) / float(PROFILE["xp_max"])
	var fill := Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y))
	draw_style_box(StageTheme.box(StageTheme.CYAN, Color(0, 0, 0, 0), 0, 4), fill)
	draw_style_box(StageTheme.box(Color(StageTheme.VIOLET.r, StageTheme.VIOLET.g,
		StageTheme.VIOLET.b, 0.75), Color(0, 0, 0, 0), 0, 4),
		Rect2(fill.position + Vector2(fill.size.x * 0.55, 0),
			Vector2(fill.size.x * 0.45, fill.size.y)))
	draw_string(num, Vector2(bar.end.x + 10.0, bar.end.y + 4.0),
		"%d/%d" % [int(PROFILE["xp"]), int(PROFILE["xp_max"])],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("66799f"))

	# currency chips
	Chrome.chip(self, Rect2(r.end.x - 152.0, cy - 36.0, 144.0, 31.0), StageTheme.AMBER,
		"◆", "%d" % int(PROFILE["coins"]), Color("ffd9a0"))
	Chrome.chip(self, Rect2(r.end.x - 152.0, cy + 5.0, 144.0, 31.0), StageTheme.VIOLET,
		"◈", "%d" % int(PROFILE["gems"]), Color("cdb2ff"))


## The stage card — one blind of the tour, in the same glass language the
## in-game blind board uses.
func _draw_card() -> void:
	var acc := Widgets.StageCard.accent_for(section_idx)
	var is_wall := GameConfig.is_wall(section_idx)
	var card := Rect2(CARD.position + Vector2(_drag_dx, 0.0), CARD.size)
	# 传外框: 玻璃体的内缩(设计稿 inset:34px)由 StageCard 自己处理,
	# 文字排版按外框算(PAD_L/PAD_T 相对外框), 两边都不用改。
	Widgets.StageCard.draw_card(self, card, acc, 26.0, CARD_INSET, true)

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
	var tier := "BOSS 墙" if is_wall else GameConfig.blind_name(section_idx)
	var tw := zh.get_string_size(tier, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	var chip := Rect2(x, y, tw + 24.0, 30.0)
	draw_style_box(StageTheme.box(Color(acc.r, acc.g, acc.b, 0.16),
		Color(acc.r, acc.g, acc.b, 0.65), 1, 8), chip)
	draw_string(zh, Vector2(chip.position.x, chip.position.y + 21.0), tier,
		HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, 17, Color("f2fbff"))
	draw_string(zh, Vector2(chip.end.x + 12.0, chip.position.y + 21.0),
		"第 %d 场演出" % [GameConfig.gig_of(section_idx) + 1],
		HORIZONTAL_ALIGNMENT_LEFT, cw, 15, StageTheme.DIM)
	y += 38.0
	Widgets.StageCard.rule_line(self, x, y, cw, acc)

	# the equaliser: the card's biggest visual, exactly as the mock has it
	y += 10.0
	Widgets.StageCard.eq_band(self, Rect2(x, y, cw, 372.0), acc, _t, section_idx, 34)
	y += 372.0 + 14.0

	# target + reward
	var ttxt := StageTheme.fmt_thousands(GameConfig.section_target(section_idx))
	Chrome.neon(self, num, ttxt, Vector2(x, y + 36.0), 40, Color("ffffff"), acc)
	var tnw := num.get_string_size(ttxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	draw_string(zh, Vector2(x + tnw + 10.0, y + 36.0), "目标分",
		HORIZONTAL_ALIGNMENT_LEFT, cw, 16, StageTheme.DIM)
	draw_string(med, Vector2(x, y + 34.0), "奖励 ◆%d" % GameConfig.SECTION_CLEAR_REWARD,
		HORIZONTAL_ALIGNMENT_RIGHT, cw, 17,
		Color(StageTheme.GOLD.r, StageTheme.GOLD.g, StageTheme.GOLD.b, 0.95))

	# limits + difficulty stars (tier read, not a save record)
	y += 54.0
	draw_string(zh, Vector2(x, y), "%d 乐句 · %.0f 秒/句 · 弃牌 ◆%d/张" %
		[GameConfig.PHRASES_PER_SECTION, GameConfig.phrase_duration(section_idx),
		GameConfig.DISCARD_COST], HORIZONTAL_ALIGNMENT_LEFT, cw, 16, StageTheme.DIM)
	var stars := Widgets.StageCard.tier_stars(section_idx)
	for i in range(3):
		var sc: Color = StageTheme.GOLD if i < stars else Color(0.47, 0.59, 0.78, 0.3)
		draw_string(zh, Vector2(x + cw - 68.0 + float(i) * 23.0, y), "★",
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
	draw_string(med, Vector2(x + 54.0, y + 14.0), "BOSS 规则",
		HORIZONTAL_ALIGNMENT_LEFT, cw - 160.0, 13, dim)
	# the run's faces are rolled at run start and previewed one blind ahead —
	# at home the honest answer is the mechanism, not a fabricated face
	var rule := "开局掷定 · 前一盲注公示预告" if is_wall else "无 · 常规盲注"
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
	_btn_rect = Rect2(x, y, cw, 76.0)
	var pulse: float = 0.86 + 0.14 * (0.5 - 0.5 * cos(_t * TAU / 2.4))
	draw_style_box(StageTheme.box(Color(acc.r * 0.28, acc.g * 0.28, acc.b * 0.28, 0.45),
		Color(acc.r, acc.g, acc.b, 0.7 * pulse), 2, 14,
		Color(acc.r, acc.g, acc.b, 0.34 * pulse), 18), _btn_rect)
	draw_line(_btn_rect.position + Vector2(14, 1.0), _btn_rect.position + Vector2(cw - 14, 1.0),
		Color(1, 1, 1, 0.8), 1.5)
	Chrome.neon(self, zh, "开 始 游 戏", Vector2(x, y + 40.0), 28, Color("ffffff"), acc, cw)
	draw_string(med, Vector2(x, y + 62.0), "⚡ 全新巡演 · 从 BLIND 01 开始",
		HORIZONTAL_ALIGNMENT_CENTER, cw, 14, dim)

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
	draw_string(StageTheme.zh(), Vector2(x, y + 26.0), "← 左右滑动查看整轮赛程 →",
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

	# scan sweep across the card (dcscan)
	var su: float = fmod(_t / 5.5, 1.0)
	var sy: float = card.position.y + card.size.y * (0.04 + 0.90 * su)
	var sa: float = 0.6 * sin(PI * su)
	draw_line(Vector2(card.position.x + 24.0, sy), Vector2(card.end.x - 24.0, sy),
		Color(acc.r, acc.g, acc.b, sa), 2.0)


## 倒影层的内容: 把卡片 1:1 翻转画到下方, 渐隐由本层的 shader 遮罩负责。
func draw_tail(ci: CanvasItem) -> void:
	var acc := Widgets.StageCard.accent_for(section_idx)
	var card := Rect2(CARD.position + Vector2(_drag_dx, 0.0), CARD.size)
	Widgets.StageCard.draw_mirror(ci, card, acc, 26.0, CARD_INSET)


## Bottom rail: 关卡 / 主角 / 小丑牌 / 荣誉。画法在 Chrome(四屏单源);
## 三个图鉴页 2026-08-11 起都有真页面了,「尚未开放」角标一起退役。
func _draw_tabs() -> void:
	_tab_rects = Chrome.tab_rects()
	Chrome.draw_tabs(self, tab, Widgets.StageCard.accent_for(section_idx))
