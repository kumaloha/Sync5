class_name StageLayout
extends RefCounted

## 对局界面的**场景装配** —— 2026-08-09 从 `view/phrase.gd` 搬出来。
## 一次性跑完就不再参与逻辑:建节点、按 data/ui.json 的坐标排版、决定层序。
##
## ⚠ 这里只**造**节点, **不连信号** —— 「谁听谁」是编排, 留在 `view/phrase.gd`。
## ⚠ 也不打点、不碰钱:那两件事按铁律只许发生在编排器。
## ⚠ **关键**坐标与文案从 `data/ui.json` 取(手牌/缓存/盲注卡/货架/信息区那几节);
##   但本文件正文仍有十几处写死的位置(音浪 426/216 · 均衡器 626/44 · 唱片 132 · 两条饰线 · 遮罩板),
##   2026-08-21 评审点名「文件头说不许, 正文自己写了十余个」—— 这句改成真话:**它们是一次性装配常量,
##   搬进 ui.json 是待办**, 在那之前改这些数字请在此处改, 并同步 docs/design/ui_meta.md 的坐标表。
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
	# ⚠⚠ **教学高亮必须加在这里 —— 在 hud/hand 之前**(`add_child` 的顺序 = 画的顺序)。
	# 它是「打光不画框」的唯一可行位置:画在上层的光会盖住卡面把花色染掉(两版实测,
	# 详见 `Widgets.TutorGlow` 的文件头)。放在下面, 光从半透黑的面板底透上来,
	# 卡面画在更上层, 颜色一个像素不动。**挪动这一行就是把那个 bug 放回来。**
	var tutor_glow := Widgets.TutorGlow.new()
	# ⚠ 不要再加 `set_anchors_preset(PRESET_FULL_RECT)` —— 它和显式 size 一起用会
	# 触发「anchors 会在 _ready 之后覆盖 size」的警告。写法与下面的 `tutor` 保持一致。
	tutor_glow.position = Vector2.ZERO
	tutor_glow.size = Vector2(720, 1280)
	tutor_glow.visible = false
	tutor_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(tutor_glow)
	var hud := Hud.new()
	host.add_child(hud)
	out["hud"] = hud
	# ⚠⚠ **Hand 必须加在小丑牌槽位之前**(2026-08-17 真人试玩抓到)。
	# 它是 `(0,0) 720×1280` 的全屏控件(拖放兜底落区要真实矩形), `mouse_filter = PASS`。
	# 而 **PASS ≠ 透明** —— 它不消费事件, 但**赢得命中测试**并把事件传给父节点,
	# **不会向下漏给下面的兄弟**。加在槽位之后 ⇒ 槽位收不到任何鼠标事件。
	# ⇒ 症状:**替换小丑牌时点不动、拖过去显示禁止符号**。而槽位**只有替换态才可点**,
	# 所以它一直存在却只在「第五张小丑牌来的时候」暴露。
	# ⚠ 视觉不受影响:Hand 的内容都在 y≥676, 槽位在 y 200-372, **两者不重叠**。
	# ⚠ **别改成收窄 Hand 的矩形** —— 它的子节点用绝对坐标, 挪 position 会让手牌整排飞走。
	out["hand"] = Hand.new()
	host.add_child(out["hand"])
	out["joker_views"] = _build_joker_row(host, margin, gap, pill_w)
	_build_wave_zone(host, out, margin)
	out["orbit"] = _build_orbit(host, hand_top)
	# ⚑ 消耗品格 ×2(2026-08-29):手牌区上方那条 66px 空带的**右端**(y 672..738)。
	# ⚠ **必须排在 orbit 之后** —— 轨道虽然是 IGNORE(不吃点击), 但绘制上后加的在上层;
	#   排在它前面会被轨道的底纹盖住(2026-08-17 那次「手牌点不动」就是层序问题的近亲)。
	# ⚠ 右端而不是左端:左端是节拍菱形走圈的起点。
	# ⚠ **全部从 `data/ui.json` 推导, 不写魔法数字**(2026-08-30 code review:
	# 首版硬编码了 738 与 696 ⇒ 改 JSON 的布局时格子不会跟着走, 违反
	# 「改布局改文案 = 改 JSON」这条铁律)。
	# 竖向:格子中心对齐「轨道顶到手牌卡顶」这条带;横向:右缘与手牌行右缘齐。
	# ⚠ 手牌上沿那条 66px 带里的旧消耗品栏已移走(见上面唱片那段)——
	# 那个位置只有 66px 高, 装不下带描述的卡, 而用户 2026-08-31 试玩报「没看到消耗牌在哪」。
	out["shop"] = Shop.new()
	host.add_child(out["shop"])

	out["settle_fx"] = SettleFx.new()
	host.add_child(out["settle_fx"])

	# 教学关的一行提示(docs/design/difficulty.md §4.4)。⚠ 加在这里而不是最后 ——
	# run_end / banner / intro 是模态覆盖层, 它们必须能盖住提示行。
	# 正式局它整块隐身(set_hint("", "") → visible=false), 不占位也不画。
	# ⚠ 压暗层要画在**内容之上**(要暗的是卡面本身), 但在提示条**之下**(条不该被自己压暗)。
	# 所以它必须夹在这里 —— glow 在最下、dim 在这、hint 在最上, 三层的顺序是有意的。
	var tutor_dim := Widgets.TutorDim.new()
	tutor_dim.position = Vector2.ZERO
	tutor_dim.size = Vector2(720, 1280)
	tutor_dim.visible = false
	tutor_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(tutor_dim)
	# 提亮层:**加法混合**画在暗层之上(它只在洞里画, 与暗层形状共用同一份判据,
	# 所以顺序对边缘无影响 —— 放上面只是语义:光压过暗)。用户 2026-08-18:
	# 「其实是需要操作的区域提亮, 其他地方变暗」—— 暗层管对比, 这层管真的把小件照亮。
	var tutor_light := Widgets.TutorLight.new()
	tutor_light.position = Vector2.ZERO
	tutor_light.size = Vector2(720, 1280)
	tutor_light.visible = false
	tutor_light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(tutor_light)
	var tutor := Widgets.TutorHint.new()
	# ⚠ **铺满全屏** —— 它既要画提示条(位置写死在 `TutorHint.BAR`), 又要在**别处**
	# 画分区描边(手牌区 / 缓存区 / 顶栏…), 所以不能只占那一条。
	tutor.position = Vector2.ZERO
	tutor.size = Vector2(720, 1280)
	tutor.visible = false
	tutor.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 提示不吃点击, 否则挡住顶栏
	host.add_child(tutor)
	# ⚑ 三层各在各的高度, 但**决定指哪的入口仍然只有 `tutor.set_hint`** —— 由它转发。
	# 拆的是「画在哪一层」, 不是「谁来决定指哪」, 所以「文案换了但高亮没跟着换」仍然不可能发生。
	tutor.glow = tutor_glow
	tutor.dim = tutor_dim
	tutor.light = tutor_light
	out["tutor"] = tutor

	# section-end result screens (docs/mockups/success.html + fail.html)
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
	# ⚠ 装饰件一律显式 IGNORE(2026-08-17 立的规矩, 见下面 frame 那段的教训)。
	var line_l := ColorRect.new()
	line_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line_l.color = Color(0.55, 0.63, 1.0, 0.22)
	line_l.position = Vector2(margin, 167)
	line_l.size = Vector2(200, 1)
	host.add_child(line_l)
	var line_r := ColorRect.new()
	line_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line_r.color = line_l.color
	line_r.position = Vector2(720 - margin - 200, 167)
	line_r.size = Vector2(200, 1)
	host.add_child(line_r)

	# 小丑牌区的标签条(盲注 2026-08-05 移到音浪层左侧的竖卡, 这里回到原样)
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_theme_stylebox_override("panel", StageTheme.box(
		Color(StageTheme.CYAN.r, StageTheme.CYAN.g, StageTheme.CYAN.b, 0.10),
		Color(StageTheme.CYAN.r, StageTheme.CYAN.g, StageTheme.CYAN.b, 0.45), 1, 18,
		Color(StageTheme.CYAN.r, StageTheme.CYAN.g, StageTheme.CYAN.b, 0.35), 8))
	var pl := StageTheme.label(Lingo.t("♪ 小丑牌 ♪"), StageTheme.zh(), 19, Color("d9fbf7"),
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

	# ⚑⚑ **唱片回位(2026-09-01 用户拍板)** —— 消耗牌改成全部自动触发之后,
	# 「消耗品栏」这个概念本身没了, 位置空出来还给光碟。用户:「光碟的位置还原成光碟」
	# +「币变成碟就可以了, 最多应该是 3 个」。
	# ⚠ 几何照 2026-08-31 退役前**逐字还原**:132×132, 右缘距边 margin, 竖向中心对齐盲注卡。
	# ⚑ 它现在的职责是**待播队列**(空着就是转盘), 见 `view/vinyl_deck.gd` 的文件头。
	# ⚠ 排版铁律那句「盲注卡 + 音浪 + 唱片(左中右)」因此回到字面意思。
	out["vinyl"] = VinylDeck.new()
	out["vinyl"].size = Vector2(132, 132)
	out["vinyl"].position = Vector2(720.0 - margin - 132.0, 426.0 + (216.0 - 132.0) * 0.5)
	host.add_child(out["vinyl"])


static func _build_orbit(host: Control, hand_top: float) -> OrbitZone:
	# the frame is the walker's track, so it sits a little outside the card row
	var frame := PanelContainer.new()
	# ⚠⚠ **必须 IGNORE** —— 它是手牌区的**装饰轨道**, 覆盖 y 672..958,
	# 也就是**整个手牌行**。`PanelContainer` 默认 `MOUSE_FILTER_STOP`,
	# 一旦它排在手牌卡上面, **手牌就点不动了**(缓存行在 y 1024+, 不受影响 ——
	# 症状正是「只能弃缓存区的」)。
	# ⚑ 2026-08-17 亲手撞的:为修「替换态点不动」把 `Hand` 提到了槽位之前,
	# 于是这个框反而跑到了手牌卡上面。**一个层序修复引出另一个层序 bug。**
	# ⇒ 真正的教训:**装饰性控件一律显式 IGNORE**, 别依赖它排在哪一层 ——
	# 依赖层序的正确性会在下一次调整层序时**静默失效**。
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
