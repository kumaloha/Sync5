class_name VinylDeck
extends Control

## The draw pile as a spinning vinyl record, with a remaining-count badge.
##
## ⚑ **也是「提前收工」的按钮**(2026-08-13 用户拍板:「主动结束一拍, 就点那个光碟」)。
## 语义天然:唱片是这一拍的时钟化身, 点它 = 让这一拍现在就结束。
## 不新增控件, 所以锁定的排版一个像素没动。

signal tapped

var count := 0
var armed := false         # 现在点它就能收工吗(决定光环与提示的显示)
var secs_left := 0.0       # armed 时中心标签显示的「省下几秒」
var _angle := 0.0
var _speed := 0.5          # radians/sec idle spin
var _boost := 0.0
var _arm_t := 0.0          # armed 状态的呼吸相位

func _ready() -> void:
	# ⚠ 从 IGNORE 改成 STOP:它现在要收点击。⚠ 别改成 PASS —— 点击会穿到下面去,
	# 而这一层底下是手牌区的边框, 穿透会让「点唱片」偶然选中一张牌。
	mouse_filter = Control.MOUSE_FILTER_STOP


## 编排器每帧告诉它「现在可不可以收工, 以及点下去能省几秒」
## (见 view/phrase.gd::_process)。⚠ 秒数由编排器算 —— **时钟只在那里读**。
func set_armed(v: bool, secs: float = 0.0) -> void:
	# 秒数每帧在变, 所以不能只在 armed 翻转时重画;但整秒不变时没必要重画。
	var same_digit: bool = int(floor(secs)) == int(floor(secs_left))
	secs_left = secs
	if armed != v or not same_digit:
		armed = v
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and armed:
		tapped.emit()

func set_count(n: int) -> void:
	if n != count:
		count = n
		queue_redraw()

func spin_boost() -> void:
	_boost = 6.0

func _process(delta: float) -> void:
	_angle += (_speed + _boost) * delta
	_boost = maxf(0.0, _boost - delta * 9.0)
	_arm_t += delta
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 4.0

	# armed 时的呼吸金环:唱片是「时钟」, 所以「可以收工了」这件事画在时钟的边上。
	# ⚠ 用**金色**而不是青色 —— 青是全局 chrome 色, 金在这一屏专表「时间/收益」
	# (金币、角标都是金), 语义对得上「省下的时间换分数」。
	if armed:
		var br: float = 0.5 + 0.5 * sin(_arm_t * 4.0)
		draw_circle(c, r + 9.0, Color(StageTheme.GOLD.r, StageTheme.GOLD.g,
			StageTheme.GOLD.b, 0.10 + 0.10 * br))
		draw_arc(c, r + 5.0, 0, TAU, 64,
			Color(StageTheme.GOLD.r, StageTheme.GOLD.g, StageTheme.GOLD.b,
			0.45 + 0.35 * br), 2.0 + br)

	# glow + plate
	draw_circle(c, r + 4.0, Color(StageTheme.CYAN.r, StageTheme.CYAN.g, StageTheme.CYAN.b, 0.20))
	draw_circle(c, r, Color("0b0e20"))
	draw_arc(c, r, 0, TAU, 64, Color(0.63, 0.71, 1.0, 0.35), 2.0)

	# grooves
	var gr := r * 0.42
	while gr < r - 3.0:
		draw_arc(c, gr, 0, TAU, 48, Color(0.63, 0.71, 1.0, 0.10), 1.0)
		gr += 4.5

	# rotating specular highlight
	draw_arc(c, r * 0.72, _angle, _angle + 0.9, 18, Color(1, 1, 1, 0.14), 5.0)
	draw_arc(c, r * 0.60, _angle + PI, _angle + PI + 0.7, 14, Color(1, 1, 1, 0.09), 4.0)

	# label
	draw_circle(c, r * 0.34, Color("2ab5aa"))
	draw_circle(c, r * 0.30, Color("7cf3e8"))
	if armed and secs_left >= 1.0:
		# armed 时中心标签让位给**省下的秒数**(2026-08-13 用户选的方案 2)。
		# ⚠ 显示的是**因**(秒数)不是果(加成):不同构筑的加成不同, 而秒数总是那个秒数
		# —— 没装时机卡时也不会显示一个 `+0%` 的废数字。
		# 中心标签本来就是纯色圆, 数字放进去不占任何新空间(排版一个像素没动)。
		var lf := StageTheme.num("Bold")
		var txt := "%d\"" % int(floor(secs_left))
		var tw := lf.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string(lf, Vector2(c.x - tw * 0.5, c.y + 8.0), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("07211f"))
	else:
		draw_circle(c, 2.5, Color("0b0e20"))
		# label notch shows rotation
		var notch := c + Vector2(cos(_angle), sin(_angle)) * r * 0.32
		draw_circle(notch, 2.0, Color("0b0e20"))

	# count badge, pinned to the plate's top-right
	var font := StageTheme.num("Bold")
	var badge := Rect2(c.x + r * 0.62, c.y - r - 4.0, 36, 22)
	var sb := StageTheme.box(StageTheme.GOLD, Color("f0a63f"), 1, 11)
	draw_style_box(sb, badge)
	draw_string(font, Vector2(badge.position.x, badge.position.y + 16), str(count),
		HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, 14, Color("211502"))
