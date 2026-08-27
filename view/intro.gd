class_name BlindIntro
extends Control

## Section-entry announcement — 盲注公示卡(2026-08-05 真人试玩:「盲注呢?
## 没看到,只看到了小丑牌」)。The blind structure only lived in a HUD caption;
## now every section OPENS with a center card: 第 N 场 · 小盲/BOSS,
## the target score, and the boss face warning on walls. Tap anywhere to
## skip; auto-dismisses otherwise. The phrase clock holds until `done`.

signal done

const AUTO_HOLD := 1.6          # seconds before self-dismiss (walls hold longer)
const AUTO_HOLD_WALL := 2.6

var _board: Widgets.BlindBoard
var _hint_label: Label
var _live := false
var _auto: Tween          # pending self-dismiss; killed on re-open
var _fade: Tween          # pending fade-out; killed on re-open
## γ 特写(v6 分镜化教学):教学毕转正式局的第一次开局, 公示卡多带一行盲注提示
## + 高光盲注板。open() 清空;set_tutor() 由编排器在 open 之后灌。
var _over: Control
var _tutor_text := ""


func _ready() -> void:
	position = Vector2.ZERO
	size = Vector2(720, 1280)
	visible = false
	z_index = 55

	var scrim := ColorRect.new()
	scrim.color = Color(0.02, 0.03, 0.08, 0.72)
	scrim.position = Vector2.ZERO
	scrim.size = size
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	# taps must land on the root's _gui_input — every child stays transparent
	_board = Widgets.BlindBoard.new()
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.position = Vector2(80, 462)
	_board.size = Vector2(560, 276)
	add_child(_board)

	_hint_label = StageTheme.label(Lingo.t("点按开始"), StageTheme.zh(), 15, StageTheme.rim(0.5), HORIZONTAL_ALIGNMENT_CENTER)
	_hint_label.position = Vector2(0, 762)
	_hint_label.size = Vector2(720, 22)
	add_child(_hint_label)

	# γ 特写的画布(v6):高光圈 + 提示条要盖在 scrim 与板**之上**, 根的 _draw 画在
	# 子节点下面, 所以单独一层, 加在最后。平时空转(_tutor_text 空 = 什么都不画)。
	_over = Control.new()
	_over.position = Vector2.ZERO
	_over.size = size
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.draw.connect(_draw_over)
	add_child(_over)


## Announce the section that is about to start. `mod` is the section's own
## boss face (SectionMod or null — walls only).
func open(section_idx: int, target: int, mod, boon = null) -> void:
	# a stale timer from the previous card must not dismiss this one
	if _auto != null and _auto.is_valid():
		_auto.kill()
	if _fade != null and _fade.is_valid():
		_fade.kill()
	var is_wall := GameConfig.is_wall(section_idx)
	skipped = false
	_tutor_text = ""              # γ 是一次性的:每次 open 先清, 要就在 open 后再灌
	_hint_label.position.y = 762
	_over.queue_redraw()
	_board.setup(section_idx, target, mod, "", -1, -1, boon)
	visible = true
	modulate.a = 1.0
	_live = true
	_board.pivot_offset = _board.size * 0.5
	_board.scale = Vector2(1.14, 1.14)
	var pop := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(_board, "scale", Vector2.ONE, 0.3)
	_auto = create_tween()
	_auto.tween_interval(AUTO_HOLD_WALL if is_wall else AUTO_HOLD)
	_auto.tween_callback(_dismiss)


## 玩家**主动**点掉了公示卡, 还是等 _auto 自己走完的 —— `done` 信号分不出来,
## 而这两件事是完全不同的行为信号(急着打 vs 在读盲注规则)。编排器在
## _on_intro_done 里读这个标志打点。
var skipped := false


## γ 特写(编排器在 open 之后调):加一行盲注提示({} 双色, 画法与 TutorHint 共用)
## + 高光盲注板;`hold` 秒后自动收(比常规公示卡多留一会 —— 这卡带课)。
## 点按跳过照旧(根的 _gui_input, intro 同手势本来就是它)。
func set_tutor(text: String, hold: float) -> void:
	_tutor_text = text
	_hint_label.position.y = 820      # γ 条占了 762 那一带, 「点按开始」往下让
	if _auto != null and _auto.is_valid():
		_auto.kill()
	_auto = create_tween()
	_auto.tween_interval(maxf(1.0, hold))
	_auto.tween_callback(_dismiss)
	_over.queue_redraw()


func _draw_over() -> void:
	if _tutor_text == "":
		return
	# 高光盲注区 = 板外一圈亮圈(打光语言, 不描内容):scrim 把全屏压暗了,
	# 亮圈 + 板自身的亮度就是「看这儿」。三圈递减 alpha 当软边。
	var br := Rect2(_board.position, _board.size).grow(8.0)
	for i in range(3):
		var a: float = 0.55 - 0.16 * float(i)
		_over.draw_rect(br.grow(float(i) * 3.0),
			Color(StageTheme.CYAN.r, StageTheme.CYAN.g, StageTheme.CYAN.b, a), false, 2.0)
	Widgets.draw_hint_bar(_over, Rect2(26.0, br.end.y + 16.0, 668.0, 40.0), _tutor_text, "")


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if _live:
			skipped = true
		_dismiss()


func _dismiss() -> void:
	if not _live:
		return
	_live = false
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 0.0, 0.22)
	_fade.tween_callback(func() -> void:
		visible = false
		done.emit())
