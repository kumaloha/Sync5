class_name FxBurst
extends Control

## **A 级触发特效层**(2026-08-27)—— 设计稿 = `docs/mockups/fx/` 的四页:
##   `fx_advance.html`         预支:借入流金 / 逐拍抽走 / 违约碎裂(三拍各一次独立触发)
##   `fx_superwild.html`       超级百搭:四张 JOKER 沿螺旋收束入牌堆
##   `fx_gueststar_exit.html`  客串到寿:追光收窄 + 深鞠一躬 + 空槽粉色余晖
##   `fx_rulecards.html`       规则牌买入:一次性全屏宣告横幅(五张共骨架, 各自变体色)
##
## 与 `view/feedback.gd` 同一条线:**纯表现, 不读也不写任何游戏状态** —— 它不认识
## run / phrase / joker, 只认识「往哪画、画多大、画什么字」。所有实参由编排器
## (`view/phrase.gd`)算好递进来, 打点与经济动作照旧留在编排器手里(铁律)。
##
## ⚑ **全部程序化**:三类原语 —— 粒子(点/碎片/流光)· 描边脉冲 · 文字弹出。零位图。
## ⚑ 节奏与设计稿总纲同构:**入场快(0~40%)· 定格顿(40~70%)· 消散缓(70~100%)**。
##
## ⚠ **与设计稿的两处偏离(取神似舍形似)**:
## ① **时长**:稿子给超级百搭 ~1.4s、规则宣告 ~1.9s;本批统一压到 **1.15/1.20s**
##    ——「单次 ≤0.6s, 仪式类 ≤1.2s」是这批的验收线, 一局 4.9 分钟里 1.9s 的全屏
##    黑幕太贵。分镜比例逐段照抄, 只是整体缩了时基。
## ② **规则牌的「常驻右上角标」不在本批**:那是 HUD 的常驻件(要改 hud/ui.json),
##    这里只做买入那一次宣告 —— 收尾改成横幅**缩向刚装上的那个槽位**, 语义是
##    「这条规则从此住在那张卡上」, 而那张卡本来就是永久可见的标记。
##
## ⚠ 层序:它由编排器**最后** add_child 且 `z_index = 100` —— 规则宣告与百搭旋涡
## 发生在**商店开着**的时候, 不盖在货架上面就等于没演。`MOUSE_FILTER_IGNORE`,
## 任何时候都不吃点击(仪式不该抢走玩家那一拍)。

const W := 720.0
const H := 1280.0

## 规则牌五张的变体主色(逐字取自 `fx_rulecards.html` 的 `--ac`)。
## 黑调用花色蓝 `#9fe9ff`(= `StageTheme.SUIT_BLK`), 它讲的就是 ♠♣ 那件事。
const RULE_TINT := {
	"shortcut": Color("1effec"),
	"fourfingers": Color("7642ff"),
	"redtone": Color("ff328d"),
	"blacktone": Color("9fe9ff"),
	"trim": Color("ff9b2b"),
}

## 借入用青(黑底上读作冷绿 = 信用/流入), 偿还与违约用红 —— 五主色里没有纯绿,
## 这是设计稿总纲第 7 条的色注。
const CREDIT := Color("1effec")
const DEBIT := Color("ff3632")
const COIN := Color("ff9b2b")

var _shows: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 整个 UI 都按 720×1280 手工排版, 光靠 anchors 会把它留在 (0,0) 尺寸 0
	position = Vector2.ZERO
	size = Vector2(W, H)
	z_index = 100
	set_process(false)


func _process(delta: float) -> void:
	var alive: Array = []
	for s in _shows:
		s["t"] = float(s["t"]) + delta
		if float(s["t"]) < float(s["dur"]):
			alive.append(s)
	_shows = alive
	if _shows.is_empty():
		set_process(false)
	queue_redraw()


## 还有特效在演(探针用;游戏侧不等它 —— 仪式不许挡住下一拍)。
func busy() -> bool:
	return not _shows.is_empty()


## 换局/回首页时把没演完的仪式掐掉(谁抢走屏幕谁负责掐掉它, 同 SettleFx.dismiss)。
func clear() -> void:
	_shows.clear()
	set_process(false)
	queue_redraw()


# ============================== 公开的六个触发 ==============================


## ① 预支 · 借入:金币拖着青尾流进钱包。`purse` = HUD 金币位(全局坐标)。
func loan_borrow(purse: Vector2, amount: int) -> void:
	_push({"kind": "borrow", "dur": 0.60, "to": purse, "n": amount})


## ② 预支 · 偿还:一枚金币被红色拽出钱包, 甩出画面。
func loan_repay(purse: Vector2, amount: int) -> void:
	_push({"kind": "repay", "dur": 0.55, "from": purse, "n": amount})


