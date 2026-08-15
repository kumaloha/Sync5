class_name StageLayout
extends RefCounted

## 对局界面的**场景装配** —— 2026-08-09 从 `view/phrase.gd` 搬出来。
## 一次性跑完就不再参与逻辑:建节点、按 data/ui.json 的坐标排版、决定层序。
##
## ⚠ 这里只**造**节点, **不连信号** —— 「谁听谁」是编排, 留在 `view/phrase.gd`。
## ⚠ 也不打点、不碰钱:那两件事按铁律只许发生在编排器。
## ⚠ 坐标与文案一律从 `data/ui.json` 取, 不许硬编码回代码。
##
## `build()` 返回的字典就是编排器要拿的那几个把手;**add_child 的顺序 = 画的顺序**,
## 动之前先想清楚谁该盖住谁(替换态那两个部件由 `view/replace.gd` 在这之后挂上去)。

## Which painted backdrop this run uses. "" falls back to the procedural stage.
const SKIN_BG := ""


static func build(host: Control) -> Dictionary:
	var ui: Dictionary = DB.ui()["stage"]
	var margin := float(ui["margin"])
	var gap := float(ui["gap"])
	var pill_w := float(ui["pill_w"])
	var hand_top := float(ui["hand_top"])

	if SKIN_BG != "" and ResourceLoader.exists(SKIN_BG):
		var pic := TextureRect.new()
		pic.texture = load(SKIN_BG)
		pic.set_anchors_preset(Control.PRESET_FULL_RECT)
		pic.stretch_mode = TextureRect.STRETCH_SCALE
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(pic)
		# scrims: sink the areas the UI sits on so painted detail never fights it
		_scrim(host, Rect2(0, 0, 720, 220), Color(0, 0, 0, 0.50), true)     # info bar
		_scrim(host, Rect2(0, 600, 720, 680), Color(0, 0, 0, 0.38), false)  # hand + cache
	else:
		var bg := StageBg.new()
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		host.add_child(bg)

	var out := {}
	var hud := Hud.new()
	host.add_child(hud)
	out["hud"] = hud
	out["joker_views"] = _build_joker_row(host, margin, gap, pill_w)
	_build_wave_zone(host, out, margin)
	out["orbit"] = _build_orbit(host, hand_top)
	out["hand"] = Hand.new()
	host.add_child(out["hand"])
	out["shop"] = Shop.new()
	host.add_child(out["shop"])

	out["settle_fx"] = SettleFx.new()
	host.add_child(out["settle_fx"])

	# 教学关的一行提示(design/difficulty.md §4.4)。⚠ 加在这里而不是最后 ——
	# run_end / banner / intro 是模态覆盖层, 它们必须能盖住提示行。
	# 正式局它整块隐身(set_hint("", "") → visible=false), 不占位也不画。
	var tutor := Widgets.TutorHint.new()
	# ⚠ 位置是**截图逐版调出来的**, 不是算出来的(CLAUDE.md:改了视觉就渲染出来自己看):
	#   y=96  → 压进顶栏玻璃板里(hud = pos[26,26]+size[668,96], 下沿 122), 读起来像顶栏的一部分;
	#   y=132 → 盖住「♪ 小丑牌 ♪」那个标签;
	#   y=384 → 小丑牌槽位下沿(~370)与音浪层上沿(~430)之间的空带, 两边都不碰。
	tutor.position = Vector2(margin, 384)
	tutor.size = Vector2(720 - margin * 2, 40)
	tutor.visible = false
	tutor.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 提示不吃点击, 否则挡住顶栏
	host.add_child(tutor)
	out["tutor"] = tutor

	# section-end result screens (resources/success.html + fail.html)
	out["run_end"] = RunEndScreen.new()
	host.add_child(out["run_end"])

	# blind-clear strip: non-boss sections skip the full success screen
	out["banner"] = BlindBanner.new()
	host.add_child(out["banner"])

	# standalone blind announcement — only for entries WITHOUT a shop before
	# them (run start / retry); every other section is announced on the shop's
	# own blind board (Balatro 频次: 商店与盲注 1:1)
	out["intro"] = BlindIntro.new()
	host.add_child(out["intro"])
	return out


## dark_at_top=true → heavy at the top fading down (banner), false → the reverse.
static func _scrim(host: Control, r: Rect2, col: Color, dark_at_top: bool) -> void:
	var g := Gradient.new()
	if dark_at_top:
		g.set_color(0, col)
		g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	else:
		g.set_color(0, Color(col.r, col.g, col.b, 0.0))
		g.set_color(1, col)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 8
	t.height = 256
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	var tr := TextureRect.new()
	tr.texture = t
	tr.position = r.position
	tr.size = r.size
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(tr)


