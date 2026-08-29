extends RefCounted

# --- 大小王 = wild cards ---
func _w(big: bool) -> Card:
	return Card.new(Card.JOKER_RANK, Card.JOKER_BIG if big else Card.JOKER_LITTLE)

func run(t) -> void:
	# one wild completes a royal flush
	var near_royal := [t._c(10, 3), t._c(11, 3), t._c(12, 3), _w(true), t._c(14, 3)]
	var rr := Pattern.evaluate_best(near_royal)
	t.eq(rr["kind"], Pattern.Kind.ROYAL_FLUSH, "wild completes a royal flush")
	t.eq(rr["cards"].size(), 5, "result keeps the original five for highlighting")
	t.check(rr["cards"][3].is_wild(), "the original wild stays in cards[]")
	t.check(not rr["resolved"][3].is_wild(), "resolved swaps the wild for a real card")

	# one wild turns trips into four of a kind
	var trips := [t._c(7, 0), t._c(7, 1), t._c(7, 2), _w(false), t._c(2, 0)]
	t.eq(Pattern.evaluate_best(trips)["kind"], Pattern.Kind.FOUR_KIND, "wild makes quads")

	# two wilds + a pair -> four of a kind
	var two_w := [t._c(9, 0), t._c(9, 1), _w(true), _w(false), t._c(3, 2)]
	t.eq(Pattern.evaluate_best(two_w)["kind"], Pattern.Kind.FOUR_KIND, "two wilds make quads")

	# a wild never makes the hand worse than the real cards alone
	var flush4 := [t._c(2, 0), t._c(5, 0), t._c(8, 0), t._c(11, 0), _w(true)]
	var fr := Pattern.evaluate_best(flush4)
	t.check(fr["kind"] >= Pattern.Kind.FLUSH, "wild completes the flush")

	# 万能牌唯一来源 = 超级百搭(2026-08-26 取代百搭)
	var d := Deck.new(9)
	t.eq(d.total(), 52, "deck starts without wilds")
	# ⚑ 超级百搭 2026-08-29 转生为消耗牌(注入后卡本身没用了 = 一次性)。
	var wc := {}
	for _e in DB.consumables():
		if String(_e["id"]) == "superwild":
			wc = _e
	var wa: Dictionary = Consumable.new(wc).action
	d.add_wilds("superwild", int(wa.get("wilds", 0)))
	t.eq(d.total(), 56, "超级百搭(消耗牌) injects four JOKERs")
