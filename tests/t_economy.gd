extends RefCounted

# --- Economy ---
func run(t) -> void:
	# 弃牌免费(2026-08-06 用户拍板)——**唯一的闸门是 8 秒钟, 不是金币**。
	# 断言从配置推导:哪天再改回收费, 改 economy.json 一处即可, 不用重写测试。
	var dc: int = GameConfig.DISCARD_COST
	t.eq(Economy.discard_cost(1), dc, "one card costs the configured discard price")
	t.eq(Economy.discard_cost(3), dc * 3, "cost scales with the card count")
	t.eq(Economy.discard_cost(0), 0, "discard 0 costs 0")
	t.eq(Economy.discard_cost(-2), 0, "negative count costs 0")

	# draft shop pricing (2026-08)
	t.eq(Economy.joker_price(Joker.by_id("neonsign")), 4, "common support costs 4")
	t.eq(Economy.joker_price(Joker.by_id("chorus")), 6, "uncommon support costs 6")
	t.eq(Economy.joker_price(Joker.by_id("bassline")), 9, "rare support costs 9")
	t.eq(Economy.joker_price(Joker.by_id("mirror")), 11, "mirror carries the scarcity tax")
	t.eq(Economy.joker_price(Joker.by_id("mono")), 0, "the first target is free")
	# Target 回池(2026-08-06 用户拍板): 换旗不再有专属价, 走同一张稀有度价目表。
	t.eq(Economy.joker_price(Joker.by_id("mono"), true), 9,
		"a later target costs its rarity price (no bespoke swap price)")
	t.eq(Economy.sell_value(Joker.by_id("mirror")), 5, "sell-back is half, rounded down")
	t.eq(Economy.sell_value(Joker.by_id("neonsign")), 2, "common sells for 2")
	t.eq(Economy.reroll_cost(0), 3, "first reroll costs 3")
	t.eq(Economy.reroll_cost(2), 5, "third reroll costs 5")