## 四个槽的视图。槽里的**数据**在 `run.joker_slots`, 这里只有壳;
## `tapped` 由编排器接(它只在替换态才活着)。
static func _build_joker_row(host: Control, margin: float, gap: float, pill_w: float) -> Array:
	var line_l := ColorRect.new()
	line_l.color = Color(0.55, 0.63, 1.0, 0.22)
	line_l.position = Vector2(margin, 167)
	line_l.size = Vector2(200, 1)
	host.add_child(line_l)
	var line_r := ColorRect.new()
	line_r.color = line_l.color
	line_r.position = Vector2(720 - margin - 200, 167)
	line_r.size = Vector2(200, 1)
	host.add_child(line_r)

	# 小丑牌区的标签条(盲注 2026-08-05 移到音浪层左侧的竖卡, 这里回到原样)
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", StageTheme.box(
		Color(StageTheme.CYAN.r, StageTheme.CYAN.g, StageTheme.CYAN.b, 0.10),
		Color(StageTheme.CYAN.r, StageTheme.CYAN.g, StageTheme.CYAN.b, 0.45), 1, 18,
		Color(StageTheme.CYAN.r, StageTheme.CYAN.g, StageTheme.CYAN.b, 0.35), 8))
	var pl := StageTheme.label("♪ 小丑牌 ♪", StageTheme.zh(), 19, Color("d9fbf7"),
		HORIZONTAL_ALIGNMENT_CENTER)
	pl.custom_minimum_size = Vector2(170, 30)
	pill.add_child(pl)
	pill.custom_minimum_size = Vector2(pill_w, 34)
	pill.size = Vector2(pill_w, 34)
	host.add_child(pill)
	pill.position = Vector2(360.0 - pill_w * 0.5, 150)
	pill.modulate.a = 0.85
	var pill_tw := pill.create_tween().set_loops()
	pill_tw.tween_property(pill, "modulate:a", 1.0, 1.5).set_trans(Tween.TRANS_SINE)
	pill_tw.tween_property(pill, "modulate:a", 0.85, 1.5).set_trans(Tween.TRANS_SINE)

	# joker modules: four squares spanning the full row (rack of effect units)
	var views: Array = []
	var jsize := (720.0 - margin * 2.0 - gap * 3.0) / 4.0
	for i in range(4):
		var slot := JokerSlotView.new()
		slot.slot_kind = "target" if i == 0 else "support"
		slot.position = Vector2(margin + i * (jsize + gap), 200)
		slot.size = Vector2(jsize, 172.0)
		host.add_child(slot)
		views.append(slot)
	return views


static func _build_wave_zone(host: Control, out: Dictionary, margin: float) -> void:
	out["wave"] = WaveView.new()
	out["wave"].position = Vector2(0, 426)
	out["wave"].size = Vector2(720, 216)
	host.add_child(out["wave"])

	# bar curtain filling the gap down to the hand frame (hand_top = 672)
	out["eq"] = EqStrip.new()
	out["eq"].position = Vector2(0, 626)
	out["eq"].size = Vector2(720, 44)
	host.add_child(out["eq"])

	# 盲注卡: 音浪层**左侧**, 和右边的唱片对称, 音浪从两者之间穿过。
	# 2026-08-11 用户拍板「位置不变, 上下顶格放大」:撑满唱片带全高(y 426..642, 高 216),
	# 宽按目录 118:176 比例随高走(≈145), 左缘仍在 margin —— 字号随设计空间整体 +23%,
	# 可读性就是这次放大的全部目的。竖向中心仍落在音浪轴 534(带的中点)。
	out["blind_card"] = Widgets.BlindCard.new()
	var bc_h := 216.0
	out["blind_card"].size = Vector2(bc_h * 118.0 / 176.0, bc_h)
	out["blind_card"].position = Vector2(margin, 426.0)
	out["blind_card"].mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(out["blind_card"])

	out["vinyl"] = VinylDeck.new()
	out["vinyl"].size = Vector2(132, 132)
	out["vinyl"].position = Vector2(720 - margin - 132, 426 + (216 - 132) * 0.5)
	host.add_child(out["vinyl"])


static func _build_orbit(host: Control, hand_top: float) -> OrbitZone:
	# the frame is the walker's track, so it sits a little outside the card row
	var frame := PanelContainer.new()
	frame.position = Vector2(24, hand_top)
	frame.size = Vector2(672, 286)
	frame.add_theme_stylebox_override("panel", StageTheme.box(
		Color(0.10, 0.13, 0.28, 0.45), Color(0.63, 0.71, 1.0, 0.30), 2, 30))
	host.add_child(frame)

	var orbit := OrbitZone.new()
	orbit.position = frame.position
	orbit.size = frame.size
	host.add_child(orbit)
	# the hand-area tab and the five card cells live in view/hand.gd now
	return orbit
