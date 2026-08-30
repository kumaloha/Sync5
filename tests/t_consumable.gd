extends RefCounted

## 消耗牌(2026-08-29 开轴)的契约门。
##
## ⚑ 这套测试锁的**不是数值**, 是几条结构契约 —— 数值归定价仪器:
##   ① 数据层干净:16 张全部可构造, `when` 合法, action/boost 至少有一个
##   ② **一次性**:用掉即从栏位消失(消耗牌与小丑牌的唯一分界)
##   ③ **时机门**:phrase 类在商店点不动, shop 类在对局中点不动
##   ④ **两套槽位互不占用**:消耗品栏满了不影响买小丑牌, 反之亦然
##   ⑤ **加成真的进乘法链**:烧掉一张 +150% 的牌, 分数必须真的涨
##   ⑥ **预支的债进存档**:借了钱不还是 run 死, 而债只活在 run 里 ⇒ 必须存
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
	# ⚠⚠ **这张表是「第二个家」** —— `core/db.gd::_CONSUMABLE_ACTIONS` 是第一个。
	# 2026-08-30 加 `loan` 时只改了 db 那份, 这里当场红 —— **这次红得对**:
	# 它逼着两处一起动, 正是本项目「两个家」纪律要的效果。⇒ 加新键时**四处齐落**:
	# db 白名单 · 这张表 · `view/phrase.gd::_apply_shop_action` · `tools/bot.gd::_apply_bot_action`
	# (后两处由 `tools/parity.py` 第 ② 层机械核对)。
	var known := ["wilds", "trim_low", "deck_rule", "shelf_slots", "buy_limit",
		"price_delta", "rule_guaranteed", "free_reroll", "min_rarity",
		"copy_one_destroy_rest", "loan"]
	for e in raw:
		for k in Consumable.new(e).action:
			t.check(known.has(String(k)),
				"%s 的 action 键 '%s' 不认识(拼错 = 静默失效, 两侧都不会执行)" % [e["id"], k])

	# ---- ④c 存档往返:买了的牌不许在续玩时消失 ----
	# ⚠ 2026-08-30 code review 抓到:`Run.snapshot()` 存了 slots/deck/cache/coins,
	# **唯独漏了 consumables** ⇒ 玩家买两张牌、暂停退出、续玩时它们凭空消失, 钱还白花。
	# 暂停/续玩是 08-27 刚做的功能, 这条路径整个没被想到。
	var sr := Run.new()
	sr.deck = Deck.new(7)          # snapshot 要序列化牌堆
	sr.take_consumable(by_id["opener"])
	sr.take_consumable(by_id["jukebox"])
	var snap := sr.snapshot(1)
	var sr2 := Run.new()
	sr2.deck = Deck.new(7)
	t.check(sr2.restore(snap), "带消耗牌的快照能读回来")
	t.check(sr2.consumables[0] != null and sr2.consumables[1] != null,
		"**两张消耗牌都还在** —— 存档往返不许把它们弄丢")
	t.eq(sr2.consumables[0].id, "opener", "第一格还是同一张")
	t.eq(sr2.consumables[1].id, "jukebox", "第二格还是同一张")
	# 拍内加成**不该**跨存档 —— 那一拍本来就没结算完
	sr.phrase_boosts.append({"bonus_pct": 1.0})
	var sr3 := Run.new()
	sr3.deck = Deck.new(7)
	sr3.restore(sr.snapshot(1))
	t.eq(sr3.phrase_boosts.size(), 0, "拍内加成不跨存档(那一拍没结算完)")

	# ---- ④d 商店类的 action **真的改变了商店的行为** ----
	# ⚠⚠ 2026-08-30 code review 抓到:联票/挑高/加急的 grant 变量**只被写入和清零,
	# 从没被读过** ⇒ 三张卡在游戏里是**空白的**(而 bot 侧有效果, 所以 sim 读数看着正常)。
	# ⚑ `parity.py` 查不出这个 —— 它查「两侧都有没有写」, 而这三个两侧都写了。
	# ⇒ 这几条断言守的是「写了之后有人读」, 不是「实现存在」。
	var sh := Shop.new()
	sh._grant_buy_limit = 2
	t.eq(sh.granted_buy_limit(), 2, "联票:授予的成交上限**读得到**(编排器靠它算配额)")
	sh._grant_free_reroll = 1
	t.check(sh.consume_free_reroll(), "加急:免费刷新**消费得掉**")
	t.check(not sh.consume_free_reroll(), "加急:只有一次(消费即清)")
	sh._grant_min_rarity = "uncommon"
	t.eq(sh._grant_min_rarity, "uncommon", "挑高:授予落在稀有度门槛上(不是牌面点数)")

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


	# ---- ⑥ 预支(2026-08-30 三批转生):借 → 记债 → 进存档 ----
	# ⚠ 它是**唯一**会在结算之外杀死 run 的消耗牌(付不起就死), 而债只活在 `run.debt`。
	# 08-30 code review 抓到过「存档没存消耗牌 ⇒ 续玩后凭空消失」—— 债丢了等于白拿 10◆,
	# 所以这条端到端必须走一遍存档往返。
	var lr := Run.new()
	lr.reset(1)
	lr.deck = Deck.new(3)
	var adv_e := {}
	for e in raw:
		if String(e["id"]) == "advance":
			adv_e = e
	t.check(not adv_e.is_empty(), "预支在消耗牌表里")
	t.check(lr.take_consumable(Consumable.new(adv_e)), "预支收进栏位")
	t.eq(lr.debt, 0, "还没烧, 不欠债")
	t.check(lr.use_consumable(0, "phrase").is_empty(), "预支是 shop 类 —— 对局中点不动")
	var out: Dictionary = lr.use_consumable(0, "shop")
	t.check(not out.is_empty(), "商店里点得动")
	var ln: Dictionary = (out.get("action", {}) as Dictionary).get("loan", {})
	t.eq(int(ln.get("borrow", 0)), 10, "action 带出借款额")
	# ⚠ 记债由**调用方**做(core 只负责取出与记账, 与其它 action 同一条分工),
	# 所以这里手动记一次, 再验存档往返。
	lr.debt += int(ln.get("repay", 0))
	t.eq(lr.debt, 12, "欠 12")
	var loan_snap: Dictionary = lr.snapshot(0)
	var lr2 := Run.new()
	t.check(lr2.restore(loan_snap), "快照可还原")
	t.eq(lr2.debt, 12, "**债进了存档** —— 续玩后还得还")
	var fresh := Run.new()
	fresh.reset(1)
	t.eq(fresh.debt, 0, "新局不带债")
	t.check(int(ln["repay"]) > int(ln["borrow"]), "还 > 借")
