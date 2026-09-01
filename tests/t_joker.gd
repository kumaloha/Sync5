extends RefCounted

# --- v0.1 joker roster ---
func run(t) -> void:
	# roster shape (2026-08-12 流派批: 删 popup/backup, 加族内件×4 + backer/bench/boxseats + trim;
	# 缘由与增删改清单见 docs/design/archetypes.md §5)
	var pool := Joker.pool()
	t.eq(pool.size(), 64, "pool holds 65 jokers(2026-08-30 二批转生:四张规则牌(近道/四指/黑调/红调)——它们的 `acquire.deck_rule` 把规则**烙进牌堆且没有撤销路径**, 卖掉后规则依然生效 ⇒ 按判据「用完之后这张卡还有没有意义」= 一次性)")
	var targets := 0
	var rarities := {"common": 0, "uncommon": 0, "rare": 0}
	for j in pool:
		if j.kind == "target":
			targets += 1
			# 回池后 Target 真的参与货架抽取, 所以**必须**有档 ——
			# 空字符串会让权重静默退到 1(比 rare 的 5 还低), 换旗率变成没人写下的数。
			t.check(j.rarity != "", "target %s carries a rarity tier" % j.id)
		else:
			rarities[j.rarity] = int(rarities.get(j.rarity, 0)) + 1
		# principle D2: EN card text, ≤7 words
		t.check(j.fx_text.split(" ").size() <= 7, "%s card text within 7 words" % j.id)
	t.eq(targets, 8, "eight targets —— 拆迁回池(beat_budget 校准 + 弃牌偏置后它可达了)")
	# 概率线基建(archetypes.md §3.8): fourfingers/twotone 降罕见 —— 规则牌从 5% 池权重解放
	t.eq(rarities["common"], 22, "22 common supports(快闪/赞助 2026-08-29 转生为消耗牌)")
	# ⚠ **twotone 已于 2026-08-14 升回 rare**(先验层实测它把同花抬 9.8×, 而同价位的
	# 近道/四指只有 3.1×/3.0× —— 效力差三倍以上;见 docs/design/jokers.md「第三次重锚」)。
	# ⚠⚠ **这撤销了上面那条「规则牌曝光」措施的一半, 是有意的**:先验数据说要救的是
	# **顺子线**(组合 8.89% 而真人只打出 1.9%), 不是同花线(组合 6.79% / 真人 7.4%, 几乎没差)。
	# 所以近道/四指**留在 uncommon**, 升回去的只有 twotone。
	# 配额上两个方向都在往 jokers_atlas.md §0 的目标(罕见 ~18 · 稀有 ~10)靠。
	# 2026-08-25 对抗批 +13(全在 uncommon/rare:乘法出口按「稀有度=构筑依赖度」入 rare,
	# 彩头/回收/客串/斗牛士/盲奏入 uncommon):uncommon 22→27 · rare 10→18。
	t.eq(rarities["uncommon"], 21, "21 uncommon supports(二批近道/四指 · 三批预支)")
	t.eq(rarities["rare"], 13, "13 rare supports(二批再转生黑调/红调)")
	# ⚑ 拆分后单张实测 5.3×(先验层 N=20万, Δ同花族 +29.7pp), 两张都装 9.6× = 老 twotone。
	# 仍是同类规则牌里最强(近道/四指只 1.8×), 所以 rare 保持不动。
	# ⚠ 近道/四指/黑调/红调的稀有度断言已删 —— 2026-08-30 二批转生, 它们是**消耗牌**了,
	# 消耗牌没有稀有度轴(TODO 里挂着「要不要加」)。它们现在的契约在 t_consumable。
	# ⚑ 快闪 2026-08-16 **按用户 08-15 那条原则复活**:「仅限一轮的卡不该删, 该是窗口窄 ⇒ 效果强」。
	# ⚠ 但**光加数额是假修**(docs/design/jokers.md 原话)—— 它的死因是 `section_eq: 0` 而**商店最早
	# S1 过半才开**, 玩家根本没机会在第 1 段拥有它(bot 2685 局触发 0%)。
	# ⇒ 窗口改成**每段第 1 拍**的滚动窗口:每段都有第 1 拍 ⇒ 何时买到都够得着,
	# 而窗口仍然窄(4/24 = 16.7%)⇒ 效果强(80% 每拍目标, 期望 13.3%/拍, 族内锚 12%)。
	# ⚑ 快闪 2026-08-29 转生为消耗牌 —— 用户:「一局4次毫无意义, 也就4次, 不是每次」。
	# 系统定时机 ⇒ 玩家被动;做成消耗牌后玩家自己选哪一拍烧。行为断言见 t_consumable。
	t.check(Joker.by_id("popup") == null, "快闪已转生为消耗牌(不该还在小丑牌池)")
	t.check(Joker.by_id("perkeo") != null, "帕奇欧在池(持续效果 ⇒ 留在小丑牌)")
	t.check(Joker.by_id("backup") == null, "backup left the pool (boxseats 上位替代)")
	t.check(Joker.by_id("nope") == null, "by_id on unknown id -> null")

	var flush_res := Pattern.evaluate_best([t._c(2, 0), t._c(5, 0), t._c(8, 0), t._c(11, 0), t._c(13, 0)])
	var base: int = flush_res["score"]
	var pair_res := Pattern.evaluate_best([t._c(5, 0), t._c(5, 1), t._c(7, 2), t._c(9, 3), t._c(13, 0)])
	var high_res := Pattern.evaluate_best([t._c(2, 0), t._c(5, 1), t._c(8, 2), t._c(11, 3), t._c(13, 0)])
	var fh_res := Pattern.evaluate_best([t._c(9, 0), t._c(9, 1), t._c(9, 2), t._c(2, 0), t._c(2, 1)])

	# targets
	# ⚠ 倍率一律从 data/jokers.json 推导。2026-08-06 拍板「难度只在牌型层收一次费,
	# Target 层各流派统一」后, 这批硬抄的断言一次红 5 条 —— 平衡要反复调, 别再抄死。
	t.eq(Settle.run(pair_res, [Joker.by_id("twin"), null, null, null], {})["score"],
		int(round(float(pair_res["score"]) * t._tmult("twin", "PAIR"))), "twin lifts the pair family")
	t.eq(Settle.run(fh_res, [Joker.by_id("twin"), null, null, null], {})["score"],
		int(fh_res["score"]), "twin: full house moved out of pair family")
	t.eq(Settle.run(fh_res, [Joker.by_id("triplet"), null, null, null], {})["score"],
		int(round(float(fh_res["score"]) * t._tmult("triplet", "FULL_HOUSE"))), "triplet lifts full house")
	var trips_res := Pattern.evaluate_best([t._c(9, 0), t._c(9, 1), t._c(9, 2), t._c(2, 0), t._c(5, 1)])
	t.eq(Settle.run(trips_res, [Joker.by_id("triplet"), null, null, null], {})["score"],
		int(round(float(trips_res["score"]) * t._tmult("triplet", "THREE_KIND"))), "triplet lifts trips")
	var tp_res := Pattern.evaluate_best([t._c(5, 0), t._c(5, 1), t._c(6, 2), t._c(6, 3), t._c(13, 0)])
	t.eq(Settle.run(tp_res, [Joker.by_id("twin"), null, null, null], {})["score"],
		int(round(float(tp_res["score"]) * t._tmult("twin", "TWO_PAIR"))), "twin lifts two pair")
	# 拍板后的**结构**契约:同一张 Target 内部各档必须一致(难度由牌型层承担, 不重复计价)
	t.eq(t._tmult("twin", "PAIR"), t._tmult("twin", "TWO_PAIR"), "twin tiers are uniform")
	t.eq(t._tmult("triplet", "THREE_KIND"), t._tmult("triplet", "FULL_HOUSE"), "triplet tiers are uniform")
	t.eq(t._tmult("stair", "STRAIGHT"), t._tmult("stair", "STRAIGHT_FLUSH"), "stair tiers are uniform")
	t.eq(t._tmult("mono", "FLUSH"), t._tmult("mono", "STRAIGHT_FLUSH"), "mono tiers are uniform")
	t.eq(Settle.run(flush_res, [Joker.by_id("triplet"), null, null, null], {})["score"],
		base, "triplet silent on a flush")
	# 独狼 2026-08-07 重做:从「得分卡」改成「经济/节奏卡」(用户拍板)。
	# 旧的「高牌 ×4」在弃牌免费后**一百拍才触发一次**(高牌频率 6.1%→1.6%),
	# 而它原本的交易「不弃牌=省钱」也随弃牌免费一起没了 —— 三根柱子倒了两根。
	# 新形态:不弃牌 → 给金币, 且 Target 出现率 ×3(卡面写着) —— 前期拖着攒钱换构筑。
	var wolf := Joker.by_id("lonewolf")
	t.eq(Settle.run(high_res, [wolf, null, null, null], {"discards": 0})["score"],
		int(high_res["score"]), "lone wolf no longer multiplies score")
	t.check(Settle.run(high_res, [wolf, null, null, null], {"discards": 0})["coins"]
		> Settle.run(high_res, [null, null, null, null], {"discards": 0})["coins"],
		"lone wolf pays coins when nothing was discarded")
	t.eq(Settle.run(high_res, [wolf, null, null, null], {"discards": 2})["coins"],
		Settle.run(high_res, [null, null, null, null], {"discards": 2})["coins"],
		"the vow is broken by any discard — no coins")
	var low_high := Pattern.evaluate_best([t._c(2, 0), t._c(4, 1), t._c(6, 2), t._c(9, 3), t._c(11, 0)])
	t.eq(Settle.run(low_high, [Joker.by_id("lonewolf"), null, null, null], {})["score"],
		int(low_high["score"]), "lonewolf: J-high does not count")
	t.eq(Settle.run(high_res, [Joker.by_id("lonewolf"), null, null, null], {"discards": 1})["score"],
		int(high_res["score"]), "lonewolf broken by a discard")
	t.eq(Settle.run(pair_res, [Joker.by_id("lonewolf"), null, null, null], {})["score"],
		int(pair_res["score"]), "lonewolf: made hands get no bonus")

	# finale / turnover / tipjar
	t.eq(Settle.run(flush_res, [null, Joker.by_id("finale"), null, null], {"acted_late": true})["score"],
		base + t._bonus("finale"), "finale bonus on a late action")
	t.eq(Settle.run(flush_res, [null, Joker.by_id("turnover"), null, null], {"discards": 3})["score"],
		base + t._bonus_n("turnover", 3), "turnover bonus per discard")
	# ⚠ **从数据推导, 不抄常量**(2026-08-30 收入重构把同花的牌型金币从 5 改到 3,
	# 这两条当场红 —— 而它们要守的契约是「零弃牌才给」, 与那个数字无关)。
	var fc: int = int(flush_res["coins"])
	var tip: int = int(t._do_amount("tipjar", "coins"))
	t.eq(Settle.run(flush_res, [null, Joker.by_id("tipjar"), null, null], {"discards": 0})["coins"],
		fc + tip, "tipjar 零弃牌才给(数额从 jokers.json 推导)")
	t.eq(Settle.run(flush_res, [null, Joker.by_id("tipjar"), null, null], {"discards": 1})["coins"],
		fc, "tipjar silent after a discard")

	# chord: cache all one suit (wilds match anything)
	var same_suit := [t._c(3, 1), t._c(9, 1), t._c(12, 1)]
	# 放宽为全同色(2026-08-26)后, 「混」必须是**异色**:红桃+方块是全红, 会触发。
	var mixed := [t._c(3, 1), t._c(9, 0), t._c(12, 1)]
	var with_wild := [t._c(3, 1), Card.new(Card.JOKER_RANK, Card.JOKER_BIG), t._c(12, 1)]
	t.eq(Settle.run(flush_res, [null, Joker.by_id("chord"), null, null], {"cache_cards": same_suit})["score"],
		base + t._bonus("chord"), "chord bonus on a one-suit cache")
	t.eq(Settle.run(flush_res, [null, Joker.by_id("chord"), null, null], {"cache_cards": mixed})["score"],
		base, "chord silent on a mixed-color cache")
	t.eq(Settle.run(flush_res, [null, Joker.by_id("chord"), null, null], {"cache_cards": with_wild})["score"],
		base + t._bonus("chord"), "a wild in the cache matches any suit")

	# neonsign: unconditional, flat — does NOT ride the multiplier
	t.eq(Settle.run(flush_res, [null, Joker.by_id("neonsign"), null, null], {})["score"],
		base + t._bonus("neonsign"), "neonsign always adds its flat bonus")
	t.eq(Settle.run(flush_res, [Joker.by_id("mono"), Joker.by_id("neonsign"), null, null], {})["score"],
		int(round(float(base) * t._tmult("mono", "FLUSH"))) + t._bonus("neonsign"),
		"neonsign stays flat under a target")

	# vinyl: permanent growth per discarded card, and it RIDES the multiplier —
	# the draft-early sleeper (user rule)
	var vinyl := Joker.by_id("vinyl")
	t.eq(Settle.run(flush_res, [null, vinyl, null, null], {})["score"], base, "vinyl starts silent")
	vinyl.on_discard(2)
	vinyl.on_discard(4)
	var fm: int = int(Pattern.BASE_MULT[Pattern.Kind.FLUSH])
	var vgrow: int = 6 * int(t._do_amount("vinyl", "additive"))    # 6 张弃牌 × 每张数额
	t.eq(Settle.run(flush_res, [null, vinyl, null, null], {})["score"],
		(int(flush_res["chips"]) + vgrow) * fm, "vinyl chips ride the pattern mult")
	t.eq(Settle.run(flush_res, [Joker.by_id("mono"), vinyl, null, null], {})["score"],
		int(round(float(int(flush_res["chips"]) + vgrow) * float(fm) * t._tmult("mono", "FLUSH"))),
		"vinyl growth rides every multiplier")

	# chorus: only on the section's last phrase
	t.eq(Settle.run(flush_res, [null, Joker.by_id("triplebill"), null, null],
		{"phrase_idx": GameConfig.PHRASES_PER_SECTION - 2})["score"],
		base, "chorus silent mid-section")

	# momentum: grows only on early finishes with at least one action
	var mom := Joker.by_id("momentum")
	mom.on_phrase_end({"early_finish": true})
	mom.on_phrase_end({"early_finish": false})
	mom.on_phrase_end({"early_finish": true})
	t.eq(Settle.run(flush_res, [null, mom, null, null], {})["score"],
		int(round(base * 1.2)), "momentum +10% per early finish")

	# vip: J/Q/K count as its face value via the additive channel(手里 J=11 与 K=13)
	var vip_res := Pattern.evaluate_best([t._c(2, 0), t._c(5, 0), t._c(8, 0), t._c(11, 0), t._c(13, 0)])
	var vval: int = int(t._do_amount("vip", "additive_face_value"))
	t.eq(Settle.run(vip_res, [null, Joker.by_id("vip"), null, null], {})["score"],
		(int(vip_res["chips"]) + (vval - 11) + (vval - 13)) * int(Pattern.BASE_MULT[Pattern.Kind.FLUSH]),
		"vip lifts J and K to face value, on the chips side")

	# glowstick: rented power, fades 6% per phrase
	var glow := Joker.by_id("glowstick")
	t.eq(Settle.run(flush_res, [null, glow, null, null], {})["score"],
		int(round(base * 1.6)), "glowstick starts at +60%")
	for i in range(5):
		glow.on_phrase_end({})
	t.eq(Settle.run(flush_res, [null, glow, null, null], {})["score"],
		int(round(base * 1.3)), "glowstick down to +30% after 5 phrases")
	for i in range(5):
		glow.on_phrase_end({})
	t.eq(Settle.run(flush_res, [null, glow, null, null], {})["score"],
		base, "glowstick burnt out after 10 phrases")

	# bassline: ×0.25 per 8 discards(2026-08-25 提速 12→8, 弃牌链毕业曲线)
	var bass := Joker.by_id("bassline")
	bass.on_discard(7)
	t.eq(Settle.run(flush_res, [null, bass, null, null], {})["score"],
		base, "bassline silent below 8 discards")
	bass.on_discard(1)
	t.eq(Settle.run(flush_res, [null, bass, null, null], {})["score"],
		int(round(base * 1.25)), "bassline ×1.25 at 8 discards")
	bass.on_discard(8)
	t.eq(Settle.run(flush_res, [null, bass, null, null], {})["score"],
		int(round(base * 1.5)), "bassline ×1.5 at 16 discards")

	# mirror(2026-08-25 改造):连续两拍达成旗条件才生效 —— 上一拍也命中时复制半个,
	# 上一拍没命中(或没有上一拍)时静默。必买卡从此要玩出来。
	var mirror := Joker.by_id("mirror")
	var streak := {"prev_target_hit": true}
	t.eq(Settle.run(flush_res, [Joker.by_id("mono"), mirror, null, null], streak)["score"],
		int(round(float(base) * t._tmult("mono", "FLUSH") * (1.0 + (t._tmult("mono", "FLUSH") - 1.0) * 0.5))),
		"mirror copies the target at half power on a streak")
	t.eq(Settle.run(flush_res, [Joker.by_id("mono"), mirror, null, null], {})["score"],
		int(round(float(base) * t._tmult("mono", "FLUSH"))),
		"mirror silent on the first hit — the streak needs two")
	t.eq(Settle.run(flush_res, [null, mirror, null, null], streak)["score"],
		base, "mirror silent without a target")
	t.eq(Settle.run(pair_res, [Joker.by_id("mono"), mirror, null, null], streak)["score"],
		int(pair_res["score"]), "mirror silent when the target missed")

	# interest: cap at +5
	# 上限从卡数据取 —— 2026-08-30 收入重构把 cap 从 5 改到 3。
	var icap: int = int(t._do_amount("interest", "cap"))
	t.eq(Settle.run(flush_res, [null, Joker.by_id("interest"), null, null], {"coins": 40})["coins"],
		int(flush_res["coins"]) + icap, "interest 封顶(上限从 jokers.json 推导)")

	# ---- 2026-08-12 流派批(docs/design/archetypes.md §3):族内件 + 缓存件 + 经济件 ----
	# 族内件 contains 语义 = kind_in(顺/同花五张点数互异, 天然不含对):
	# 葫芦必须**同时**吃到对子件和三条件 —— 原作葫芦流 Duo+Trio 双吃的直译, 结构契约。
	var damt: int = int(t._do_amount("duo", "additive"))
	var tamt: int = int(t._do_amount("triad", "additive"))
	t.eq(Settle.run(fh_res, [null, Joker.by_id("duo"), Joker.by_id("triad"), null], {})["score"],
		(int(fh_res["chips"]) + damt + tamt) * int(Pattern.BASE_MULT[Pattern.Kind.FULL_HOUSE]),
		"duo+triad double-dip on a full house (contains semantics)")
	t.eq(Settle.run(flush_res, [null, Joker.by_id("duo"), null, null], {})["score"],
		base, "duo silent on a flush (no pair inside)")
	t.eq(Settle.run(pair_res, [null, Joker.by_id("triad"), null, null], {})["score"],
		int(pair_res["score"]), "triad silent on a bare pair")
	var dpct: float = t._do_amount("duet", "bonus_pct")
	t.eq(Settle.run(pair_res, [null, Joker.by_id("duet"), null, null], {})["score"],
		int(round(float(pair_res["score"]) * (1.0 + dpct))), "duet rides the pct channel")

	# backer(后台, Bull 直译):每 2◆ +1 chips, 乘前通道吃全倍率
	var bamt: int = int(t._do_amount("backer", "additive"))
	t.eq(Settle.run(flush_res, [null, Joker.by_id("backer"), null, null], {"coins": 10})["score"],
		(int(flush_res["chips"]) + bamt * 5) * int(Pattern.BASE_MULT[Pattern.Kind.FLUSH]),
		"backer: +1 chip per 2 coins held, rides the mult")
	t.eq(Settle.run(flush_res, [null, Joker.by_id("backer"), null, null], {"coins": 1})["score"],
		base, "backer silent below 2 coins")

	# bench(替补, Splash 缓存直译):缓存最高点数按倍数计 chips
	var btop: int = 13 * int(t._do_amount("bench", "additive_cache_top"))
	t.eq(Settle.run(flush_res, [null, Joker.by_id("bench"), null, null],
		{"cache_cards": [t._c(13, 2), t._c(3, 1), t._c(7, 0)]})["score"],
		(int(flush_res["chips"]) + btop) * int(Pattern.BASE_MULT[Pattern.Kind.FLUSH]),
		"bench: top cache rank rides as chips")

	# boxseats(包厢, Baron 缓存直译):缓存每张人头 mult_add 0.2 —— 两张人头 = ×1.4
	var bstep: float = t._do_amount("boxseats", "mult_add")
	t.eq(Settle.run(flush_res, [null, Joker.by_id("boxseats"), null, null],
		{"cache_cards": [t._c(13, 2), t._c(12, 1), t._c(7, 0)]})["score"],
		int(round(base * (1.0 + bstep * 2.0))), "boxseats: two cache faces stack the mult")
	t.eq(Settle.run(flush_res, [null, Joker.by_id("boxseats"), null, null],
		{"cache_cards": [t._c(7, 2), t._c(5, 1), t._c(2, 0)]})["score"],
		base, "boxseats silent with no face in cache")

	# ---- 2026-08-13 引擎波次·子波1:动作内容信号(docs/design/jokers_atlas.md)----
	# 静物:零交换才给 —— 交换是免费动作, 这是「不动手」的那一侧张力(vs 串场)
	t.eq(Settle.run(flush_res, [null, Joker.by_id("stilllife"), null, null], {"swaps": 0})["score"],
		base + int(t._bonus("stilllife")), "still life pays a zero-swap phrase")
	t.eq(Settle.run(flush_res, [null, Joker.by_id("stilllife"), null, null], {"swaps": 1})["score"],
		base, "still life silent once a swap happened")
	# 串场:按「换入且参与成牌」的张数计 —— 每张都要真的进了成牌五张
	t.eq(Settle.run(flush_res, [null, Joker.by_id("segue"), null, null],
		{"swapped_scoring": 2})["score"],
		base + t._bonus_n("segue", 2), "segue pays per swapped scoring card(总额一次取整, 同 Fx)")
	t.eq(Settle.run(flush_res, [null, Joker.by_id("segue"), null, null],
		{"swapped_scoring": 0})["score"], base, "segue silent with nothing swapped in")
	# 断舍离(declutter)撤出 json 挂仪器债(bot 弃牌上限 2-3 张, 一次弃 5 张结构不可能),
	# 断言随卡一起撤 —— 回池时连同 bot 弃牌流策略块一起恢复(同 wrecker/trio)。
	# 让位:每张被弃的人头 —— 反贵宾路线的燃料
	t.eq(Settle.run(flush_res, [null, Joker.by_id("stageexit"), null, null],
		{"faces_discarded": 3})["score"], base + t._bonus_n("stageexit", 3),
		"stage exit pays per discarded face card")
	# 定格:早锁只武装**下一拍**(脉冲计数器, 一拍后自动归零)
	var frz := Joker.by_id("freeze")
	t.eq(Settle.run(flush_res, [null, frz, null, null], {})["score"], base,
		"freeze silent before any early finish")
	frz.on_phrase_end({"early_finish": true})
	var fpct: float = t._do_amount("freeze", "bonus_pct")
	t.eq(Settle.run(flush_res, [null, frz, null, null], {})["score"],
		int(round(base * (1.0 + fpct))), "freeze arms the phrase after an early finish")
	frz.on_phrase_end({"early_finish": false})
	t.eq(Settle.run(flush_res, [null, frz, null, null], {})["score"], base,
		"freeze lasts exactly one phrase (pulse, not permanent)")
	# 分成:牌型自带金币翻倍, **不乘**其他卡给的 coins_bonus(小费罐同装时验证)
	var pat_coins: int = int(flush_res["coins"])
	# 倍数从卡数据取 —— 2026-08-30 把 ×2 改成 ×1.5(收入重构)。
	var rf: float = float(t._do_amount("royalty", "coins_factor"))
	t.eq(Settle.run(flush_res, [null, Joker.by_id("royalty"), null, null], {})["coins"],
		int(round(pat_coins * rf)), "分成放大牌型自带的金币(倍数从 jokers.json 推导;实现用 round)")
	t.eq(Settle.run(flush_res, [null, Joker.by_id("royalty"), Joker.by_id("tipjar"), null],
		{"discards": 0})["coins"],
		int(round(pat_coins * rf)) + int(t._do_amount("tipjar", "coins")),
		"分成**不放大**别的卡给的 coins_bonus")
	# 打包:段分已达目标两倍才给(悲观口径 —— 本拍自己的分还没落地)
	t.eq(Settle.run(flush_res, [null, Joker.by_id("doggybag"), null, null],
		{"section_score": 2000, "section_target": 1000})["coins"],
		pat_coins + int(t._do_amount("doggybag", "coins")), "doggy bag pays past double target")
	t.eq(Settle.run(flush_res, [null, Joker.by_id("doggybag"), null, null],
		{"section_score": 1999, "section_target": 1000})["coins"],
		pat_coins, "doggy bag silent just below double")
	# 穷开心:常驻倍率 + 金币上限(上限本身在 Economy 收口, 见 t_economy)
	var spct: float = t._do_amount("skint", "mult_add")
	t.eq(Settle.run(flush_res, [null, Joker.by_id("skint"), null, null], {})["score"],
		int(round(base * (1.0 + spct))), "broke & happy always multiplies")

	# ---- 2026-08-13 子波 2:计时族(时钟观测由 view/探针经 flags 传入, core 不含时钟)----
	# 谢幕:最后 1 秒窗口, 比尾声(2 秒)更窄 —— 两者是**包含关系**, 压到最后一秒双亮
	var cpct: float = t._do_amount("curtain", "bonus_pct")
	t.eq(Settle.run(flush_res, [null, Joker.by_id("curtain"), null, null],
		{"acted_final": true})["score"], int(round(base * (1.0 + cpct))),
		"curtain pays an action in the final second")
	t.eq(Settle.run(flush_res, [null, Joker.by_id("curtain"), null, null],
		{"acted_late": true})["score"], base,
		"curtain stays silent on a merely-late action (its window is narrower)")
	# 压到最后一秒 = 同时点亮谢幕(pct)与尾声(bonus)。两条通道分别落地:
	# pct 乘在乘法链上, bonus 在乘法**后**加 —— 顺序错了这条断言会红。
	t.eq(Settle.run(flush_res, [null, Joker.by_id("curtain"), Joker.by_id("finale"), null],
		{"acted_final": true, "acted_late": true})["score"],
		int(round(base * (1.0 + cpct))) + int(t._bonus("finale")),
		"a final-second action lights both curtain and finale (windows nest, by design)")
	# 秒表:每剩 1 秒;整秒向下取(玩家读的是秒表上的整数)
	var swpct: float = t._do_amount("stopwatch", "bonus_pct")
	t.eq(Settle.run(flush_res, [null, Joker.by_id("stopwatch"), null, null],
		{"seconds_left": 3.0})["score"], int(round(base * (1.0 + swpct * 3.0))),
		"stopwatch pays per whole second left")
	t.eq(Settle.run(flush_res, [null, Joker.by_id("stopwatch"), null, null],
		{"seconds_left": 2.9})["score"], int(round(base * (1.0 + swpct * 2.0))),
		"stopwatch floors to whole seconds")
	t.eq(Settle.run(flush_res, [null, Joker.by_id("stopwatch"), null, null],
		{"seconds_left": 0.0})["score"], base, "stopwatch silent with no time left")
	# 早弃:弃过牌**且**都在前段 —— 没弃过牌不算(否则整拍不动手白拿, A4 挂机)
	t.eq(Settle.run(flush_res, [null, Joker.by_id("earlyout"), null, null],
		{"early_discards": true})["score"], base + int(t._bonus("earlyout")),
		"early purge pays when every discard landed early")
	t.eq(Settle.run(flush_res, [null, Joker.by_id("earlyout"), null, null], {})["score"],
		base, "early purge silent on an untouched phrase (no discards is not 'early')")

	# ---- 2026-08-13 子波 3:商店成长族(第七个钩子 on_shop_event)----
	# 三张都挂**付费动作**(A4✓):刷新付钱 / 买卡付钱 / 换旗丢掉旧旗。
	var dig := Joker.by_id("digger")
	var col := Joker.by_id("collector")
	var reb := Joker.by_id("rebrand")
	t.eq(Settle.run(flush_res, [null, dig, null, null], {})["score"], base,
		"crate digger starts silent (growth cards are dead weight at first — B3)")
	# 事件要**认门别**:刷新只喂淘碟, 买只喂收藏家 —— 串了就是「一个动作喂两张卡」
	dig.on_shop_event("buy")
	t.eq(Settle.run(flush_res, [null, dig, null, null], {})["score"], base,
		"a purchase does not feed the reroll counter")
	dig.on_shop_event("reroll")
	dig.on_shop_event("reroll")
	var dgrow: int = 2 * int(t._do_amount("digger", "additive"))
	t.eq(Settle.run(flush_res, [null, dig, null, null], {})["score"],
		(int(flush_res["chips"]) + dgrow) * int(Pattern.BASE_MULT[Pattern.Kind.FLUSH]),
		"two rerolls grow the digger, and it rides the mult (additive channel)")
	col.on_shop_event("reroll")
	t.eq(Settle.run(flush_res, [null, col, null, null], {})["score"], base,
		"a reroll does not feed the buy counter")
	col.on_shop_event("buy")
	t.eq(Settle.run(flush_res, [null, col, null, null], {})["score"],
		(int(flush_res["chips"]) + int(t._do_amount("collector", "additive")))
		* int(Pattern.BASE_MULT[Pattern.Kind.FLUSH]), "collector grows per purchase")
	reb.on_shop_event("target_swap")
	t.eq(Settle.run(flush_res, [null, reb, null, null], {})["score"],
		int(round(base * (1.0 + t._do_amount("rebrand", "bonus_pct")))),
		"reinvention grows per target change (pct channel)")
	# 静态口:一次调用喂满整排槽位 —— 两侧编排器都只写这一行
	var shelf_slots: Array = [null, Joker.by_id("digger"), Joker.by_id("collector"), null]
	Joker.notify_shop(shelf_slots, "reroll")
	t.check(float(shelf_slots[1].state.get("n", 0.0)) == 1.0
		and float(shelf_slots[2].state.get("n", 0.0)) == 0.0,
		"notify_shop feeds every slot but only the matching counters")

	# ── 槽位归属:0 号 = Target 专用, Support 只进 1..3 ──────────────────
	# ⚠⚠ **这一组是回归锁**:2026-08-16 真人试玩报「第五个小丑牌来的时候, 点替换会失效」。
	# 根因 = `view/shop.gd` 用 `_slots.has(null)`(四个槽)判满, 而 Support 只能进 1..3。
	# **当时没有任何测试守着这条规则**, 所以它一路溜到了真人手里。
	var sup := Joker.by_id("collector")
	var tgt_slots: Array = [null, sup, sup, sup]       # 没有 Target, 三个 Support 满
	t.eq(Joker.first_free_support(tgt_slots), -1,
		"0 号空不算 Support 的空位 —— 这正是那个 bug 的确切形状")
	t.check(not Joker.has_room_for(tgt_slots, "support"),
		"没有 Target + 三 Support 满 ⇒ Support 装不进 ⇒ 必须走替换流程")
	t.check(Joker.has_room_for(tgt_slots, "target"),
		"同一局面下 Target 装得进 —— 0 号槽就地换旗, 不需要替换流程")
	var half: Array = [null, sup, null, sup]
	t.eq(Joker.first_free_support(half), 2, "返回**第一个**空的 Support 槽")
	t.check(Joker.has_room_for(half, "support"), "有空位就装得进")
	var full: Array = [sup, sup, sup, sup]
	t.eq(Joker.first_free_support(full), -1, "全满没有空位")
	t.check(Joker.has_room_for(full, "target"), "全满时 Target 仍装得进(换旗)")
	_t_loan(t)


