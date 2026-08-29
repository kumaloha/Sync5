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
	t.eq(Economy.joker_price(Joker.by_id("neonsign")), 3, "common support costs 3(经济 v2 平价)")
	t.eq(Economy.joker_price(Joker.by_id("triplebill")), 3, "uncommon support costs 3(经济 v2 平价)")
	t.eq(Economy.joker_price(Joker.by_id("bassline")), 3, "rare support costs 3(经济 v2 平价)")
	t.eq(Economy.joker_price(Joker.by_id("mirror")), 3, "mirror 平价(稀缺税随经济 v2 摘除;特例要回来必须在 levels.md 说明)")
	# ⚑ superwild 2026-08-29 转生为**消耗牌**(注入万能牌后卡本身没用了 = 一次性),
	# 它的 4◆ 特例价随卡搬到 data/consumables.json。断言跟着搬, 不删。
	var _sw := {}
	for _e in DB.consumables():
		if String(_e["id"]) == "superwild":
			_sw = _e
	t.eq(int(_sw.get("price", 0)), 4,
		"超级百搭特例价 4◆(2026-08-26 用户:「超级卡就4金币」;2026-08-29 随卡转生到消耗牌)")
	t.eq(Economy.joker_price(Joker.by_id("mono")), 0, "the first target is free")
	# Target 回池(2026-08-06 用户拍板): 换旗不再有专属价, 走同一张稀有度价目表。
	t.eq(Economy.joker_price(Joker.by_id("mono"), true), 3,
		"a later target costs its rarity price (no bespoke swap price)")
	t.eq(Economy.sell_value(Joker.by_id("mirror")), 1, "sell-back is half, rounded down(3◆ → 1)")
	t.eq(Economy.sell_value(Joker.by_id("neonsign")), 1, "common sells for 1(经济 v2)")
	t.eq(Economy.reroll_cost(0), 3, "first reroll costs 3")
	t.eq(Economy.reroll_cost(2), 5, "third reroll costs 5")

	# ---- 金币上限(穷开心 skint 的 hold.coin_cap;2026-08-13 引擎波次·子波1)----
	# 上限收口在 Economy 的两个口:grant 卡住收入、cap_held 修剪存量。
	# ⚠ 契约:入账点有四处(结算/段工资×2/替换回收), 漏一处 = 上限对那条收入无效
	# 且不报错 —— 与「乘法只写一处」同一条纪律。
	var skint_slots: Array = [null, Joker.by_id("skint"), null, null]
	var plain_slots: Array = [null, Joker.by_id("neonsign"), null, null]
	var cap: int = Joker.slots_coin_cap(skint_slots)
	t.check(cap > 0 and cap < 999999, "skint declares a coin cap")
	t.eq(Joker.slots_coin_cap(plain_slots), 999999, "no cap without the card")
	t.eq(Economy.grant(0, 3, plain_slots), 3, "income is untouched without a cap")
	t.eq(Economy.grant(cap - 1, 3, skint_slots), cap, "income stops at the cap")
	t.eq(Economy.grant(cap + 7, 3, skint_slots), cap + 7,
		"income above the cap is refused, never deducted (grant is not a confiscation)")
	t.eq(Economy.grant(5, -2, plain_slots), 3, "spending is never clamped")
	t.eq(Economy.cap_held(cap + 20, skint_slots), cap,
		"installing the card trims the hoard — 卡面「上限 5」对已经很富的玩家也必须为真")
	t.eq(Economy.cap_held(2, skint_slots), 2, "cap_held never adds coins")
	# 结算入账走 grant:装着穷开心时, 牌型金币吃不进上限之上
	var cap_run := Run.new()
	cap_run.reset(931)
	cap_run.joker_slots[1] = Joker.by_id("skint")
	cap_run.coins = cap
	var cap_p := Beat.begin(cap_run)
	Beat.settle(cap_run, cap_p, {})
	t.eq(cap_run.coins, cap, "settle income cannot push past the cap (core/beat.gd uses grant)")
