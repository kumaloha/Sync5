extends SceneTree

## 盲注卡三态近景 → `_shot_blind.png`(2× 放大)。
## 卡面是「牌」不是公示板, 所以要和手牌摆在同一套语言下目检。
## 2026-08-05 节奏重构后每场只有两盲(小盲 + BOSS 墙, 墙在 S2/S4/S6/S8),
## 三态取: S1 小盲(无脸, 倒置角标齐全) / S2 BOSS 墙(本段的脸) / S3 小盲 + NEXT 预告。

var _frames := 0

func _initialize() -> void:
	Shot.canvas(self, 720, 420, Color("0b0a1f"))

	var cases := [
		[0, null, null],                                 # S1 小盲
		[1, null, SectionMod.by_id("norepeat")],         # S2 BOSS 墙(本段的脸)
		[2, SectionMod.by_id("rush"), null],             # S3 小盲 + 下一面墙预告
	]
	for i in range(cases.size()):
		var c: Array = cases[i]
		var holder := Control.new()
		holder.scale = Vector2(2, 2)
		holder.position = Vector2(40 + i * 226, 34)
		get_root().add_child(holder)
		var card := Widgets.BlindCard.new()
		card.size = Vector2(118, 176)
		holder.add_child(card)
		card.setup(int(c[0]), c[1], c[2])


func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 12:
		return false
	Shot.save(self, "blind")
	return true
