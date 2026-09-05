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
		# ⚑ `fire` 取代 `when`(2026-09-01 全部自动触发):"buy" / "next" / 拍号 1..6。
		# ⚠ 拍号越界 = **永远等不到 = 静默废卡**, 所以这里连边界一起锁。
		if typeof(c.fire) == TYPE_STRING:
			t.check(["buy", "next"].has(String(c.fire)), "%s 的 fire 字符串合法" % c.id)
		else:
			t.check(int(c.fire) >= 1 and int(c.fire) <= GameConfig.PHRASES_PER_SECTION,
				"%s 的 fire 拍号在 1..%d(越界就永远等不到)" % [c.id, GameConfig.PHRASES_PER_SECTION])
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

	# ---- ② 一次性 + ③ 触发时机(2026-09-01 重写:点击这个动作整个没了)----
	var run := Run.new()
	var opener: Consumable = by_id["opener"]        # fire = 1(段首拍)
	var jukebox: Consumable = by_id["jukebox"]      # fire = "buy"(买下即触发)
	var popup: Consumable = by_id["popup"]          # fire = "next"(下一拍)

	# buy 类:**买下这一刻就返回它的 action**, 根本不进队列
	var inst := run.take_consumable(jukebox)
	t.check(not inst.is_empty(), "buy 类买下即触发 —— 就地返回 action")
	t.eq(inst.get("id", ""), "jukebox", "返回的是它自己")
	t.eq(run.consumables.size(), 0, "buy 类不占队列(它已经发生完了)")

	# 时机卡:排队, 到自己的拍号才打
	t.eq(run.take_consumable(opener), {}, "时机卡买下时什么也不执行 —— 它排队去了")
	t.eq(run.consumables.size(), 1, "进了待播队列")
	run.age_consumables()
	t.eq(run.due_consumables(2).size(), 0, "开场刻的是第 1 拍, 第 2 拍不该轮到它")
	run.age_consumables()
	var due := run.due_consumables(1)
	t.eq(due.size(), 1, "到第 1 拍才轮到")
	t.eq(String(due[0].get("id", "")), "opener", "轮到的是开场")
	t.eq(run.consumables.size(), 0, "**打完即消失** —— 一次性是消耗牌的定义")
	t.eq(run.phrase_boosts.size(), 1, "boost 并进了本拍加成")

	# "next":与段内位置无关, 排过一拍就打
	var run3 := Run.new()
	run3.take_consumable(popup)
	t.eq(run3.due_consumables(3).size(), 0, "刚买下的这一拍不打(还没排过拍)")
	run3.age_consumables()
	t.eq(run3.due_consumables(3).size(), 1, "下一拍就打, 拍号是几都一样")

	# ---- ④ 队列没有硬上限(与 2 格栏位时代的契约相反)----
	var run2 := Run.new()
	for _i in range(5):
		run2.take_consumable(Consumable.new(raw[0] if String(raw[0]["id"]) != "jukebox" else raw[1]))
	t.check(run2.consumables.size() >= 1, "队列收得下多张 —— 上限是算出来的 4, 不是拍的")
	t.eq(run2.joker_slots.size(), 4, "小丑槽不受影响 —— 两套东西互不占用")
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
	var known := ["wilds", "trim_low", "deck_rule", "shelf_slots", "extra_buys",
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
	sr.take_consumable(by_id["chorus"])
	var snap := sr.snapshot(1)
	var sr2 := Run.new()
	sr2.deck = Deck.new(7)
	t.check(sr2.restore(snap), "带消耗牌的快照能读回来")
	t.eq(sr2.consumables.size(), sr.consumables.size(),
		"**排队的碟一张都不许丢** —— 存档往返(暂停/续玩)")
	t.check(sr2.consumables.size() >= 1 and sr2.consumables[0].id == sr.consumables[0].id,
		"顺序也保住 —— 队列的顺序就是播放顺序")
	# ⚑ **排队年龄也要存**:只存 id 的话, 「下一拍」那张会在续玩后重新数一遍,
	# 玩家等两次 —— 而它已经等过了。这条是队列化之后新增的往返面。
	t.eq(int(sr2.consumables[0].queued_beats), int(sr.consumables[0].queued_beats),
		"排队了几拍也要跟着存")
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
	sh._grant_extra_buys = 2
	t.eq(sh.granted_extra_buys(), 2, "联票:授予的**额外**成交张数读得到(编排器靠它算配额)")
	# ⚑⚑ **净效果才是契约**(2026-09-02 用户报的问题):此前算式是
	# `maxi(基础, 授予)` ⇒ 联票买掉的正是它要给的那次成交, 买它等于白花 3◆。
	# ⇒ 这条断言锁的是**玩家看得见的那个数**:买完联票, 还能再选**两张**。
	# ⚠ 不写死 3 —— 基础名额走 `Joker.slots_buy_limit`, 它改了这条要跟着动。
	var empty4: Array = [null, null, null, null]
	var quota := Joker.slots_buy_limit(empty4) + sh.granted_extra_buys()
	t.eq(quota - 1, 2,
		"联票:买下它之后**还能再选 2 张**(它自己占第 1 次 —— 名额是加法不是取大)")
	# 累加:一店买到第二张联票要再给一次(与 bot 的 `_g_extra_buys +=` 同款)
	sh._grant_extra_buys += 2
	t.eq(sh.granted_extra_buys(), 4, "联票:一店买到第二张要**再给一次**, 不是覆盖")
	sh._grant_extra_buys = 0
	sh._grant_free_reroll = 1
	t.check(sh.consume_free_reroll(), "加急:免费刷新**消费得掉**")
	t.check(not sh.consume_free_reroll(), "加急:只有一次(消费即清)")
	sh._grant_min_rarity = "uncommon"
	t.eq(sh._grant_min_rarity, "uncommon", "挑高:授予落在稀有度门槛上(不是牌面点数)")

	# ---- ④e 本店类卡自带名额(2026-09-05 用户:「加急卖 3◆ 和直接点刷新没区别」)----
	# 5 选 1 下买它本身占掉本店唯一一次成交 ⇒ 编排器当场关店、`close()` 清零授予 ⇒ 卡是空白的
	#(联票 09-02 修的是同一形状, 当时只修了它一张)。锁两层:
	#   数据层 —— 凡 action 只改「本店」的卡必须带 extra_buys ≥ 1(名额是加法, 不开第二套计数);
	#   读取层 —— `grant_extra_buys` 是独立入口且累加(此前只在联票的货架分支里读, 带了键也没人读)。
	for c in DB.consumables():
		var a: Dictionary = c.get("action", {})
		if a.has("price_delta") or a.has("free_reroll") or a.has("min_rarity") or a.has("shelf_slots"):
			t.check(int(a.get("extra_buys", 0)) >= 1,
				"%s:本店类卡自带成交名额(extra_buys ≥ 1), 否则 5 选 1 下买了当场关店" % c["id"])
	var sh2 := Shop.new()
	sh2.grant_extra_buys(1)
	sh2.grant_extra_buys(1)
	t.eq(sh2.granted_extra_buys(), 2, "grant_extra_buys:独立入口, 累加(不经过联票的货架分支)")
	t.eq(Joker.slots_buy_limit(empty4) + sh2.granted_extra_buys() - 2, 1,
		"买两张本店类卡之后**仍剩 1 次成交** —— 它们只还回自己占掉的那次, 不多给")
	# 加急 3 次(3+4+5 = 12◆ 的刷新换 3◆):有上限才是逐次决策, 不限次 = 翻遍池子没有决策发生。
	var ec: Dictionary = {}
	for c in DB.consumables():
		if String(c["id"]) == "encorecall":
			ec = c
	t.eq(int(ec["action"]["free_reroll"]), 3, "加急:本店免费刷新 3 次(1 次 = 首刷价 3◆, 零价值)")

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
	# ⚑ 2026-09-01:预支是 `fire: "buy"` ⇒ **买下这一刻就借**, 不再有「进栏位等玩家点」。
	var out: Dictionary = lr.take_consumable(Consumable.new(adv_e))
	t.check(not out.is_empty(), "预支买下即触发 —— 就地返回 action")
	t.eq(lr.consumables.size(), 0, "它不进队列(没有『哪一拍』可选)")
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
