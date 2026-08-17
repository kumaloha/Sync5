extends RefCounted

# --- v0.1 joker roster ---
func run(t) -> void:
	# roster shape (2026-08-12 流派批: 删 popup/backup, 加族内件×4 + backer/bench/boxseats + trim;
	# 缘由与增删改清单见 design/archetypes.md §5)
	var pool := Joker.pool()
	t.eq(pool.size(), 63, "pool holds 62 jokers(2026-08-16 双色调拆两张 61→62)")
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
	t.eq(rarities["common"], 23, "twenty-three common supports(快闪 2026-08-16 回池)")
	# ⚠ **twotone 已于 2026-08-14 升回 rare**(先验层实测它把同花抬 9.8×, 而同价位的
	# 近道/四指只有 3.1×/3.0× —— 效力差三倍以上;见 design/jokers.md「第三次重锚」)。
	# ⚠⚠ **这撤销了上面那条「规则牌曝光」措施的一半, 是有意的**:先验数据说要救的是
	# **顺子线**(组合 8.89% 而真人只打出 1.9%), 不是同花线(组合 6.79% / 真人 7.4%, 几乎没差)。
	# 所以近道/四指**留在 uncommon**, 升回去的只有 twotone。
	# 配额上两个方向都在往 jokers_atlas.md §0 的目标(罕见 ~18 · 稀有 ~10)靠。
	t.eq(rarities["uncommon"], 22, "twenty-two uncommon supports")
	t.eq(rarities["rare"], 10, "ten rare supports(双色调拆两张, rare 9→10)")
	t.eq(String(Joker.by_id("fourfingers").rarity), "uncommon", "fourfingers stays uncommon (顺子线要救)")
	# ⚑ 拆分后单张实测 5.3×(先验层 N=20万, Δ同花族 +29.7pp), 两张都装 9.6× = 老 twotone。
	# 仍是同类规则牌里最强(近道/四指只 1.8×), 所以 rare 保持不动。
	t.eq(String(Joker.by_id("blacktone").rarity), "rare", "黑调 rare")
	t.eq(String(Joker.by_id("redtone").rarity), "rare", "红调 rare")
	# ⚑ 快闪 2026-08-16 **按用户 08-15 那条原则复活**:「仅限一轮的卡不该删, 该是窗口窄 ⇒ 效果强」。
	# ⚠ 但**光加数额是假修**(design/jokers.md 原话)—— 它的死因是 `section_eq: 0` 而**商店最早
	# S1 过半才开**, 玩家根本没机会在第 1 段拥有它(bot 2685 局触发 0%)。
	# ⇒ 窗口改成**每段第 1 拍**的滚动窗口:每段都有第 1 拍 ⇒ 何时买到都够得着,
	# 而窗口仍然窄(4/24 = 16.7%)⇒ 效果强(80% 每拍目标, 期望 13.3%/拍, 族内锚 12%)。
	t.check(Joker.by_id("popup") != null, "快闪已回池(窗口从「只有第 1 段」改成「每段第 1 拍」)")
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
		base + 3 * t._bonus("turnover"), "turnover bonus per discard")
	t.eq(Settle.run(flush_res, [null, Joker.by_id("tipjar"), null, null], {"discards": 0})["coins"],
		4 + 2, "tipjar +2 coins on zero discards")
	t.eq(Settle.run(flush_res, [null, Joker.by_id("tipjar"), null, null], {"discards": 1})["coins"],
		4, "tipjar silent after a discard")

	# chord: cache all one suit (wilds match anything)
	var same_suit := [t._c(3, 1), t._c(9, 1), t._c(12, 1)]
	var mixed := [t._c(3, 1), t._c(9, 2), t._c(12, 1)]
	var with_wild := [t._c(3, 1), Card.new(Card.JOKER_RANK, Card.JOKER_BIG), t._c(12, 1)]
	t.eq(Settle.run(flush_res, [null, Joker.by_id("chord"), null, null], {"cache_cards": same_suit})["score"],
		base + t._bonus("chord"), "chord bonus on a one-suit cache")
	t.eq(Settle.run(flush_res, [null, Joker.by_id("chord"), null, null], {"cache_cards": mixed})["score"],
		base, "chord silent on a mixed cache")
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
	t.eq(Settle.run(flush_res, [null, Joker.by_id("chorus"), null, null],
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

	# bassline: ×0.25 per 12 discards
	var bass := Joker.by_id("bassline")
	bass.on_discard(11)
	t.eq(Settle.run(flush_res, [null, bass, null, null], {})["score"],
		base, "bassline silent below 12 discards")
	bass.on_discard(1)
	t.eq(Settle.run(flush_res, [null, bass, null, null], {})["score"],
		int(round(base * 1.25)), "bassline ×1.25 at 12 discards")
	bass.on_discard(12)
	t.eq(Settle.run(flush_res, [null, bass, null, null], {})["score"],
		int(round(base * 1.5)), "bassline ×1.5 at 24 discards")

	# mirror: re-applies the target at half power
	var mirror := Joker.by_id("mirror")
	t.eq(Settle.run(flush_res, [Joker.by_id("mono"), mirror, null, null], {})["score"],
		int(round(float(base) * t._tmult("mono", "FLUSH") * (1.0 + (t._tmult("mono", "FLUSH") - 1.0) * 0.5))),
		"mirror copies the target at half power")
	t.eq(Settle.run(flush_res, [null, mirror, null, null], {})["score"],
		base, "mirror silent without a target")
	t.eq(Settle.run(pair_res, [Joker.by_id("mono"), mirror, null, null], {})["score"],
		int(pair_res["score"]), "mirror silent when the target missed")

	# interest: cap at +5
	t.eq(Settle.run(flush_res, [null, Joker.by_id("interest"), null, null], {"coins": 40})["coins"],
		4 + 5, "interest caps at +5")

	# ---- 2026-08-12 流派批(design/archetypes.md §3):族内件 + 缓存件 + 经济件 ----
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

	# ---- 2026-08-13 引擎波次·子波1:动作内容信号(design/jokers_atlas.md)----
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
		{"faces_discarded": 3})["score"], base + int(t._bonus("stageexit")) * 3,
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
	t.eq(Settle.run(flush_res, [null, Joker.by_id("royalty"), null, null], {})["coins"],
		pat_coins * 2, "royalties double the hand's own coin reward")
	t.eq(Settle.run(flush_res, [null, Joker.by_id("royalty"), Joker.by_id("tipjar"), null],
		{"discards": 0})["coins"],
		pat_coins * 2 + int(t._do_amount("tipjar", "coins")),
		"royalties do not double another card's coin bonus")
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
	_t_upgrade(t)


## 升级(2026-08-16, 金币的主出口)—— 规格在 data/economy.json 的 joker_upgrade 注释。
func _t_upgrade(t) -> void:
	var base := {"mult": 1.0, "additive": 0, "bonus": 0, "bonus_pct": 0.0,
		"coins_bonus": 0, "chips": 0, "kind": 0, "base_score": 0,
		"scoring_cards": [], "cache_cards": []}
	# ⚠⚠⚠ **这条是整套升级里唯一会静默炸掉平衡的地方。**
	# 乘子必须按 `1 + (x−1)×scale` 放大:×1.5 的卡满级 = **×2.0**。
	# 若误写成 `x × scale`, 满级会变成 ×3.05 —— 而且它**不报错**, 只是所有乘子卡
	# 悄悄变成三倍强。四级下来是指数, 不是线性。
	var c5 := base.duplicate()
	Fx.apply_effects([{"do": {"mult": 1.5}}], {}, c5, 2.0)
	t.check(absf(float(c5["mult"]) - 2.0) < 0.001,
		"满级乘子 ×1.5 → ×2.0(按**增量**放大);写成整数放大会得到 ×3.05 = 指数爆炸")
	var c1 := base.duplicate()
	Fx.apply_effects([{"do": {"mult": 1.5}}], {}, c1, 1.0)
	t.check(absf(float(c1["mult"]) - 1.5) < 0.001, "Lv1 逐字节不变 —— 加功能不许改既有行为")
	var cb := base.duplicate()
	Fx.apply_effects([{"do": {"bonus": 240.0}}], {}, cb, 2.0)
	t.eq(int(cb["bonus"]), 480, "满级加分 240 → 480(加分族按整数放大是对的)")
	# ⚠ 金币不放大 —— 升级印钱就是正反馈:钱越多升得越多, 升得越多钱越多。
	var cc := base.duplicate()
	Fx.apply_effects([{"do": {"coins": 3.0}}], {}, cc, 2.0)
	t.eq(int(cc["coins_bonus"]), 3, "金币通道**不**随等级放大")
	# ⚑ 规则牌不可升级 —— 这不只是「没数值可升」, 它是红调/黑调的**平衡杠杆**:
	# 它们开局 5.3× 最强, 但吃不到升级红利, 中后期被满级乘子卡压过去。
	var rule := Joker.by_id("blacktone")
	t.check(rule != null and not rule.can_upgrade(), "规则牌不可升级(红调/黑调靠这条被时间轴拉平)")
	var up := Joker.by_id("neonsign")
	t.check(up != null and up.can_upgrade(), "带 effects 的普通卡可升级")
	t.eq(up.upgrade_cost(), int(GameConfig.UPGRADE_COSTS[0]), "第一级价格取自 economy.json")
	up.level = GameConfig.UPGRADE_MAX_LEVEL
	t.check(not up.can_upgrade(), "满级不可再升")
	t.eq(up.upgrade_cost(), -1, "满级 upgrade_cost() = −1, 不是 0 —— 0 会被读成「免费」")
	up.level = 1
