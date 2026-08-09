extends RefCounted

# --- Pattern ---
func run(t) -> void:
	# Royal flush
	var royal := [t._c(10, 3), t._c(11, 3), t._c(12, 3), t._c(13, 3), t._c(14, 3)]
	var r := Pattern.evaluate_best(royal)
	t.eq(r["kind"], Pattern.Kind.ROYAL_FLUSH, "royal flush kind")
	t.eq(r["score"], (140 + 60) * int(Pattern.BASE_MULT[Pattern.Kind.ROYAL_FLUSH]),
		"royal flush score = chips × mult")

	# Straight flush 5-9 hearts
	var sf := [t._c(5, 2), t._c(6, 2), t._c(7, 2), t._c(8, 2), t._c(9, 2)]
	t.eq(Pattern.evaluate_best(sf)["kind"], Pattern.Kind.STRAIGHT_FLUSH, "straight flush kind")

	# Wheel straight (A2345 mixed suits)
	var wheel := [t._c(14, 3), t._c(2, 2), t._c(3, 1), t._c(4, 0), t._c(5, 3)]
	var w := Pattern.evaluate_best(wheel)
	t.eq(w["kind"], Pattern.Kind.STRAIGHT, "wheel is a straight")
	t.eq(w["score"], (30 + 28) * int(Pattern.BASE_MULT[Pattern.Kind.STRAIGHT]),
		"wheel score uses A=14")

	# Four of a kind
	var quad := [t._c(7, 0), t._c(7, 1), t._c(7, 2), t._c(7, 3), t._c(2, 0)]
	t.eq(Pattern.evaluate_best(quad)["kind"], Pattern.Kind.FOUR_KIND, "four of a kind")

	# Full house 999 22
	var fh := [t._c(9, 0), t._c(9, 1), t._c(9, 2), t._c(2, 0), t._c(2, 1)]
	var fhr := Pattern.evaluate_best(fh)
	t.eq(fhr["kind"], Pattern.Kind.FULL_HOUSE, "full house kind")
	t.eq(fhr["score"], (40 + 31) * int(Pattern.BASE_MULT[Pattern.Kind.FULL_HOUSE]),
		"full house score = chips × mult")

	# Flush (non-straight)
	var fl := [t._c(2, 0), t._c(5, 0), t._c(8, 0), t._c(11, 0), t._c(13, 0)]
	t.eq(Pattern.evaluate_best(fl)["kind"], Pattern.Kind.FLUSH, "flush kind")

	# Two pair
	var tp := [t._c(5, 0), t._c(5, 1), t._c(6, 2), t._c(6, 3), t._c(13, 0)]
	t.eq(Pattern.evaluate_best(tp)["kind"], Pattern.Kind.TWO_PAIR, "two pair kind")

	# Best-five from 7: quad hidden among noise
	var seven := [t._c(7, 0), t._c(7, 1), t._c(7, 2), t._c(7, 3), t._c(2, 0), t._c(3, 1), t._c(9, 2)]
	t.eq(Pattern.evaluate_best(seven)["kind"], Pattern.Kind.FOUR_KIND, "best-five finds quad in 7 cards")

	# Fewer than 5 cards -> empty
	t.check(Pattern.evaluate_best([t._c(2, 0), t._c(3, 0)]).is_empty(), "less than 5 cards -> empty")
