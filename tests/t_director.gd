extends RefCounted

## B 轴 · Director 的契约(docs/design/difficulty.md §3 · core/director.gd · data/director.json)。
##
## ⚠ 锁的是**结构**, 不是内容 —— 第几局走哪个状态、货架偏多少是设计, 用户直接改 JSON。
## 所以这里**一个死数字都不抄**:序列长度、循环点、档宽、稀有度名单全部从 DB 推导
## (CLAUDE.md 的老教训 —— 抄死的断言等于给每次调参加一道无意义的返工)。
##
## ⚑ 这一份要守住的四件事, 每一件都对应一条拍过板的边界:
##   ① **Director 不许调目标分** —— 一局能调的只有两样(脸的排布 + 货架), 多一个键就红;
##   ② **不读 context** —— 入口只有「第几局」一个参数;
##   ③ **接不上也不许改现状** —— 没有排序表时逐字节退回 SectionMod, 连 RNG 消耗都一样;
##   ④ **重复必须是有意的** —— exclude 那条守卫不许在 Director 这条路上丢掉。

func run(t) -> void:
	var cfg: Dictionary = DB.director()
	t.eq(DB.validate_director(cfg), "", "出厂的 data/director.json 是干净的")

	var seq: Array = Director.sequence()
	var states: Dictionary = Director.states()
	var n := seq.size()
	var lf := Director.loop_from()
	var span := n - lf
	t.check(n > 0, "sequence 非空")
	t.check(span > 0, "loop_from 在序列里 —— 否则走完序列就没有下一局")

	# --- ① Director 一局能调的只有两样 ---
	# 多一个键 = 多一条「玩家看得见的数按局数漂」的通道, 那正是 DDA 被察觉的形状。
	for sname in states:
		var st: Dictionary = states[sname]
		var live: Array = []
		for k in st:
			if not String(k).begins_with("_"):
				live.append(String(k))
		t.eq(live.size(), 2, "state '%s' 只有两个可调项(face_bias + shelf)" % sname)
		t.check(live.has("face_bias"), "state '%s' 有 face_bias" % sname)
		t.check(live.has("shelf"), "state '%s' 显式写了 shelf(中性也要写 {})" % sname)

	# --- 序列:每一局都有状态, 走完之后循环 ---
	for i in range(n):
		t.eq(Director.state_for(i + 1), String(seq[i]), "第 %d 局走 sequence 第 %d 项" % [i + 1, i + 1])
	for r in range(n + 1, n + 3 * span + 1):
		t.eq(Director.state_for(r), String(seq[lf + (r - 1 - lf) % span]),
			"第 %d 局按 loop_from 循环回去" % r)
	# ⚠ 越界钳到第 1 局, **不返回空** —— 空状态会让调用方静默失去 Director,
	# 和 Tutorial.seconds 越界返回 0 会让时钟停摆是同一个形状。
	t.eq(Director.state_for(0), Director.state_for(1), "第 0 局钳到第 1 局")
	t.eq(Director.state_for(-7), Director.state_for(1), "负数下标同上")
	for r in range(1, n + 2 * span + 1):
		t.check(Director.state_for(r) != "", "第 %d 局有状态" % r)
		t.check(Director.BIASES.has(Director.face_bias(r)), "第 %d 局的 face_bias 合法" % r)
		t.check(not Director.entry_for(r).is_empty(), "第 %d 局查得到状态条目" % r)

	# --- ② 只按局数索引:同一个位置永远拿到同一个数 ---
	# 这是「DDA 必须不可见」那条外部约束的可执行版本(docs/design/difficulty.md §3 末)。
	# Director 的入口只有 run_index 一个参数, 所以它可以被直接断言:两趟一模一样。
	var pass1: Array = []
	for r in range(1, n + span + 1):
		pass1.append(Director.state_for(r))
	for r in range(1, n + span + 1):
		t.eq(Director.state_for(r), String(pass1[r - 1]), "第 %d 局第二趟仍是同一个状态" % r)

	# --- 档:温和 = 最容易的一段, 最狠 = 最难的一段(排序由易到难) ---
	var ranked: Array = []
	for i in range(12):
		ranked.append("f%02d" % i)
	var frac := Director.band_fraction()
	t.check(frac > 0.0 and frac <= 1.0, "band_fraction 在 (0, 1]")
	var prev_k := 0
	for m in range(1, ranked.size() + 1):
		var sub: Array = ranked.slice(0, m)
		var k := Director.band_size(m)
		t.check(k >= 1 and k <= m, "n=%d 的档宽在 [1, n] —— 空档是个静默死锁" % m)
		t.check(k >= prev_k, "档宽随池子单调不减(n=%d)" % m)
		prev_k = k
		for b in Director.BIASES:
			var bd: Array = Director.band(sub, b)
			t.eq(bd.size(), k, "n=%d bias=%s 的档宽 = band_size(n)" % [m, b])
			for i in range(1, bd.size()):
				t.eq(sub.find(bd[i]), sub.find(bd[i - 1]) + 1,
					"n=%d bias=%s 的档是排序上**连续**的一段" % [m, b])
		t.eq(String(Director.band(sub, "mild")[0]), String(sub[0]),
			"n=%d 温和档从最容易的那张起" % m)
		var harsh: Array = Director.band(sub, "harsh")
		t.eq(String(harsh[harsh.size() - 1]), String(sub[m - 1]), "n=%d 最狠档到最难的那张止" % m)
		var mid: Array = Director.band(sub, "median")
		t.check(sub.find(mid[0]) >= sub.find(Director.band(sub, "mild")[0]),
			"n=%d 中位档不比温和档更靠前" % m)
		t.check(sub.find(mid[mid.size() - 1]) <= sub.find(harsh[harsh.size() - 1]),
			"n=%d 中位档不比最狠档更靠后" % m)
		if m == 1:
			t.eq(String(Director.band(sub, "mild")[0]), String(Director.band(sub, "harsh")[0]),
				"只有一张脸时三档同解")
	# 档宽必须真的跟着 band_fraction 走 —— 允许一张的取整误差, 再多就是没在用这个参数。
	for m in [20, 50, 100]:
		t.check(abs(float(Director.band_size(m)) / float(m) - frac) <= 1.0 / float(m) + 1e-9,
			"n=%d 时档宽比例贴着 band_fraction(取整误差 ≤1 张)" % m)
	t.eq(Director.band(ranked, "nope").size(), Director.band(ranked, "median").size(),
		"不认识的倾向退回中位(中性), 不是空档")
	t.eq(Director.band([], "mild").size(), 0, "空池子给空档")

	# --- 掷点:落在档里, 且认 exclude ---
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for b in Director.BIASES:
		var bd: Array = Director.band(ranked, b)
		for i in range(20):
			t.check(bd.has(Director.pick_face(ranked, b, rng)), "掷出来的脸落在 '%s' 档里" % b)
	var mild: Array = Director.band(ranked, "mild")
	var ex: Array = mild.slice(0, mild.size() - 1)
	for i in range(8):
		t.eq(Director.pick_face(ranked, "mild", rng, ex), String(mild[mild.size() - 1]),
			"exclude 掉的脸不会再被掷到(重复必须是有意的)")
	# ⚠ 整档被排空时**退回整档**, 不返回空 —— 同 SectionMod.roll「宁可重复也不要漏一堵墙」。
	t.check(mild.has(Director.pick_face(ranked, "mild", rng, mild)),
		"一档被 exclude 排空时退回整档, 不返回空串")
	t.eq(Director.pick_face([], "mild", rng), "", "空池子返回空串")

	# --- ③ 接不上 Director 时**逐字节**等于现状 ---
	var a := RandomNumberGenerator.new()
	var b2 := RandomNumberGenerator.new()
	a.seed = 99
	b2.seed = 99
	# ⚠⚠ **等价契约的正确形状是「同一个局数下等价」**(2026-08-16 加 min_run 之后)。
	# 旧写法比的是 `SectionMod.roll_run(b2)`(不带局数 = **全解锁**)vs `Director.roll_run(1, ...)`
	# (第 1 局 = **禁回锁着**)—— 两边看的池子不一样, 差异是 min_run **有意**造成的, 不是漂。
	const RUN_IDX := 1
	var plain: Dictionary = SectionMod.roll_run(b2, RUN_IDX)
	var same: Dictionary = Director.roll_run(RUN_IDX, a)
	t.eq(same.size(), plain.size(), "没有排序表时段数与现有掷法一致")
	for w in GameConfig.WALL_SECTIONS:
		t.eq(String(same[int(w)]), String(plain[int(w)]), "第 %d 段与现有掷法掷出同一张脸" % int(w))
	t.eq(a.randi(), b2.randi(), "RNG 消耗也一样 —— 接上 Director 不会让探针的复现性漂")

	# --- 有排序表时:RNG 消耗 = 首墙一次简单关判定 + 每个实墙恰好一次掷点;
	# 脸仍来自本段池子, 且落在本局的倾向档里(2026-08-24 首墙两层放水后的新契约)---
	var ranking := {}
	for w in GameConfig.WALL_SECTIONS:
		ranking[int(w)] = SectionMod.pool_for(int(w))
	var c := RandomNumberGenerator.new()
	var e2 := RandomNumberGenerator.new()
	c.seed = 7
	e2.seed = 7
	var ri := GameConfig.S1_FACE_MIN_RUN          # 解锁局:走「简单关判定 + 掷脸」全路径
	var faces: Dictionary = Director.roll_run(ri, c, ranking)
	# 镜像消耗:第 1 步 = 首墙的简单关判定;触发则首墙不掷。逐墙用 SectionMod.roll
	# 镜像(不按「每墙一步」硬数步数 —— 旧契约保证的是排序路径与普通掷法**同耗**,
	# 不是每墙恰好一步, 这里继承那条既有等价性)。
	var ez := e2.randf() < GameConfig.S1_EASY_CHANCE
	var drawn2: Array = []
	var out2 := {}
	for w0 in GameConfig.WALL_SECTIONS:
		if int(w0) == 0 and ez:
			out2[int(w0)] = ""
			continue
		var f2 := SectionMod.roll(int(w0), e2, drawn2, ri)
		out2[int(w0)] = f2
		if f2 != "":
			drawn2.append(f2)
	# ⚑ 2026-08-26 序列杀伤预算:修复走**派生流**, 主流恒定只多一掷(派种子)——
	# 消耗与序列内容解耦, 镜像照跑同一份 enforce 即同耗(修复次数不影响主流)。
	SectionMod.enforce_axis_budget(out2, e2, ri)
	t.eq(c.randi(), e2.randi(), "RNG 消耗 = 简单关判定一掷 + 每个实墙照常掷 + 修复派种一掷")
	t.eq(String(faces.get(0, "x")) == "", ez, "首墙空脸当且仅当简单关判定触发")
	t.eq(faces.size(), GameConfig.WALL_SECTIONS.size(), "每个墙段一张脸(空脸也占位)")
	var pools_disjoint := true
	var seen := {}
	var off_band := 0
	for w in GameConfig.WALL_SECTIONS:
		var idx := int(w)
		var pool: Array = SectionMod.pool_for(idx)
		if idx == 0 and String(faces[0]) == "":
			continue                              # 简单关:首墙无脸, 无池/档可查
		t.check(pool.has(String(faces[idx])), "第 %d 段的脸来自它自己的池子" % idx)
		# ⚠ 档要从**过滤后**的排序池算 —— Director 掷点用的就是它(`ranked_pool` 会按
		# min_run 摘掉没解锁的脸), 拿未过滤的 ranking 算档等于和另一个池子比。
		# ⚑ 2026-08-26 围殴修复走素掷, 被修的槽会离档;镜像认不出 Director 修了哪个槽
		# (内容路径不同), 所以逐槽断言退为**总量断言**:离档 ≤1 槽(修复的文档化让步)。
		var in_band: bool = Director.band(Director.ranked_pool(idx, ranking, ri),
			Director.face_bias(ri)).has(String(faces[idx]))
		if not in_band:
			off_band += 1
		for fid in pool:
			if seen.has(fid):
				pools_disjoint = false
			seen[fid] = true
	t.check(off_band <= 1, "倾向档总量:离档 ≤1 槽(围殴修复的素掷让步, 实测 %d)" % off_band)
	# ⚠ 条件断言:池子互斥时「一局不重复」是硬保证;将来放开 tiers(一张脸跨轮)后
	# 一档可能被 exclude 排空而退回整档, 那时重复是**有意的退让**, 不是漏掉守卫。
	if pools_disjoint:
		var uniq := {}
		var dup := false
		for w in GameConfig.WALL_SECTIONS:
			var f := String(faces[int(w)])
			if uniq.has(f):
				dup = true
			uniq[f] = true
		t.check(not dup, "池子互斥时一局四张脸互不相同")
	# 排序表里混进一张不属于这一段的脸时, 必须被过滤掉(仪器输出会跨轮)。
	var first_wall := int(GameConfig.WALL_SECTIONS[0])
	var dirty: Array = ["__not_a_face__"] + SectionMod.pool_for(first_wall)
	var cleaned: Array = Director.ranked_pool(first_wall, {first_wall: dirty})
	t.check(not cleaned.has("__not_a_face__"), "排序表与池子取交 —— 不属于本段的脸被滤掉")
	t.eq(cleaned.size(), SectionMod.pool_for(first_wall).size(), "取交之后剩的就是本段池子")
	t.eq(Director.ranked_pool(first_wall, {}).size(), 0, "没给排序 = 空, 由调用方退回 SectionMod")

	# --- 货架:权重 = 基础 × 本局乘数, 不写 shelf = 不动货架 ---
	var base: Dictionary = DB.economy()["draft_rarity_weights"]
	var neutral := 0
	for r in range(1, n + span + 1):
		var w2: Dictionary = Director.shelf_weights(r)
		var mult: Dictionary = Director.shelf_rarity_mult(r)
		t.eq(w2.size(), base.size(), "第 %d 局的货架权重按 economy 的稀有度补齐" % r)
		for k in base:
			t.check(float(w2[k]) > 0.0, "第 %d 局 '%s' 的权重 > 0(0 等于把一档从货架上删掉)" % [r, k])
			t.eq(float(w2[k]), float(base[k]) * float(mult[String(k)]),
				"第 %d 局 '%s' 的权重 = 基础 × 本局乘数" % [r, k])
		if Director.shelf(r).is_empty() and neutral == 0:
			neutral = r
	if neutral > 0:
		for k in base:
			t.eq(float(Director.shelf_weights(neutral)[k]), float(base[k]),
				"中性那一局 '%s' 的货架权重逐字节等于基础权重" % k)

	# --- schema 门禁:越界的表必须红, 而且要为**正确的理由**红 ---
	# ⚑ 连错误信息一起断 —— 否则「unknown key」也是非空, 会为了错误的理由变绿
	#    (docs/design/difficulty.md §5 的教学弧那条就踩过这个)。
	var rar: Array = base.keys()
	var r0 := String(rar[0])
	var ok := _cfg({"a": {"face_bias": "mild", "shelf": {}}}, ["a"])
	t.eq(DB.validate_director(ok), "", "最小合法表通过(fixture 自检)")
	var tilt := _cfg({"a": {"face_bias": "harsh",
		"shelf": {"rarity_weight_mult": {r0: 2.0}}}}, ["a"])
	t.eq(DB.validate_director(tilt), "", "带货架倾向的表通过")

	# ① 目标分那条铁律
	var tgt := _cfg({"a": {"face_bias": "mild", "shelf": {"target_mult": 1.5}}}, ["a"])
	t.check(DB.validate_director(tgt).contains("目标分"),
		"改目标分被拒, 且错误信息点名铁律(不是一句 unknown key)")
	var death := _cfg({"a": {"face_bias": "mild", "shelf": {}}}, ["a"])
	death["death_spec"] = [0.1]
	t.check(DB.validate_director(death).contains("death_spec"), "难度形状被拒")
	var clocks := _cfg({"a": {"face_bias": "mild", "shelf": {"gig_clocks": [8.0]}}}, ["a"])
	t.check(DB.validate_director(clocks).contains("gig_clocks"), "拍长被拒")
	# ② 价格必须走 docs/design/numbers.md 的宪法
	var price := _cfg({"a": {"face_bias": "mild", "shelf": {"price_delta": -1}}}, ["a"])
	t.check(DB.validate_director(price).contains("price_delta"), "价格被拒")
	# ③ 「必定出某张牌」是卡面效果, 不是 Director 的口
	var gtee := _cfg({"a": {"face_bias": "mild", "shelf": {"target_guaranteed": true}}}, ["a"])
	t.check(DB.validate_director(gtee).contains("卡面"), "「必定出 Target」被拒, 理由是它该写在卡面上")
	var tw := _cfg({"a": {"face_bias": "mild", "shelf": {"target_weight_mult": 3.0}}}, ["a"])
	t.check(DB.validate_director(tw) != "", "Target 权重乘数被拒(卡面效果, 不是按局数的暗改)")
	# ④ 不读 context
	var ctx := _cfg({"a": {"face_bias": "mild", "shelf": {}}}, ["a"])
	ctx["inputs"] = []
	t.check(DB.validate_director(ctx).contains("不读 context"), "读 context 的键被拒")
	# 脸的参数不许从 Director 覆写
	var fp := _cfg({"a": {"face_bias": "mild", "shelf": {"time_penalty": 2.0}}}, ["a"])
	t.check(DB.validate_director(fp).contains("只排布脸"), "脸的参数被拒 —— Director 只排布脸, 不改脸")
	# ⚠ 但**状态名**不受禁用词表约束 —— 草案七状态里就有 Mastery, 撞词表是误伤。
	var mname := _cfg({"mastery": {"face_bias": "mild", "shelf": {}}}, ["mastery"])
	t.eq(DB.validate_director(mname), "", "状态名撞上禁用词表不算越界(禁的是字段, 不是名字)")

	# 结构错的表
	var badbias := _cfg({"a": {"face_bias": "gentle", "shelf": {}}}, ["a"])
	t.check(DB.validate_director(badbias) != "", "不认识的 face_bias 被拒")
	var noshelf := _cfg({"a": {"face_bias": "mild"}}, ["a"])
	t.check(DB.validate_director(noshelf) != "", "state 漏写 shelf 被拒(中性必须是有意的)")
	var ghost := _cfg({"a": {"face_bias": "mild", "shelf": {}}}, ["b"])
	t.check(DB.validate_director(ghost) != "", "sequence 指向不存在的 state 被拒")
	var dead := _cfg({"a": {"face_bias": "mild", "shelf": {}},
		"b": {"face_bias": "harsh", "shelf": {}}}, ["a"])
	t.check(DB.validate_director(dead) != "", "定义了却没排进 sequence 的 state 被拒(死行)")
	var emptyseq := _cfg({"a": {"face_bias": "mild", "shelf": {}}}, [])
	t.check(DB.validate_director(emptyseq) != "", "空 sequence 被拒")
	var loop_hi := _cfg({"a": {"face_bias": "mild", "shelf": {}}}, ["a"], 1)
	t.check(DB.validate_director(loop_hi) != "", "loop_from 越界被拒 —— 否则走完序列就没有下一局")
	var loop_lo := _cfg({"a": {"face_bias": "mild", "shelf": {}}}, ["a"], -1)
	t.check(DB.validate_director(loop_lo) != "", "loop_from 负数被拒")
	var bf0 := _cfg({"a": {"face_bias": "mild", "shelf": {}}}, ["a"], 0, 0.0)
	t.check(DB.validate_director(bf0) != "", "band_fraction = 0 被拒(每一档都空)")
	var bf2 := _cfg({"a": {"face_bias": "mild", "shelf": {}}}, ["a"], 0, 1.5)
	t.check(DB.validate_director(bf2) != "", "band_fraction > 1 被拒(等于没有倾向)")
	var bf1 := _cfg({"a": {"face_bias": "mild", "shelf": {}}}, ["a"], 0, 1.0)
	t.eq(DB.validate_director(bf1), "", "band_fraction = 1 合法(整池 = 不挑)")
	# ⚠ 拼错的稀有度会**静默不生效**(乘数查不到就退回 1.0)—— 这个项目栽过六次的形状。
	var badrar := _cfg({"a": {"face_bias": "mild",
		"shelf": {"rarity_weight_mult": {"legendary": 2.0}}}}, ["a"])
	t.check(DB.validate_director(badrar).contains("legendary"), "不是 economy 稀有度的键被拒")
	var zero := _cfg({"a": {"face_bias": "mild",
		"shelf": {"rarity_weight_mult": {r0: 0.0}}}}, ["a"])
	t.check(DB.validate_director(zero) != "", "稀有度乘数 = 0 被拒(那是改规则, 不是加倾向)")
	var neg := _cfg({"a": {"face_bias": "mild",
		"shelf": {"rarity_weight_mult": {r0: -1.0}}}}, ["a"])
	t.check(DB.validate_director(neg) != "", "稀有度乘数为负被拒")
	var extra := _cfg({"a": {"face_bias": "mild", "shelf": {"nope": 1}}}, ["a"])
	t.check(DB.validate_director(extra) != "", "shelf 里不认识的键被拒")
	var missing := {"sequence": ["a"], "states": {"a": {"face_bias": "mild", "shelf": {}}}}
	t.check(DB.validate_director(missing) != "", "缺顶层键被拒")
	# ⚑ 1.0 必须带导演(2026-08-18 用户拍板「director 是必须的」):
	# 排序表四段齐全非空 —— 这条红 = 要么忘了跑 tools/price.gd 重刷 ranking.json,
	# 要么脸池变了(db 的 validate_ranking 会先红并指路)。
	var rk := DB.ranking_tiers()
	for sec in range(4):
		t.check(rk.has(sec) and not (rk[sec] as Array).is_empty(),
			"ranking 第 %d 段必须喂满(空表 = 没有导演, 只是随机)" % sec)

	# ---- context(2026-08-19「基于 context 生成关卡」, 推翻 08-14「不读 context」)----
	# 出厂开关:**两个都开**(08-19 晚用户拍板:「开, 就是要千人千面, 但不要被察觉」)。
	t.check(Director.novelty_on(), "novelty ships ON (N axis, generating.md says it must be external)")
	t.check(Director.streak_shift_on(),
		"streak_shift ships ON (user 08-19: thousand faces, never detectable)")
	t.check(Director.returning_on(), "returning ships ON (context.md fork #3 approved)")
	t.check(Director.explore_on(), "explore_shelf ships ON (context.md fork #1 approved)")
	# 回归局:强制温和档 + 熟脸(seen 最大者必选 —— familiar 反向收缩)
	var rk_ret := DB.ranking_tiers()
	var band_r := Director.band(rk_ret[0], "mild")
	var seen_r := {}
	for id in band_r:
		seen_r[String(id)] = 1
	var fam_id := String(band_r[0])
	seen_r[fam_id] = 9
	for sd in [3, 77]:
		var rr2 := RandomNumberGenerator.new()
		rr2.seed = sd
		t.eq(Director.pick_face(rk_ret[0], "mild", rr2, [], seen_r, true), fam_id,
			"returning run picks the most familiar face (seed %d)" % sd)
	# ⚠ 局号取解锁局(2026-08-24 首墙放水):第 3 局首墙必空, 那不是 mild 档是缓冲期
	var ret_ri := GameConfig.S1_FACE_MIN_RUN
	var ret_roll := Director.roll_run(ret_ri, RandomNumberGenerator.new(), rk_ret,
		{"streak": 5, "returning": true, "seen": seen_r})
	for w in GameConfig.WALL_SECTIONS:
		if int(w) == 0 and String(ret_roll[0]) == "":
			continue                              # 简单关判定触发:首墙无脸, 无档可查
		var pool_w := Director.ranked_pool(int(w), rk_ret, ret_ri)
		t.check(Director.band(pool_w, "mild").has(String(ret_roll[int(w)])),
			"returning run stays in the mild band even on a win streak (sec %d)" % int(w))
	# 纯函数 shift_bias:连败 2 降一档 / 连胜 3 升一档, 阈值不对称是设计
	t.eq(Director.shift_bias("median", -2), "mild", "2 losses soften a step")
	t.eq(Director.shift_bias("median", -1), "median", "1 loss does nothing")
	t.eq(Director.shift_bias("mild", -5), "mild", "already mild: floor")
	t.eq(Director.shift_bias("median", 3), "harsh", "3 wins harden a step")
	t.eq(Director.shift_bias("median", 2), "median", "2 wins do nothing (asymmetric on purpose)")
	t.eq(Director.shift_bias("harsh", 9), "harsh", "already harsh: ceiling")
	t.eq(Director.shift_bias("nosuch", -9), "nosuch", "unknown bias passes through")
	# 阈值是参数(data/director.json context_tuning), 不再写死
	t.eq(Director.shift_bias("median", -1, 1, 3), "mild", "lose threshold 1: one loss softens")
	t.eq(Director.shift_bias("median", 2, 2, 2), "harsh", "win threshold 2: two wins harden")
	t.eq(int(Director.tuning().get("lose_streak", -1)), 2, "shipped lose_streak = 2")
	t.eq(int(Director.tuning().get("win_streak", -1)), 3, "shipped win_streak = 3")
	t.eq(Director.return_gap_s(), 3 * 86400, "shipped return gap = 3 days")
	t.check(absf(Director.explore_mult() - 1.5) < 1e-9, "shipped explore_mult = 1.5")
	# context_tuning 校验:未知键 / 低于下界 都红
	var tn_bad := _cfg({"a": {"face_bias": "mild", "shelf": {}}}, ["a"])
	tn_bad["context_tuning"] = {"lose_streak": 2, "bogus": 1}
	t.check(DB.validate_director(tn_bad).contains("未知键"), "context_tuning rejects unknown keys")
	tn_bad["context_tuning"] = {"explore_mult": 0.5}
	t.check(DB.validate_director(tn_bad).contains("≥"), "context_tuning rejects explore_mult < 1")
	tn_bad["context_tuning"] = {"lose_streak": 1, "win_streak": 1, "return_gap_days": 1, "explore_mult": 1.0}
	t.eq(DB.validate_director(tn_bad), "", "context_tuning at the lower bounds passes")
	# explore_boost 是纯函数:空 used ⇒ 空;有 used ⇒ 只有「没用过的 Target」进字典
	var cands: Array = []
	for jid in ["twin", "stair", "superwild"]:
		cands.append(Joker.by_id(jid))
	t.check(Director.explore_boost(cands, {}).is_empty(), "explore_boost: no history ⇒ no boost")
	var eb := Director.explore_boost(cands, {"twin": 3})
	t.check(not eb.has("twin"), "explore_boost: a used Target is not boosted")
	t.check(eb.has("stair") and absf(float(eb["stair"]) - Director.explore_mult()) < 1e-9,
		"explore_boost: an unused Target gets explore_mult")
	t.check(not eb.has("superwild"), "explore_boost: supports are never boosted")
	# 开关开着时走 shift;ctx 为空仍恒等(逐字节退回的另一半契约)
	t.eq(Director.bias_with_ctx("median", {"streak": -9}), "mild",
		"switch on: losses soften the band")
	t.eq(Director.bias_with_ctx("median", {}), "median", "empty ctx never shifts")
	# ⚑ 契约核心:ctx 缺省空 = 逐字节退回(探针/hundred 验证全靠这条)
	var ra := RandomNumberGenerator.new()
	var rb := RandomNumberGenerator.new()
	ra.seed = 777
	rb.seed = 777
	var no_ctx := Director.roll_run(3, ra, rk)
	var empty_ctx := Director.roll_run(3, rb, rk, {})
	t.eq(no_ctx, empty_ctx, "empty ctx is byte-identical to the old signature")
	t.eq(ra.state, rb.state, "…and consumes the same amount of RNG")
	# novelty:同一档里「见得最少」的那张必选(子集恰好剩 1 张时与种子无关)
	var band3 := Director.band(rk[0], "median")
	t.check(band3.size() >= 1, "band is non-empty")
	var seen_map := {}
	for id in band3:
		seen_map[String(id)] = 5
	var fresh_id := String(band3[band3.size() - 1])
	seen_map[fresh_id] = 0
	for sd in [1, 42, 999]:
		var rr := RandomNumberGenerator.new()
		rr.seed = sd
		t.eq(Director.pick_face(rk[0], "median", rr, [], seen_map), fresh_id,
			"least-seen face always picked (seed %d)" % sd)
	# Boon novelty(岔 #4 已落地):seen 里唯一最少见的 boon 必选, 与种子无关;空 seen 逐字节退回
	var bids := BlindBoon.ids()
	if bids.size() >= 2:
		var bseen := {}
		for b in bids:
			bseen[String(b)] = 5
		bseen[String(bids[1])] = 0
		for sd in [2, 44, 888]:
			var rb2 := RandomNumberGenerator.new()
			rb2.seed = sd
			t.eq(BlindBoon.roll(rb2, bseen), String(bids[1]), "least-seen boon always rolled (seed %d)" % sd)
		var rx := RandomNumberGenerator.new()
		var ry := RandomNumberGenerator.new()
		rx.seed = 5
		ry.seed = 5
		t.eq(BlindBoon.roll(rx), BlindBoon.roll(ry, {}), "empty seen equals no-arg roll")
		var hits := 0
		for sd in range(120):
			var rz := RandomNumberGenerator.new()
			rz.seed = 7000 + sd
			if BlindBoon.roll(rz) == String(bids[1]):
				hits += 1
		t.check(hits < 110, "without seen the roll is not pinned (bids[1] %d/120)" % hits)
	# 数据面:context 节只有两个布尔开关
	var cgood := _cfg({"a": {"face_bias": "mild", "shelf": {}}}, ["a"])
	cgood["context"] = {"novelty": true, "streak_shift": false}
	t.eq(DB.validate_director(cgood), "", "well-formed context section validates")
	var cbad := _cfg({"a": {"face_bias": "mild", "shelf": {}}}, ["a"])
	cbad["context"] = {"nope": true}
	t.check(DB.validate_director(cbad) != "", "unknown context key rejected")
	var cint := _cfg({"a": {"face_bias": "mild", "shelf": {}}}, ["a"])
	cint["context"] = {"novelty": 1}
	t.check(DB.validate_director(cint) != "", "non-bool context switch rejected")

	# --- 首墙两层放水(2026-08-24 用户:原作对照 + 「后面的关也偶尔可以有简单关」)---
	var wr := RandomNumberGenerator.new()
	wr.seed = 424242
	t.check(not SectionMod.wall_face_unlocked(0, 1), "第 1 局首墙未解锁")
	t.check(not SectionMod.wall_face_unlocked(0, GameConfig.S1_FACE_MIN_RUN - 1), "解锁前一局仍锁")
	t.check(SectionMod.wall_face_unlocked(0, GameConfig.S1_FACE_MIN_RUN), "到解锁局放行")
	t.check(SectionMod.wall_face_unlocked(0, -1), "探针缺省(-1)= 全解锁世界, 逐字节不变")
	t.check(SectionMod.wall_face_unlocked(1, 1), "门只锁首墙")
	t.eq(String(SectionMod.roll_run(wr, 1).get(0, "x")), "", "模型侧同一道门(规则不许只在游戏里)")
	t.eq(String(Director.roll_run(2, wr).get(0, "x")), "", "Director 侧:新手期首墙必空")
	# 概率放水:解锁后 400 局, 频率落在 p ± 3σ;其余段恒有脸(简单关只开在首墙)
	var easy := 0
	var others_ok := true
	for i in range(400):
		var fs: Dictionary = Director.roll_run(GameConfig.S1_FACE_MIN_RUN + i, wr)
		if String(fs.get(0, "")) == "":
			easy += 1
		for sec in range(1, GameConfig.SECTIONS_PER_RUN):
			if String(fs.get(sec, "")) == "":
				others_ok = false
	t.check(others_ok, "解锁后 S2-S4 恒有脸 —— 压轴不放水")
	var p := GameConfig.S1_EASY_CHANCE
	var rate := float(easy) / 400.0
	var se3 := 3.0 * sqrt(maxf(0.0001, p * (1.0 - p) / 400.0))
	t.check(absf(rate - p) <= se3 + 0.001,
		"简单关频率带内(%.3f vs p=%.2f ± %.3f)" % [rate, p, se3])


func _cfg(states: Dictionary, seq: Array, lf: int = 0, bf: float = 0.5) -> Dictionary:
	return {"band_fraction": bf, "loop_from": lf, "sequence": seq, "states": states}
