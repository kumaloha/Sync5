extends RefCounted

## 消耗牌(2026-08-29 开轴)的契约门。
##
## ⚑ 这套测试锁的**不是数值**, 是几条结构契约 —— 数值归定价仪器:
##   ① 数据层干净:12 张全部可构造, `when` 合法, action/boost 至少有一个
##   ② **一次性**:用掉即从栏位消失(消耗牌与小丑牌的唯一分界)
##   ③ **时机门**:phrase 类在商店点不动, shop 类在对局中点不动
##   ④ **两套槽位互不占用**:消耗品栏满了不影响买小丑牌, 反之亦然
##   ⑤ **加成真的进乘法链**:烧掉一张 +150% 的牌, 分数必须真的涨
## ⚠ ⑤ 是今天两次「改了没生效」的直接教训:数据落地 ≠ 运行时生效,
##   必须有一条端到端断言把「点下去 → 分数变了」这条路走一遍。

func run(t) -> void:
	var raw := DB.consumables()
	t.check(raw.size() >= 10, "consumables 表已装载(%d 张)" % raw.size())
	t.eq(DB.load_error(), "", "consumables.json 校验干净")

	# ---- ① 数据层 ----
	var by_id := {}
	for e in raw:
		var c := Consumable.new(e)
		by_id[c.id] = c
		t.check(c.price > 0, "%s 有正价格" % c.id)
		t.check(not c.action.is_empty() or not c.boost.is_empty(),
			"%s 至少有 action 或 boost(否则用了什么都不发生)" % c.id)
		t.check(["phrase", "shop", "any"].has(c.when), "%s 的 when 合法" % c.id)
		t.check(c.fx_text.split(" ").size() <= 7, "%s 卡面英文 ≤7 词" % c.id)

	# ---- ①b 卡面文案:每张都要有中文 trigger, 且进对照表 ----
	# ⚠ 与小丑牌同一条门(t_lingo ①):漏一条 = en 模式上屏中文而**不报错**。
	var ui_cc: Dictionary = DB.ui().get("consumablecard", {})
	var tbl: Dictionary = DB.lingo().get("table", {})
	for e in raw:
		var cid := String(e["id"])
		t.check(ui_cc.has(cid), "%s 有中文卡面(否则卡面退回英文 fx)" % cid)
		if ui_cc.has(cid):
			var trig := String(ui_cc[cid].get("trigger", ""))
			t.check(trig != "", "%s 的 trigger 非空" % cid)
			t.check(tbl.has(trig), "%s 的 trigger 在 lingo 对照表里" % cid)

	# ---- ② 一次性 + ③ 时机门 ----
	var run := Run.new()
	var opener: Consumable = by_id["opener"]        # when=phrase
	var jukebox: Consumable = by_id["jukebox"]      # when=shop
	t.check(run.take_consumable(opener), "空栏位收得下")
	t.check(run.take_consumable(jukebox), "第二格也收得下")
	t.check(not run.take_consumable(opener), "两格满了就收不下(不许无限囤)")

	t.eq(run.use_consumable(0, "shop"), {}, "phrase 类在商店里点不动")
	var used := run.use_consumable(0, "phrase")
	t.check(not used.is_empty(), "phrase 类在对局中点得动")
	t.eq(used.get("id", ""), "opener", "返回的是被点的那张")
	t.eq(run.consumables[0], null, "**用掉即消失** —— 一次性是消耗牌的定义")
	t.eq(run.phrase_boosts.size(), 1, "boost 记进了本拍加成")

	t.eq(run.use_consumable(1, "phrase"), {}, "shop 类在对局中点不动")
	t.check(not run.use_consumable(1, "shop").is_empty(), "shop 类在商店里点得动")

	# ---- ④ 两套槽位互不占用 ----
	var run2 := Run.new()
	run2.take_consumable(opener)
	run2.take_consumable(jukebox)
	t.check(not run2.consumable_room(), "消耗品栏已满")
	t.eq(run2.joker_slots.size(), 4, "小丑槽不受影响 —— 两套槽位互不占用")
	t.check(run2.joker_slots[1] == null, "小丑槽仍然是空的")

	# ---- ④b 每张牌「用了之后真的发生点什么」----
	# ⚠ 2026-08-30 教训:6/9 的 action 键**只在游戏侧实现**, bot 会买、会用,
	# 但用了什么都不发生 —— 而我正是用那份读数给它们定的价。
	# 机械核对在 `tools/parity.py`(它读得了源码);这里守数据侧的前提:
	# **每张牌的 action 键都得是已知的那 9 个之一**, 拼错一个字母 = 静默失效。
	var known := ["wilds", "trim_low", "deck_rule", "shelf_slots", "buy_limit",
		"price_delta", "rule_guaranteed", "free_reroll", "min_rank",
		"copy_one_destroy_rest"]
	for e in raw:
		for k in Consumable.new(e).action:
			t.check(known.has(String(k)),
				"%s 的 action 键 '%s' 不认识(拼错 = 静默失效, 两侧都不会执行)" % [e["id"], k])

	# ---- ⑤ 端到端:加成真的进乘法链 ----
	var five := [t._c(10, 0), t._c(10, 1), t._c(5, 2), t._c(7, 3), t._c(9, 0)]
	var res := Pattern.evaluate_best(five)
	var base_out := Settle.run(res, [null, null, null, null], {})
	var boosted := Settle.run(res, [null, null, null, null],
		{"phrase_boosts": [{"bonus_pct": 1.5}]})
	t.check(int(boosted["score"]) > int(base_out["score"]),
		"烧掉 +150%% 之后分数真的涨了(%d → %d)" % [base_out["score"], boosted["score"]])
	var mult_boost := Settle.run(res, [null, null, null, null],
		{"phrase_boosts": [{"mult": 3.0}]})
	t.check(int(mult_boost["score"]) > int(base_out["score"]),
		"mult 类加成同样生效(%d → %d)" % [base_out["score"], mult_boost["score"]])