## 预支 advance —— 2026-08-30 三批转生为**消耗牌**(判据:「每段一次」也判一次性,
## 而且它是系统自动借还、**玩家零决策**)。这里锁新形态的数据契约;
## 借还的两界行为由 `run.debt` 承载(编排器 / runloop 各一处), 端到端在 t_consumable。
func _t_loan(t) -> void:
	t.check(Joker.by_id("advance") == null, "预支已不在小丑牌池")
	var none: Array = [null, null, null, null]
	t.eq(int(Joker.slots_loan(none)["borrow"]), 0, "空槽不借")
	# ⚠⚠ `slots_loan` 现在**没有真值来源**。留着这条是为了「将来又有小丑牌挂借贷」时
	# 仍被守住 —— 但**现役的借贷不走这里**(见 core/run.gd::debt)。
	for j in Joker.pool():
		t.eq(int(Joker.slots_loan([j])["repay"]), 0,
			"%s 不该带 hold.loan —— 借贷已整体搬到消耗牌(run.debt)" % j.id)
	var adv := {}
	for e in DB.consumables():
		if String(e["id"]) == "advance":
			adv = e
	t.check(not adv.is_empty(), "预支在消耗牌里")
	var ln: Dictionary = (adv.get("action", {}) as Dictionary).get("loan", {})
	t.eq(int(ln.get("borrow", 0)), 10, "借 10")
	t.eq(int(ln.get("repay", 0)), 12, "还 12(利息 2 = 一段的 tempo 价)")
	t.check(int(ln["repay"]) > int(ln["borrow"]),
		"还 > 借 —— 这卡是贷款不是印钞机(数值再调也不许倒挂)")
	# ⚑ 2026-09-01:`when: "shop"` 换成 `fire: "buy"`(消耗牌全部自动触发)。
	# **契约的意图一字未变** —— 借钱是为了买卡, 所以借款必须发生在商店里、且必须在
	# 这次购买之前到账。`fire: "buy"` = 买下那一刻就借, 比「进栏位等玩家点」更强地
	# 保证了这一点(玩家不可能借完忘了花)。
	t.eq(String(adv.get("fire", "")), "buy",
		"预支买下即借 —— 借钱是为了买卡, 拍内借了没有出口")