## ③ 预支 · 违约:红闪 + 卡面碎成玻璃片爆散。`at` = 那张预支卡的槽位中心。
func loan_default(at: Vector2, amount: int) -> void:
	_push({"kind": "default", "dur": 0.60, "at": at, "n": amount})


## ④ 超级百搭买入:金色洗牌旋涡, 四张 JOKER 螺旋收束没入牌堆。
## 牌堆在游戏里没有实体, 所以仪式自带一叠牌背画在 `at` 上(稿子也是这么画的)。
func superwild(at: Vector2) -> void:
	_push({"kind": "wild", "dur": 1.15, "at": at})


## ⑤ 客串到寿谢幕:追光收窄 → 深鞠一躬 → 升起淡出, 空槽留一圈粉色余晖。
## `slot` = 槽位矩形(全局), `label` = 卡名(来自数据, 不是本文件的字面量)。
func guest_exit(slot: Rect2, label: String) -> void:
	_push({"kind": "bow", "dur": 1.20, "slot": slot, "label": label})


## ⑥ 规则牌买入宣告:全屏横幅 + 变体图形, 收尾缩向 `land`(刚装上的槽位中心)。
## `title`/`sub` 全部来自 `data/jokers.json`(cn_name / fx_text)—— 本文件不写文案。
func rule_decree(title: String, sub: String, variant: String, land: Vector2) -> void:
	_push({"kind": "rule", "dur": 1.20, "title": title, "sub": sub,
		"id": variant, "land": land})


func _push(s: Dictionary) -> void:
	s["t"] = 0.0
	_shows.append(s)
	set_process(true)
	queue_redraw()


# ============================== 时基与小工具 ==============================


static func _u(s: Dictionary) -> float:
	return clampf(float(s["t"]) / float(s["dur"]), 0.0, 1.0)


## 梯形包络:0→rise 升起, rise→fall 定格, fall→1 消散。
static func _fade(u: float, rise: float, fall: float) -> float:
	if u <= 0.0:
		return 0.0
	if rise > 0.0 and u < rise:
		return u / rise
	if fall < 1.0 and u > fall:
		return maxf(0.0, 1.0 - (u - fall) / (1.0 - fall))
	return 1.0


static func _out(u: float) -> float:
	return 1.0 - pow(1.0 - clampf(u, 0.0, 1.0), 3.0)


static func _smooth(u: float) -> float:
	var x: float = clampf(u, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## 局部进度:从 `delay` 起算、`span` 秒跑完。
static func _local(s: Dictionary, delay: float, span: float) -> float:
	return clampf((float(s["t"]) - delay) / maxf(span, 0.0001), 0.0, 1.0)


## 柔光斑 —— 借手牌那支霓虹管的白色径向渐变(同一套语言, 各画各的会飘)。
func _bloom(c: Vector2, r: float, col: Color) -> void:
	if col.a <= 0.003 or r <= 0.0:
		return
	draw_texture_rect(PaperCard.glow_tex(), Rect2(c - Vector2(r, r), Vector2(r * 2.0, r * 2.0)),
		false, col)


## ◆ 金币:一颗菱形 + 一圈柔光(语义自带颜色的小件, 金币恒金)。
func _coin(c: Vector2, r: float, halo: Color, a: float) -> void:
	if a <= 0.003:
		return
	_bloom(c, r * 2.6, Color(halo.r, halo.g, halo.b, 0.45 * a))
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0.0, -r), c + Vector2(r * 0.72, 0.0),
		c + Vector2(0.0, r), c + Vector2(-r * 0.72, 0.0)]),
		Color(COIN.r, COIN.g, COIN.b, a))
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0.0, -r * 0.44), c + Vector2(r * 0.32, 0.0),
		c + Vector2(0.0, r * 0.44), c + Vector2(-r * 0.32, 0.0)]),
		Color(1.0, 0.94, 0.78, a * 0.9))


## 居中的霓虹字。`at` 是**中心**, 不是基线。
func _text(font: Font, txt: String, at: Vector2, fs: int, col: Color, a: float) -> void:
	if a <= 0.003:
		return
	var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	PaperCard.neon_text(self, font, txt, at - Vector2(tw * 0.5, -fs * 0.36), fs,
		Color(col.r, col.g, col.b, a), Color(col.r, col.g, col.b, a), 1.0, 1.0)


