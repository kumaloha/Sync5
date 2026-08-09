extends SceneTree

## Close-up strip of card faces at 2×, for judging the neon treatment and the
## drop-shadow reflection beneath each card.
##   godot --path . --script res://tools/card_sheet.gd

var _n := 0

func _initialize() -> void:
	Shot.canvas(self, 1240, 520, Color(0.027, 0.035, 0.086))

	var specs := [[8, 2], [13, 3], [15, 0], [15, 1]]   # 8♥ K♠ 大王 小王
	for i in range(specs.size()):
		var holder := Node2D.new()
		holder.position = Vector2(40 + i * 240, 60)
		holder.scale = Vector2(2, 2)
		get_root().add_child(holder)
		var pc := PaperCard.new()
		pc.size = Vector2(114, 170)
		pc.setup(Card.new(int(specs[i][0]), int(specs[i][1])))
		holder.add_child(pc)

	# a card back, to check the reflection there too
	var back_holder := Node2D.new()
	back_holder.position = Vector2(40 + specs.size() * 240, 60)
	back_holder.scale = Vector2(2, 2)
	get_root().add_child(back_holder)
	var back := PaperCard.new()
	back.size = Vector2(114, 170)
	back.setup(Card.new(8, 2))
	back.set_back(true)
	back_holder.add_child(back)

func _process(_d: float) -> bool:
	_n += 1
	if _n == 60:
		Shot.save(self, "cards")
		quit()
	return false
