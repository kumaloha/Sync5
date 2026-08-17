class_name Hud
extends Control

## Info bar (docs/design/tech.md view split): 12 grouped pills, coins, score/target,
## phrase counter and the progress bar. Geometry from data/ui.json "hud";
## refresh(vm) is the only input — the orchestrator never touches the labels.
##
## **场次标签与 BOSS 脸不在这里** —— 2026-08-05 起搬到音浪层左侧的盲注卡
## (`Widgets.BlindCard`)。分工: HUD 管"当前数值"(分数/目标、金币、第几拍、进度),
## 盲注卡管"你在打什么"(档位、第几场、BOSS 规则)。

var _cfg: Dictionary = DB.ui()["hud"]
var seg_pills: Array = []
var coin_label: Label
var score_label: Label
var target_label: Label
var phrase_label: Label
var pbar: Widgets.GradBar


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.position = _v2(_cfg["pos"])
	panel.size = _v2(_cfg["size"])
	panel.add_theme_stylebox_override("panel", StageTheme.box(
		Color(0.043, 0.055, 0.13, 0.74),
		Color(StageTheme.CYAN.r, StageTheme.CYAN.g, StageTheme.CYAN.b, 0.38), 2, 16,
		Color(StageTheme.CYAN.r, StageTheme.CYAN.g, StageTheme.CYAN.b, 0.26), 16))
	add_child(panel)

	var inner := Control.new()
	panel.add_child(inner)

	# 12 blinds in 4 gig groups: tighter pitch + a gap per gig so the run
	# reads as four shows, not one long strip (right edge must clear ◆ coins)
	var pc: Dictionary = _cfg["pills"]
	for i in range(GameConfig.SECTIONS_PER_RUN):
		var pill := Widgets.SegPill.new()
		pill.position = Vector2(float(pc["x0"]) + i * float(pc["pitch"])
			+ GameConfig.gig_of(i) * float(pc["gap"]), float(pc["y"]))
		pill.size = Vector2(float(pc["w"]), float(pc["h"]))
		inner.add_child(pill)
		seg_pills.append(pill)

	coin_label = StageTheme.label("◆ 6", StageTheme.num("Bold"), 27, StageTheme.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	coin_label.position = _v2(_cfg["coin"])
	coin_label.size = Vector2(160, 30)
	inner.add_child(coin_label)

	score_label = StageTheme.label("0", StageTheme.num("Bold"), 48, StageTheme.INK)
	score_label.position = _v2(_cfg["score"])
	inner.add_child(score_label)

	target_label = StageTheme.label("/ 150", StageTheme.num("Regular"), 20, StageTheme.rim(0.40))
	target_label.position = _v2(_cfg["target"])
	inner.add_child(target_label)

	phrase_label = StageTheme.label("PHRASE 01", StageTheme.num("Medium"), 19, StageTheme.rim(0.75), HORIZONTAL_ALIGNMENT_RIGHT)
	phrase_label.position = _v2(_cfg["phrase"])
	phrase_label.size = Vector2(200, 24)
	inner.add_child(phrase_label)

	pbar = Widgets.GradBar.new()
	pbar.position = _v2(_cfg["pbar_pos"])
	pbar.size = _v2(_cfg["pbar_size"])
	inner.add_child(pbar)


func _v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


## vm keys: section_idx, coins, score, target, phrase_no, fraction
func refresh(vm: Dictionary) -> void:
	var si := int(vm["section_idx"])
	phrase_label.text = "PHRASE %02d" % int(vm["phrase_no"])
	coin_label.text = "◆ %d" % int(vm["coins"])
	score_label.text = "%d" % int(vm["score"])
	# ⚠ 目标分为 0 = **这一段没有目标**(目前只有教学关会这样, Run.target() 恒 0)——
	# 显示「0 / 0」会让玩家以为自己一分没得或者目标坏了。**没有目标就别画那一格。**
	target_label.visible = int(vm["target"]) > 0
	target_label.text = "/ %d" % int(vm["target"])
	target_label.position.x = float(_cfg["target_x_base"]) + score_label.get_minimum_size().x
	pbar.fraction = clampf(float(vm["fraction"]), 0.0, 1.0)
	for i in range(seg_pills.size()):
		seg_pills[i].lit = i <= si


## Anchor for coin float-texts (global coords).
func coin_anchor() -> Vector2:
	return coin_label.get_global_position()


## Anchor for the settle-fx flight target (global coords).
func score_anchor() -> Vector2:
	return score_label.global_position


## Score roll-up tick: write the number and pop it, one beat per frame.
func set_score_text(v: int) -> void:
	score_label.text = "%d" % v
	score_label.pivot_offset = score_label.size * 0.5
	score_label.scale = Vector2(1.12, 1.12)
	var tw := create_tween()
	tw.tween_property(score_label, "scale", Vector2.ONE, 0.12)