## 数值 chip 的弹出:0→1.18→1 的过冲, 末段上飘淡出(稿子里 `@keyframes pop`)。
func _pop_text(txt: String, at: Vector2, col: Color, u: float, fs := 34) -> void:
	if u <= 0.0:
		return
	var a: float = _fade(u, 0.24, 0.70)
	if a <= 0.003:
		return
	var sc := 1.0
	if u < 0.30:
		var k: float = u / 0.30
		sc = 0.5 + 0.5 * _out(k) + 0.20 * sin(k * PI)
	var dy: float = -20.0 * maxf(0.0, (u - 0.70) / 0.30)
	draw_set_transform(at + Vector2(0.0, dy), 0.0, Vector2(sc, sc))
	_text(StageTheme.num("Bold"), txt, Vector2.ZERO, fs, col, a)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 暗玻璃板(全屏统一语言:暗底 + 主色描边 + 外发光)。
func _glass(r: Rect2, bg: Color, edge: Color, bw: int, radius: int, glow: float) -> void:
	draw_style_box(StageTheme.box(bg, edge, bw, radius,
		Color(edge.r, edge.g, edge.b, 0.42 * edge.a), int(glow)), r)


func _dashed_box(r: Rect2, col: Color, w: float, dash: float) -> void:
	draw_dashed_line(r.position, r.position + Vector2(r.size.x, 0.0), col, w, dash)
	draw_dashed_line(r.position + Vector2(r.size.x, 0.0), r.end, col, w, dash)
	draw_dashed_line(r.end, r.position + Vector2(0.0, r.size.y), col, w, dash)
	draw_dashed_line(r.position + Vector2(0.0, r.size.y), r.position, col, w, dash)


# ============================== 分发 ==============================


func _draw() -> void:
	for s in _shows:
		match String(s["kind"]):
			"borrow":
				_draw_borrow(s)
			"repay":
				_draw_repay(s)
			"default":
				_draw_default(s)
			"wild":
				_draw_wild(s)
			"bow":
				_draw_bow(s)
			"rule":
				_draw_rule(s)


# ------------------------------ ① 借入 ------------------------------


