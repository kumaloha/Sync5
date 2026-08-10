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

	_hint_label = StageTheme.label("点按开始", StageTheme.zh(), 15, StageTheme.rim(0.5), HORIZONTAL_ALIGNMENT_CENTER)
	_hint_label.position = Vector2(0, 762)
	_hint_label.size = Vector2(720, 22)
	add_child(_hint_label)


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