func _draw_borrow(s: Dictionary) -> void:
	var to: Vector2 = s["to"]
	var n: int = clampi(int(s["n"]), 4, 8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260827
	for i in range(n):
		# 从钱包的左下半圈飞来 —— 八枚各自的起点固定(同 seed 每帧同解, 不抖)
		var ang: float = rng.randf_range(PI * 0.52, PI * 1.38)
		var rad: float = rng.randf_range(250.0, 430.0)
		var from: Vector2 = to + Vector2(cos(ang), sin(ang)) * rad
		from.x = clampf(from.x, 34.0, W - 34.0)
		from.y = clampf(from.y, 90.0, H - 120.0)
		var e: float = _out(_local(s, 0.02 + i * 0.035, 0.30))
		if e <= 0.0:
			continue
		var p: Vector2 = from.lerp(to, e)
		var a: float = 1.0 if e < 0.86 else (1.0 - (e - 0.86) / 0.14)
		# 青色拖尾:同一条飞行线上的四个影子(流光, 不是星星粒子)
		for k in range(1, 5):
			var eg: float = maxf(0.0, e - float(k) * 0.06)
			var pg: Vector2 = from.lerp(to, eg)
			_bloom(pg, 16.0 - float(k) * 1.8,
				Color(CREDIT.r, CREDIT.g, CREDIT.b, (0.34 - 0.07 * float(k)) * a))
		_coin(p, 12.0 * (1.0 - 0.45 * e), CREDIT, a)
	# ⚠ chip 落在信息栏**下方**:第一版画在钱包正下方, 正好压在 "PHRASE 02" 上
	# (截图对账抓到)—— 数值弹出限一行高, 但那一行得是空的。
	_pop_text("+%d◆" % int(s["n"]), to + Vector2(-46.0, 102.0), CREDIT,
		_local(s, 0.14, 0.42), 36)


# ------------------------------ ② 偿还 ------------------------------


func _draw_repay(s: Dictionary) -> void:
	var from: Vector2 = s["from"]
	# 红钩把币从钱包里拽出来, 抛出画面(cubic-bezier(.5,0,.8,.6) 的加速感)。
	# ⚠ 钱包在**右上角**, 往右只有 56px 就出界了 —— 拽的方向必须朝**画面里**下沉,
	# 否则整段飞行有一半在屏幕外(第一版就是这样, 截图对账抓到)。
	for i in range(2):
		var e: float = _local(s, 0.02 + float(i) * 0.09, 0.42)
		if e <= 0.0:
			continue
		var acc: float = e * e * (1.4 - 0.4 * e)
		var dir := Vector2(-72.0 - 34.0 * float(i), 268.0 + 54.0 * float(i))
		var p: Vector2 = from + dir * acc
		var a: float = _fade(e, 0.12, 0.78)
		for k in range(1, 4):
			var eg: float = maxf(0.0, acc - float(k) * 0.08)
			_bloom(from + dir * eg, 15.0 - float(k) * 2.0,
				Color(DEBIT.r, DEBIT.g, DEBIT.b, (0.32 - 0.07 * float(k)) * a))
		_coin(p, 12.0 * (1.0 - 0.45 * e), DEBIT, a)
	_pop_text("-%d◆" % int(s["n"]), from + Vector2(-46.0, 102.0), DEBIT,
		_local(s, 0.08, 0.42), 36)


# ------------------------------ ③ 违约 ------------------------------


func _draw_default(s: Dictionary) -> void:
	var at: Vector2 = s["at"]
	var u: float = _u(s)
	# 红幕:径向柔光, 不是一块平的红板(底色不贡献亮度, 光全由光效层承担)
	var veil: float = _fade(u, 0.16, 0.42)
	if veil > 0.003:
		_bloom(at, 460.0, Color(DEBIT.r, DEBIT.g, DEBIT.b, 0.55 * veil))
		_bloom(at, 150.0, Color(DEBIT.r, DEBIT.g, DEBIT.b, 0.45 * veil))
	# 玻璃碎片:十片带红描边的暗玻璃, 各自的方向/自转固定
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var e: float = _out(_local(s, 0.02, 0.50))
	for i in range(10):
		var ang: float = TAU * float(i) / 10.0 + rng.randf_range(-0.26, 0.26)
		var dist: float = rng.randf_range(120.0, 210.0)
		var spin: float = rng.randf_range(-2.4, 2.4)
		var sz: float = rng.randf_range(26.0, 42.0)
		# ⚠ 碎片**先飞满程再淡出**:第一版 alpha 直接取 1-e, 飞到一半就只剩 14%,
		# 暗玻璃在黑底上等于隐身(截图对账抓到 —— 只看得见红描边)。
		var a: float = 1.0 - maxf(0.0, (e - 0.45) / 0.55)
		if a <= 0.003:
			continue
		var p: Vector2 = at + Vector2(cos(ang), sin(ang)) * dist * e
		draw_set_transform(p, spin * e, Vector2.ONE)
		var tri := PackedVector2Array([
			Vector2(-sz * 0.5, -sz * 0.6), Vector2(sz * 0.6, -sz * 0.2), Vector2(-sz * 0.1, sz * 0.6)])
		draw_colored_polygon(tri, Color(0.20, 0.20, 0.32, 0.96 * a))
		draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]),
			Color(DEBIT.r, DEBIT.g, DEBIT.b, a), 2.2, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 盖章:还不上的那个数字(死因行归 fail 屏, 这里只念数)。
	# ⚠ 盖在卡**下方**一行:压在卡心的红光/碎片堆里读不出来, 压在上方又撞
	# 「♪ 小丑牌 ♪」标签条(两版截图对账各抓到一次)。
	var st: float = _local(s, 0.16, 0.44)
	if st > 0.0:
		var a2: float = _fade(st, 0.20, 0.72)
		var sc: float = 2.1 - 1.15 * _out(minf(st / 0.35, 1.0))
		draw_set_transform(at + Vector2(0.0, 118.0), -0.10, Vector2(sc, sc))
		_text(StageTheme.num("Bold"), "-%d◆" % int(s["n"]), Vector2.ZERO, 38, DEBIT, a2)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ------------------------------ ④ 超级百搭 ------------------------------


func _draw_wild(s: Dictionary) -> void:
	var c: Vector2 = s["at"]
	var u: float = _u(s)
	var au := Color("ff9b2b")
	# 旋涡:三段弧一起转(0 → 700°), 收半径
	var va: float = _fade(u, 0.12, 0.62)
	if va > 0.003:
		var rot: float = deg_to_rad(700.0 * _out(minf(u / 0.85, 1.0)))
		var vr: float = 128.0 * (1.15 - 0.45 * _smooth(minf(u / 0.85, 1.0)))
		_bloom(c, vr * 1.5, Color(au.r, au.g, au.b, 0.14 * va))
		for i in range(3):
			var a0: float = rot + TAU * float(i) / 3.0
			draw_arc(c, vr, a0, a0 + deg_to_rad(84.0), 24,
				Color(au.r, au.g, au.b, 0.20 * va), 14.0, true)
			draw_arc(c, vr, a0, a0 + deg_to_rad(84.0), 24,
				Color(au.r, au.g, au.b, 0.95 * va), 4.5, true)
	# 牌堆:旋涡的落点。0.72 起「一口吞下」的缩放脉冲
	var gulp := 1.0
	if u > 0.68:
		var g: float = clampf((u - 0.68) / 0.22, 0.0, 1.0)
		gulp = 1.0 + 0.09 * sin(g * PI)
	draw_set_transform(c, 0.0, Vector2(gulp, gulp))
	_deck_stack(Vector2(-11.0, 9.0), 0.45)
	_deck_stack(Vector2(-5.5, 4.5), 0.7)
	_deck_stack(Vector2.ZERO, 1.0)
	if u > 0.68:
		_bloom(Vector2.ZERO, 74.0, Color(au.r, au.g, au.b, 0.34 * _fade((u - 0.68) / 0.32, 0.3, 0.5)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 四张 JOKER:外层转角度、内层收半径 = 真螺旋
	for i in range(4):
		var e: float = _local(s, 0.04 + float(i) * 0.07, 0.66)
		if e <= 0.0:
			continue
		var ee: float = _smooth(e)
		var ang: float = deg_to_rad(90.0 * float(i) + (340.0 + 90.0 * float(i)) * ee)
		var rad: float = lerpf(182.0, 3.0, ee)
		var p: Vector2 = c + Vector2(cos(ang), sin(ang)) * rad
		var sc: float = 1.0 - 0.9 * ee
		var a: float = 1.0 if e < 0.82 else (1.0 - (e - 0.82) / 0.18)
		draw_set_transform(p, deg_to_rad(320.0 * ee), Vector2(sc, sc))
		_joker_chip(au, a)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 汇心闪
	var fl: float = _local(s, 0.74, 0.22)
	if fl > 0.0 and fl < 1.0:
		var fa: float = sin(fl * PI)
		_bloom(c, 30.0 + 70.0 * fl, Color(1.0, 0.94, 0.80, 0.85 * fa))
		draw_circle(c, 6.0 + 16.0 * fl, Color(1.0, 1.0, 1.0, fa))
	_pop_text("JOKER ×4", c + Vector2(0.0, -168.0), au, _local(s, 0.80, 0.35), 34)


## 一叠牌背(斜纹填充 = 稿子的 repeating-linear-gradient)。原点 = 牌堆中心。
func _deck_stack(off: Vector2, dim: float) -> void:
	var r := Rect2(off + Vector2(-33.0, -45.0), Vector2(66.0, 90.0))
	_glass(r, Color(0.075, 0.062, 0.16, 0.96 * dim),
		Color(0.29, 0.23, 0.52, dim), 2, 8, 0.0)
	_hatch(r.grow(-3.0), 9.0, Color(0.38, 0.31, 0.66, 0.55 * dim))


## 45° 斜纹, **按矩形自己裁**(Godot 的 draw_line 不会被父矩形裁掉 ——
## 第一版偷懒只画了左上角那一小截, 截图里看着像脏点)。
func _hatch(r: Rect2, step: float, col: Color) -> void:
	var k: float = r.position.x + r.position.y
	var k_end: float = r.end.x + r.end.y
	while k <= k_end:
		var lo: float = maxf(r.position.x, k - r.end.y)
		var hi: float = minf(r.end.x, k - r.position.y)
		if hi > lo:
			draw_line(Vector2(lo, k - lo), Vector2(hi, k - hi), col, 2.0)
		k += step


## 一张 46×62 的 JOKER 小卡(原点 = 卡心)。
func _joker_chip(au: Color, a: float) -> void:
	var r := Rect2(-23.0, -31.0, 46.0, 62.0)
	_glass(r, Color(0.13, 0.10, 0.06, 0.95 * a), Color(au.r, au.g, au.b, a), 2, 6, 12.0)
	_text(StageTheme.num("Bold"), "J", Vector2.ZERO, 20, au, a)


# ------------------------------ ⑤ 客串谢幕 ------------------------------


func _draw_bow(s: Dictionary) -> void:
	var slot: Rect2 = s["slot"]
	var u: float = _u(s)
	var ac := Color("ff328d")
	var cx: float = slot.position.x + slot.size.x * 0.5
	# 段末压暗 —— 全场只剩这一束光
	var dim: float = 0.60 * _fade(u, 0.10, 0.74)
	if dim > 0.003:
		draw_rect(Rect2(0.0, 0.0, W, H), Color(0.0, 0.0, 0.0, dim), true)
	# 追光:从顶端一个点扩到槽位, 30% 处收窄到一半, 末段熄灭
	var sa: float = _fade(u, 0.12, 0.72)
	if sa > 0.003:
		var narrow: float = 1.0 - 0.55 * _smooth(clampf(u / 0.30, 0.0, 1.0))
		var hw: float = 232.0 * narrow
		var base_y: float = slot.end.y + 26.0
		var top := Color(ac.r, ac.g, ac.b, 0.30 * sa)
		var bot := Color(ac.r, ac.g, ac.b, 0.02 * sa)
		draw_polygon(
			PackedVector2Array([
				Vector2(cx - 9.0, 0.0), Vector2(cx + 9.0, 0.0),
				Vector2(cx + hw, base_y), Vector2(cx - hw, base_y)]),
			PackedColorArray([top, top, bot, bot]))
	# 观众闪光灯:六下白闪, 此起彼伏
	var rng := RandomNumberGenerator.new()
	rng.seed = 8823
	for i in range(6):
		var fp := Vector2(rng.randf_range(70.0, W - 70.0),
			slot.position.y + rng.randf_range(-90.0, 240.0))
		var fe: float = _local(s, 0.24 + float(i) * 0.045, 0.22)
		if fe <= 0.0 or fe >= 1.0:
			continue
		var fa: float = sin(fe * PI)
		_bloom(fp, 22.0, Color(ac.r, ac.g, ac.b, 0.55 * fa))
		draw_circle(fp, 3.6 * (0.6 + fa), Color(1.0, 1.0, 1.0, fa))
	# 客串卡本体:深鞠一躬(绕底边中点转) → 归位 → 升起淡出
	var rot := 0.0
	if u > 0.14 and u < 0.52:
		var b: float = clampf((u - 0.14) / 0.10, 0.0, 1.0)
		var back: float = clampf((u - 0.40) / 0.12, 0.0, 1.0)
		rot = deg_to_rad(16.0) * (_smooth(b) - _smooth(back))
	var rise := 0.0
	var ca := 1.0
	if u > 0.60:
		var k: float = clampf((u - 0.60) / 0.26, 0.0, 1.0)
		rise = -118.0 * _smooth(k)
		ca = 1.0 - k
	if ca > 0.003:
		var pivot := Vector2(cx, slot.end.y) + Vector2(0.0, rise)
		draw_set_transform(pivot, rot, Vector2.ONE)
		var body := Rect2(-slot.size.x * 0.5, -slot.size.y, slot.size.x, slot.size.y)
		_glass(body, Color(0.13, 0.078, 0.14, 0.94 * ca), Color(ac.r, ac.g, ac.b, ca), 2, 10, 16.0)
		_star(Vector2(0.0, -slot.size.y * 0.60), slot.size.x * 0.30, Color(ac.r, ac.g, ac.b, ca))
		_text(StageTheme.zh(), String(s["label"]), Vector2(0.0, -slot.size.y * 0.22), 15,
			Color(0.68, 0.71, 0.85), ca)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 上升拖尾星屑
	for i in range(3):
		var te: float = _local(s, 0.62 + float(i) * 0.06, 0.26)
		if te <= 0.0 or te >= 1.0:
			continue
		var tp := Vector2(cx - 18.0 + float(i) * 20.0,
			slot.position.y + 40.0 - 44.0 * te)
		var ta: float = 1.0 - te
		_bloom(tp, 14.0, Color(ac.r, ac.g, ac.b, 0.5 * ta))
		draw_circle(tp, 2.6, Color(ac.r, ac.g, ac.b, ta))
	# 空槽余晖:粉描边亮一下再退回去 —— **不许凭空蒸发**
	var la: float = _local(s, 0.72, 0.28)
	if la > 0.0:
		var laa: float = _fade(la, 0.25, 0.35)
		_dashed_box(slot, Color(ac.r, ac.g, ac.b, laa), 1.6, 7.0)
		_bloom(slot.get_center(), slot.size.x * 0.9, Color(ac.r, ac.g, ac.b, 0.20 * laa))


## 五角星(clip-path 的十个顶点逐点照抄), `r` = 外接半径。
func _star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var k := [Vector2(0.50, 0.00), Vector2(0.63, 0.36), Vector2(1.00, 0.38), Vector2(0.70, 0.60),
		Vector2(0.81, 1.00), Vector2(0.50, 0.76), Vector2(0.19, 1.00), Vector2(0.30, 0.60),
		Vector2(0.00, 0.38), Vector2(0.37, 0.36)]
	for v in k:
		var vv: Vector2 = v
		pts.append(c + (vv - Vector2(0.5, 0.5)) * r * 2.0)
	_bloom(c, r * 2.2, Color(col.r, col.g, col.b, col.a * 0.45))
	draw_colored_polygon(pts, col)


# ------------------------------ ⑥ 规则牌宣告 ------------------------------


const BANNER := Rect2(0.0, 512.0, W, 136.0)


func _draw_rule(s: Dictionary) -> void:
	var u: float = _u(s)
	var ac: Color = RULE_TINT.get(String(s["id"]), Color("1effec"))
	# 全屏压暗一次 —— 规则永续生效, 值得一次完整的停顿
	var dim: float = 0.58 * _fade(u, 0.12, 0.70)
	if dim > 0.003:
		draw_rect(Rect2(0.0, 0.0, W, H), Color(0.0, 0.0, 0.0, dim), true)
	# 横幅:玻璃条横贯(scaleX .2 → 1.015 → 1), 末段缩向刚装上的那个槽位
	var open_k: float = clampf(u / 0.13, 0.0, 1.0)
	var sx: float = 0.2 + 0.815 * _out(open_k)
	if open_k >= 1.0:
		sx = 1.0
	var ba := 1.0
	var org: Vector2 = BANNER.get_center()
	var scl := Vector2(sx, 1.0)
	if u > 0.78:
		var k: float = clampf((u - 0.78) / 0.22, 0.0, 1.0)
		ba = 1.0 - k
		var land: Vector2 = s["land"]
		org = BANNER.get_center().lerp(land, _smooth(k))
		var shrink: float = 1.0 - 0.86 * _smooth(k)
		scl = Vector2(shrink, shrink)
	if ba <= 0.003:
		return
	draw_set_transform(org, 0.0, scl)
	var plate := Rect2(-W * 0.5, -BANNER.size.y * 0.5, W, BANNER.size.y)
	draw_rect(plate, Color(0.055, 0.062, 0.125, 0.95 * ba), true)
	# 上下两条主色边(稿子只给 border-top / border-bottom), 外发光另画一层
	for edge_y in [plate.position.y, plate.end.y]:
		draw_line(Vector2(plate.position.x, edge_y), Vector2(plate.end.x, edge_y),
			Color(ac.r, ac.g, ac.b, ba), 2.5)
		draw_line(Vector2(plate.position.x, edge_y), Vector2(plate.end.x, edge_y),
			Color(ac.r, ac.g, ac.b, 0.24 * ba), 12.0)
	# 内容:字在左、变体图形在右。两者都在 0.10 之后才淡入(横幅先展开)
	var ca: float = ba * _fade(clampf((u - 0.10) / 0.90, 0.0, 1.0), 0.16, 1.0)
	if ca > 0.003:
		_text(StageTheme.zh(), String(s["title"]), Vector2(-166.0, -22.0), 34, ac, ca)
		_text(StageTheme.num("Medium"), String(s["sub"]), Vector2(-166.0, 16.0), 17,
			Color(0.68, 0.71, 0.85), ca)
		_text(StageTheme.num("Medium"), "RULE", Vector2(-166.0, 44.0), 12,
			Color(0.42, 0.45, 0.60), ca)
		_rule_gfx(String(s["id"]), Vector2(190.0, 0.0), ac, s, ca)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 变体图形区(原点 = 横幅内的图形中心;宽 ≈ 320, 高 ≈ 100)。
func _rule_gfx(id: String, o: Vector2, ac: Color, s: Dictionary, a: float) -> void:
	match id:
		"shortcut":
			_gfx_shortcut(o, ac, s, a)
		"fourfingers":
			_gfx_fourfingers(o, ac, s, a)
		"redtone":
			_gfx_tone(o, ac, s, a, "♥", "♦", Color("ff6aa9"))
		"blacktone":
			_gfx_tone(o, ac, s, a, "♠", "♣", Color("9fe9ff"))
		"trim":
			_gfx_trim(o, ac, s, a)


## 一格点数框(原点 = 框心)。
func _rank_box(c: Vector2, txt: String, col: Color, a: float, dashed := false) -> void:
	var r := Rect2(c - Vector2(20.0, 22.0), Vector2(40.0, 44.0))
	if dashed:
		_dashed_box(r, Color(0.36, 0.38, 0.52, a), 1.5, 5.0)
		_text(StageTheme.num("Bold"), txt, c, 19, Color(0.36, 0.38, 0.52), a * 0.7)
		return
	_glass(r, Color(0.04, 0.047, 0.094, 0.92 * a), Color(col.r, col.g, col.b, a), 2, 7, 8.0)
	_text(StageTheme.num("Bold"), txt, c, 19, col, a)


## 近道:5-6-□-8-9, 一道火花跃过中间的缺口。
func _gfx_shortcut(o: Vector2, ac: Color, s: Dictionary, a: float) -> void:
	var labels := ["5", "6", "7", "8", "9"]
	for i in range(5):
		var c: Vector2 = o + Vector2(-124.0 + float(i) * 62.0, 8.0)
		_rank_box(c, labels[i], ac, a, i == 2)
	# 跃过缺口的弧:按进度画一段渐长的折线(stroke-dashoffset 的等效)
	var e: float = _local(s, 0.28, 0.34)
	if e <= 0.0:
		return
	# ⚠ 弧要**跨过缺口**:从「6」跳到「8」。第一版落点写成了 o(缺口正上方),
	# 截图里那道光停在虚线框上 —— 近道讲的正是「不落在这一格」。
	var from: Vector2 = o + Vector2(-62.0, -22.0)
	var to: Vector2 = o + Vector2(62.0, -22.0)
	var pts := PackedVector2Array()
	var steps := 22
	for i in range(steps + 1):
		var k: float = float(i) / float(steps)
		if k > e:
			break
		var p: Vector2 = from.lerp(to, k) + Vector2(0.0, -40.0 * sin(k * PI))
		pts.append(p)
	if pts.size() >= 2:
		draw_polyline(pts, Color(ac.r, ac.g, ac.b, 0.28 * a), 8.0, true)
		draw_polyline(pts, Color(ac.r, ac.g, ac.b, a), 2.6, true)
		_bloom(pts[pts.size() - 1], 16.0, Color(ac.r, ac.g, ac.b, 0.6 * a))


## 四指:四张点亮, 第五张熄灭划叉。
func _gfx_fourfingers(o: Vector2, ac: Color, s: Dictionary, a: float) -> void:
	var lit: float = _local(s, 0.28, 0.30)
	for i in range(5):
		var c: Vector2 = o + Vector2(-124.0 + float(i) * 62.0, 0.0)
		var r := Rect2(c - Vector2(22.0, 30.0), Vector2(44.0, 60.0))
		if i == 4:
			_glass(r, Color(0.05, 0.05, 0.09, 0.9 * a), Color(0.23, 0.23, 0.35, a), 2, 7, 0.0)
			continue
		var g := 6.0
		if lit > 0.0:
			g += 12.0 * sin(lit * PI)
		_glass(r, Color(0.047, 0.04, 0.094, 0.92 * a), Color(ac.r, ac.g, ac.b, a), 2, 7, g)
	var x: float = _local(s, 0.38, 0.20)
	if x > 0.0:
		var c5: Vector2 = o + Vector2(124.0, 0.0)
		var sc: float = 2.0 - 1.0 * _out(x)
		draw_set_transform(c5, 0.0, Vector2(sc, sc))
		_text(StageTheme.num("Bold"), "×", Vector2.ZERO, 40, DEBIT, a * x)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 红调 / 黑调:两个花色相拥合一, 合到位时一记白闪。
func _gfx_tone(o: Vector2, ac: Color, s: Dictionary, a: float, gl: String, gr: String,
		suit: Color) -> void:
	var e: float = _smooth(_local(s, 0.26, 0.34))
	var dx: float = 74.0 * (1.0 - e)
	_text(StageTheme.zh(), gl, o + Vector2(-dx, 0.0), 56, suit, a)
	_text(StageTheme.zh(), gr, o + Vector2(dx, 0.0), 56, suit, a)
	var f: float = _local(s, 0.58, 0.16)
	if f > 0.0 and f < 1.0:
		var fa: float = sin(f * PI)
		_bloom(o, 34.0 + 48.0 * f, Color(ac.r, ac.g, ac.b, 0.7 * fa * a))
		draw_circle(o, 8.0 + 12.0 * f, Color(1.0, 1.0, 1.0, fa * a))


## 修剪:一道剪切虚线, 2 和 3 被剪落。
func _gfx_trim(o: Vector2, ac: Color, s: Dictionary, a: float) -> void:
	var sn: float = _local(s, 0.24, 0.18)
	if sn > 0.0:
		var w: float = 150.0 * sn
		var sa: float = a
		if sn > 0.8:
			sa = a * clampf((1.0 - sn) * 5.0, 0.0, 1.0)
		draw_dashed_line(o + Vector2(-w, -40.0), o + Vector2(w, -40.0),
			Color(ac.r, ac.g, ac.b, sa), 2.5, 8.0)
	var labels := ["2", "3"]
	for i in range(2):
		var e: float = _local(s, 0.34 + float(i) * 0.09, 0.32)
		var c: Vector2 = o + Vector2(-62.0 + float(i) * 124.0, 0.0)
		var ca: float = a * (1.0 - e)
		if ca <= 0.003:
			continue
		var fall: float = c.y + 96.0 * (e * e)
		draw_set_transform(Vector2(c.x, fall), deg_to_rad(-18.0 * e), Vector2.ONE)
		var r := Rect2(-22.0, -30.0, 44.0, 60.0)
		_glass(r, Color(0.047, 0.04, 0.094, 0.92 * ca), Color(0.62, 0.91, 1.0, ca), 2, 7, 8.0)
		_text(StageTheme.num("Bold"), labels[i], Vector2.ZERO, 22, Color("9fe9ff"), ca)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
