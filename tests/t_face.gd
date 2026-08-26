extends RefCounted

## 直接从 data/faces.json 读一个 param —— 让断言跟着数据走, 而不是抄一份死数字。
func _face_param(fid: String, key: String) -> float:
	for e in DB.faces().get("faces", []):
		if String(e["id"]) == fid:
			return float(e.get("params", {}).get(key, 0.0))
	return 0.0

# --- Boss-face section modifiers ---
func run(t) -> void:
	for m in SectionMod.roster():
		t.check(m.fx_text.split(" ").size() <= 7, "%s text within 7 words" % m.id)
	for idx in GameConfig.WALL_SECTIONS:
		t.check(not SectionMod.pool_for(idx).is_empty(), "wall S%d has a pool" % (idx + 1))
		for id in SectionMod.pool_for(idx):
			t.check(SectionMod.by_id(id) != null, "pool id %s exists" % id)
	# 2026-08-06: no verses left — all 4 sections are walls, so every one of
	# them carries a face. 教学空间因此归零, 首段的池必须留在最温和档。
	t.eq(GameConfig.WALL_SECTIONS.size(), GameConfig.SECTIONS_PER_RUN, "no verses remain")
	var expected_pools := [
		["norepeat", "lostpage", "smallstage", "facedown", "lastcall", "lockup", "onetake", "oneswap"],
		# ⚑ 2026-08-25 红灯退役(管手脚不管结果, 花色打击归变色灯)· 接线退役(解法单一)。
		# ⚑ 2026-08-26 对抗批七脸入池(蒙色/蒙点仍暂存, 欠属性级信念):
		#   T2 +高音/轮盘/变色灯/暗场 · T3 +点名/渐强 · T4 +倒计时(时间族)。
		["setlist", "blindspot", "throttle", "request", "lowend", "highend", "roulette",
			"colorlight", "dimstage", "wetink", "handseal"],
		["callout", "crescendo", "rerun", "raisedbar", "trilogy", "blackout",
			"doubleseal", "ration", "switchtrack"],
		# ⚑ 2026-08-14 用户:「tier4 可以补脸, 只不过都是时间相关的就行」——
		# 末轮从「固定一张」变成「时间族四张」。六秒仍然始终成立:**每张都自带 time_penalty**,
		# 所以 docs/design/blinds.md §6 删掉延音的那条理由(把六秒还回去 = 破坏第四轮主机制)不被违反。
		["countdown", "rush", "overtime", "teardown", "closing"],
	]
	for idx in range(expected_pools.size()):
		t.check(SectionMod.pool_for(idx) == expected_pools[idx],
			"S%d matches the approved final pool" % (idx + 1))
	# ⚠ These used to spell out S1's pool by id, which meant every pool retune
	# reddened the suite for no reason (CLAUDE.md: 抄死断言等于给每次调参加返工).
	# What actually has to hold are STRUCTURAL properties — they survive both
	# retuning and the eventual switch to a search-generated pool table.
	# ⚠ 2026-08-07 二次重构:池子不再手写, **由每张脸的 `tier` 推导**
	# (用户:「每次都要看塞在哪个轮次合适, 这也是脸的一个基础属性」)。
	# 连带作废的是 `arc`(同一张脸跨段复现)—— 一张脸一个 tier 之后那件事
	# 在结构上表达不出来, 守一个不可能发生的情况是死代码。教训留在 docs/design/gates.md。
	for m in SectionMod.roster():
		var tier := SectionMod.tier_of(m.id)
		if tier == 0:
			continue                      # 没入池 = 退役 或 还没决定塞哪轮
		t.check(tier >= 1 and tier <= GameConfig.SECTIONS_PER_RUN,
			"%s 的 tier %d 落在 1..%d" % [m.id, tier, GameConfig.SECTIONS_PER_RUN])
		t.check(SectionMod.pool_for(tier - 1).has(m.id), "%s 出现在它自己声明的第 %d 轮里" % [m.id, tier])
	# 每一轮都要有脸(4 段全是墙), 且只有显式声明为 fixed 的轮次才允许只有一张。
	for idx in GameConfig.WALL_SECTIONS:
		var pool := SectionMod.pool_for(idx)
		t.check(not pool.is_empty(), "S%d 有脸" % (idx + 1))
		if pool.size() < 2:
			t.check(SectionMod.tier_is_fixed(idx + 1),
				"S%d 只有一张脸, 必须在 fixed_tiers 里显式声明" % (idx + 1))
	# ⚑⚑ 末轮的契约从「固定一张」换成「**全员时间族**」(2026-08-14 用户:
	# 「tier4 可以补脸, 只不过都是时间相关的就行」)。
	# ⚠ 六秒是第四轮的**主机制** —— docs/design/blinds.md §6 删掉「延音」的理由就是
	# 「把六秒恢复到七至八秒, 破坏第四轮主机制」。所以末轮每张脸都必须自带 time_penalty,
	# 否则掷到它那一局的终章会**变软**, 正是延音被删的同一个错。
	# ⚑ 2026-08-26 倒计时入池:契约放宽到「**末拍**必缩时」(time_penalty 恒定或
	# time_curve 末值), 曲线族的前两拍 8 秒不违反主机制 —— 终章仍然是紧的。
	for id in SectionMod.pool_for(GameConfig.SECTIONS_PER_RUN - 1):
		t.check(SectionMod.time_penalty_at(String(id), GameConfig.PHRASES_PER_SECTION - 1) > 0.0,
			"末轮的 '%s' 末拍自带缩时 —— 六秒是第四轮的主机制, 不许有脸把它还回去" % id)
	# ⚠⚠ 回归锁:**JSON 数字全是 float, `[4.0].has(4)` 是 false 且不报错**。
	# 2026-08-07 当场踩到 —— fixed_tiers 写了 [4] 却一直判成没写。
	# ⚠ 2026-08-14 补脸之后 `fixed_tiers` 空了, 原来那两条断言**双双变成空测**
	# (一条恒真、一条恒假)—— 空测比没测更糟, 它看起来还在守。
	# 所以改成直接测**那个坑本身**, 用真实的 JSON 解析(字面量夹具是 int, 测不到)。
	var raw = JSON.parse_string('{"fixed_tiers": [4]}')
	t.check(not raw["fixed_tiers"].has(4),
		"(记录事实)JSON 解析出来是 float, 原始数组 .has(int) 匹配不上 —— 这就是那个坑")
	var conv: Array = []
	for v in raw["fixed_tiers"]:
		conv.append(int(v))
	t.check(conv.has(4), "转成 int 之后才判得对 —— core/db.gd 与 SectionMod 都这么做")
	# ── 量级豁免 weak_upper_bound(2026-08-08 用户拍板 A 案)──────────────
	# 覆盖自证判据两条:|z|>=3(信不信得过)**且** 量级>=5%(要不要管)。
	# 量级不够允许豁免, 但**必须显式声明** —— 和 fixed_tiers 同一条原则。
	# ⚠ 声明的是「对**完美玩家**的上界效应小」, 不是「这张脸没用」。
	# ⚠ 循环内计数, 循环外断言一次。
	var _weak: Array = DB.faces().get("weak_upper_bound", [])
	var _weak_bad := 0
	for w in _weak:
		if SectionMod.tier_of(String(w)) <= 0:
			_weak_bad += 1
	t.eq(_weak_bad, 0, "weak_upper_bound 里的每张脸都必须真的在池子里(豁免一张不出场的脸没意义)")
	# A/B:拼错 id / 豁免一张不在池子里的脸, 守卫必须真的会喊。
	var _tw: Dictionary = {"faces": [
		{"id": "a", "name": "A", "cn": "a", "fx": "x", "params": {"time_penalty": 1.0},
			"proof": "score", "tier": 1},
		{"id": "b", "name": "B", "cn": "b", "fx": "x", "params": {"time_penalty": 2.0},
			"proof": "score", "tier": 1}],
		"weak_upper_bound": ["typo_id"]}
	t.check(DB.validate_faces(_tw) != "", "weak_upper_bound 里拼错的 id 被拒")
	_tw["weak_upper_bound"] = ["a"]
	t.eq(DB.validate_faces(_tw), "", "weak_upper_bound 指向池子里真实存在的脸时放行")

	# A/B:tier 的守卫必须真的会喊。
	var _t: Dictionary = {"faces": [
		{"id": "a", "name": "A", "cn": "a", "fx": "x", "params": {"time_penalty": 1.0},
			"proof": "score", "tier": 1}]}
	t.check(DB.validate_faces(_t) != "", "一轮只有一张脸而没声明 fixed 被拒")
	_t["fixed_tiers"] = [1]
	t.eq(DB.validate_faces(_t), "", "声明 fixed 之后接受")
	_t["faces"].append({"id": "b", "name": "B", "cn": "b", "fx": "x",
		"params": {"time_penalty": 1.0}, "proof": "score", "tier": 1})
	t.check(DB.validate_faces(_t) != "", "声明成 fixed 却有两张脸被拒")
	_t["fixed_tiers"] = []
	t.eq(DB.validate_faces(_t), "", "两张脸、不声明 fixed 是正常的一轮")
	_t["faces"][0]["tier"] = 0
	t.check(DB.validate_faces(_t) != "", "tier 0 被拒(轮次从 1 起)")

	# --- 覆盖自证契约 (docs/design/gates.md):进池子就要声明模型里的通路 ---
	# 一条规则如果进不了模型, 它就不该进池子。tools/gate.gd 照这个声明造对照臂,
	# 所以漏声明 / 声明了个不认识的通路都必须当场红 —— 否则门会给它造一条
	# 测不到东西的臂然后放行, 而那正是这道门要拦的形状。
	for fid in SectionMod.pooled_ids():
		t.check(DB.FACE_PROOFS.has(SectionMod.proof(fid)),
			"pooled face %s declares a known proof channel (%s)" % [fid, SectionMod.proof(fid)])
	t.check(SectionMod.proof("rotation") == "", "a retired face needs no proof channel")
	# ⚠ 通路选错会把结论量**反**, 不是量小: 规则 bot 量 freshsheet 得 +1584(脸让人变强),
	# 完美玩家量是 −790。攻击跨拍养牌/时间预算的脸必须走 solver, 不能走 score。
	for fid in ["lostpage", "smallstage", "rush"]:
		t.eq(SectionMod.proof(fid), "solver",
			"%s attacks the solver's planning, so its proof arm must be the perfect player" % fid)
	var _p: Dictionary = {"faces": [{"id": "a", "name": "A", "cn": "a", "fx": "x",
		"params": {"time_penalty": 1.0}, "tier": 1}], "fixed_tiers": [1]}
	t.check(DB.validate_faces(_p) != "", "a pooled face without a proof channel is rejected")
	_p["faces"][0]["proof"] = "vibes"
	t.check(DB.validate_faces(_p) != "", "an unknown proof channel is rejected")
	_p["faces"][0]["proof"] = "score"
	t.eq(DB.validate_faces(_p), "", "a declared channel is accepted")

	# --- 起承転結:同族递进 (2026-08-07 用户拍板 A′ 案) ---
	# 契约 = 软版出现的**最后一段** < 硬版出现的**第一段**。先硬后软不是教学弧,
	# 是难度倒挂 —— 而且它不报错, 只会让「起」变成一段莫名其妙的放水。
	var _fam: Dictionary = DB.faces().get("families", {})
	t.check(not _fam.is_empty(), "至少声明了一族软硬递进(起承転結的载体)")
	for fam in _fam:
		var soft := String(_fam[fam]["soft"])
		var hard := String(_fam[fam]["hard"])
		var st := SectionMod.tier_of(soft)
		var ht := SectionMod.tier_of(hard)
		if st == 0 or ht == 0:
			continue
		t.check(st < ht, "family %s: 软版 %s 在第 %d 轮, 硬版 %s 在第 %d 轮" % [fam, soft, st, hard, ht])
	# A/B:守卫必须真的会喊 —— 把先后倒过来, 必须红。
	var _ff: Dictionary = {"faces": [
			{"id": "soft", "name": "S", "cn": "s", "fx": "x", "params": {"repeat_factor": 0.5},
				"proof": "score", "tier": 1},
			{"id": "hard", "name": "H", "cn": "h", "fx": "x", "params": {"repeat_factor": 0.0},
				"proof": "score", "tier": 2}],
		"fixed_tiers": [1, 2],
		"families": {"repeat_factor": {"soft": "soft", "hard": "hard"}}}
	t.eq(DB.validate_faces(_ff), "", "软先硬后是合法的教学弧")
	_ff["faces"][0]["tier"] = 2
	_ff["faces"][1]["tier"] = 1
	t.check(DB.validate_faces(_ff) != "", "先硬后软被拒(难度倒挂)")
	_ff["faces"][0]["tier"] = 1
	_ff["faces"][1]["tier"] = 2
	_ff["families"] = {"repeat_factor": {"soft": "soft", "hard": "soft"}}
	t.check(DB.validate_faces(_ff) != "", "同一张脸兼任软硬两档被拒")
	_ff["families"] = {"lock_first": {"soft": "soft", "hard": "hard"}}
	t.check(DB.validate_faces(_ff) != "", "两张脸不带这个 param 就不是同一族")

	# --- 设计死亡谱已配置化 (2026-08-07 用户拍板, 从 tools/curve.gd 挪进 data/) ---
	# ⚠ **故意不断言单调递增**:目标函数换成留存之后,「一关比一关难」从原则降级成
	# 未经检验的假设, 而起承転結的「転」本来就不单调。形状由搜索来挑。
	var _ds: Array = DB.run()["death_spec"]
	t.eq(_ds.size(), GameConfig.SECTIONS_PER_RUN, "death_spec 每段一项(表长错了会静默用错分位)")
	for v in _ds:
		t.check(float(v) >= 0.0 and float(v) < 1.0, "death_spec 是到达者死亡率, 落在 [0,1)")

	# --- 段目标 = 表 × 脸的加码, **只有一份实现** ---
	# ⚠ tools/sim.gd 判生死时曾直接读表、没乘 target_mult, 于是 raisedbar 在模型里
	# 整个是空气(游戏 ×1.5, 模型当它不存在)。两处判生死必须走这一个函数。
	t.eq(Run.section_target_for([100, 200, 300, 400], 1, ""), 200, "no face -> the table value")
	t.eq(Run.section_target_for([100, 200, 300, 400], 1, "raisedbar"), 300, "raisedbar scales the target")
	t.eq(Run.section_target_for([100], 3, ""), 100, "a short table clamps instead of going out of bounds")
	t.eq(Run.section_target_for([], 0, ""), 0, "an empty table is 0, not a crash")
	# a face that no pool references is dead data — either place it or retire it
	# on purpose. The retired two are named so the exemption stays deliberate.
	var placed := {}
	for idx in GameConfig.WALL_SECTIONS:
		for id in SectionMod.pool_for(idx):
			placed[id] = true
	# ⚠ `cover` was briefly on this list and it was a mistake — see docs/design/blinds.md §4
	# ("别读代码下结论") / tools/coin.gd. Only rotation is genuinely dead.
	# 没有 tier = 没入池。这必须是**有意的**, 所以退役清单显式写死:
	#   rotation —— 弃牌免费后随手弃一张零成本免疫, 代价为零。
	# ⚑ **`raisedbar` 2026-08-09 由用户拍板进第三轮**(原话:「适合第三轮, 放第二轮会无聊」)
	#   —— 「転」那一段本就该是节奏变化处, 放第二轮只是把「承」变成单纯加量。
	#   它曾在这张清单上, 理由是「不改玩法、只把目标分 ×1.5, 是难度靠抽签的极端形态」;
	#   那**从来不是退役, 是待拍板**(docs/design/blinds.md 里一直写着「要放回来, 告诉我放哪一轮」)。
	# ⚑ 2026-08-25 对抗批两笔新豁免, 都是有意的:
	#   退役 +2:redlight(管手脚不管结果, 补牌路径还从未过滤)· patchin(解法单一只剩硬吃,
	#   「可解除」衣钵传给 callout);
	#   暂存 +11:对抗批新脸, 机制已实装、**等 ranking 重跑后补 tier 入池**
	#   (蒙色/蒙点还欠属性级信念)。入池时从 STAGED 划去 + faces.json 加 tier, 缺一头都红。
	const RETIRED := ["unplugged", "static", "rotation", "cover", "freshsheet",
		"redlight", "patchin"]
	# 2026-08-26 七脸入池后只剩两张:蒙色/蒙点等属性级信念(入池前必修)。
	const STAGED := ["suitveil", "rankfog"]
	for m in SectionMod.roster():
		if RETIRED.has(m.id):
			t.check(not placed.has(m.id), "%s 保持退役(见 docs/design/blinds.md §5)" % m.id)
		elif STAGED.has(m.id):
			t.check(not placed.has(m.id), "%s 暂存中(入池 = faces.json 补 tier + 从 STAGED 划去)" % m.id)
		else:
			t.check(placed.has(m.id), "face %s 有 tier, 进了某一轮的池子" % m.id)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	t.check(SectionMod.roll(1, rng) in SectionMod.pool_for(1), "roll draws from the pool")
	t.eq(SectionMod.roll(99, rng), "", "no roll outside the table")
	# ⚑ 「重复必须是有意的, 不能是偶然的」——`exclude` 守卫(2026-08-14 随 `tiers` 加回,
	# docs/design/blinds.md §3 当年删它时就留了这句后手)。这里直接测原语, 不依赖数据里真有跨轮的脸。
	var p1: Array = SectionMod.pool_for(1)
	var keep: String = String(p1[0])
	var others: Array = p1.slice(1)
	t.eq(SectionMod.roll(1, rng, others), keep,
		"排除掉除一张以外的全部 ⇒ 必然掷到剩下那张")
	t.check(SectionMod.roll(1, rng, p1) in p1,
		"池子被排空时退回全池, 而不是返回 ''(「这一段没有脸」是真实的规则差异, 不能拿来表达排不下)")
	# 一局四张脸 = 唯一真相(原来抄了 7 份)。
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 11
	var run_faces: Dictionary = SectionMod.roll_run(rng2)
	t.eq(run_faces.size(), GameConfig.WALL_SECTIONS.size(), "roll_run 每个墙段一张脸")
	var seen := {}
	for w in run_faces:
		t.check(SectionMod.pool_for(int(w)).has(String(run_faces[w])),
			"roll_run 的 S%d 取自它自己的池子" % (int(w) + 1))
		t.check(not seen.has(run_faces[w]), "roll_run 一局之内不重复掷到同一张脸")
		seen[run_faces[w]] = true
	# ⚠ 逐字节不变的证据:同一个种子, roll_run 与「逐段独立掷」结果相同 ——
	# 单轮时代 exclude 永远筛不掉东西, 所以收口不该改变任何既有读数。
	var rng3 := RandomNumberGenerator.new()
	rng3.seed = 11
	var manual := {}
	for w in GameConfig.WALL_SECTIONS:
		manual[int(w)] = SectionMod.roll(int(w), rng3)
	t.eq(run_faces, manual, "roll_run == 逐段独立掷(当前数据下逐字节不变)")
	t.eq(SectionMod.time_penalty("rush"), 2.0, "rush shaves 2 seconds")
	# ⚠ 不抄死数额 —— 平衡要反复调, 抄死等于给每次调参加一道返工(CLAUDE.md 的老教训:
	# Target 倍率那批抄死的断言一改就红 10 条)。这里锁的是**契约**:入场费真的收钱。
	t.check(SectionMod.phrase_toll("cover") > 0, "cover 每拍收钱")
	t.eq(SectionMod.phrase_toll("cover"), int(_face_param("cover", "phrase_toll")),
		"cover 的数额跟着 faces.json 走")
	t.eq(SectionMod.phrase_toll(""), 0, "没有脸就不收入场费")
	t.eq(SectionMod.target_power("unplugged"), 0.5, "unplugged param from data")
	t.eq(SectionMod.target_power(""), 1.0, "no face -> full power")
	t.check(SectionMod.bonus_disabled("static"), "static disables bonuses")
	t.eq(SectionMod.repeat_factor("norepeat"), 0.5, "norepeat factor from data")
	t.eq(SectionMod.zero_discard_factor("rotation"), 0.5, "rotation factor from data")
	# --- 2026-08-07 批次:改「输入」的脸(docs/design/research_balatro_bosses) ---
	t.eq(SectionMod.cache_evict("lostpage"), 1, "lostpage drops 1 cache card")
	t.eq(SectionMod.cache_evict("freshsheet"), GameConfig.CACHE_CAP, "freshsheet wipes the cache")
	t.eq(SectionMod.cache_evict(""), 0, "no face -> no eviction")
	t.eq(SectionMod.cache_cap("smallstage"), GameConfig.CACHE_CAP - 1, "smallstage shrinks the cache")
	t.eq(SectionMod.cache_cap(""), GameConfig.CACHE_CAP, "no face -> full cache")
	t.eq(SectionMod.target_mult("raisedbar"), 1.5, "raisedbar raises the bar")
	t.eq(SectionMod.target_mult(""), 1.0, "no face -> untouched target")
	t.eq(SectionMod.lock_first("setlist"), 0.5, "setlist halves off-lock hands")
	t.eq(SectionMod.lock_first(""), 1.0, "no face -> no lock")
	# rerun is norepeat's hard tier — SAME param, same code path, only the
	# number differs. If these two ever stop sharing repeat_factor, the
	# 「软硬两档 = 天然难度递进」 story is broken.
	t.eq(SectionMod.repeat_factor("rerun"), 0.0, "rerun zeroes a repeated hand")
	t.check(SectionMod.repeat_factor("rerun") < SectionMod.repeat_factor("norepeat"),
		"rerun is strictly harsher than norepeat")
	# --- 信息隐藏族 ---
	t.check(SectionMod.hide_refill("blindspot"), "blindspot hides the refill")
	t.check(not SectionMod.hide_refill(""), "no face -> refills are visible")
	t.check(SectionMod.hide_faces("facedown"), "facedown hides J/Q/K")
	t.check(not SectionMod.hide_faces("norepeat"), "an unrelated face hides nothing")
	# --- 最终池新增参数全部通过 SectionMod 单一数据门面读取 ---
	t.eq(SectionMod.discard_lock_last("lastcall"), 2.0, "lastcall closes discard for two seconds")
	t.eq(SectionMod.swap_lock_last("lockup"), 2.0, "lockup closes swap for two seconds")
	t.eq(SectionMod.discard_cards_max("onetake"), 2, "onetake caps two discarded cards (2026-08-25 张数重铸)")
	t.eq(SectionMod.swap_action_limit("oneswap"), 1, "oneswap allows one swap action")
	t.eq(SectionMod.action_cards_max("throttle"), 4, "throttle caps four moved cards total")
	t.eq(SectionMod.discard_cards_max("closing"), 2, "closing caps two discarded cards")
	t.check(SectionMod.cache_blocks_red("redlight"), "redlight rejects red cards entering cache")
	t.eq(SectionMod.refill_rank_min("lowend"), 2, "lowend refill minimum comes from data")
	t.eq(SectionMod.refill_rank_max("lowend"), 9, "lowend refill maximum comes from data")
	t.eq(SectionMod.refill_rank_min("highend"), 9, "highend refill minimum comes from data (staged, no tier yet)")
	t.eq(SectionMod.cache_lock_phrases("wetink"), 1, "wetink locks new cache cards for this phrase")
	t.check(SectionMod.seals_random_start("handseal"), "handseal freezes one random opening card (2026-08-25 随机封)")
	t.check(SectionMod.seals_random_cache("doubleseal"), "doubleseal freezes one random cache card")
	t.eq(SectionMod.required_kinds("trilogy"), 3, "trilogy requires three hand types")
	t.check(SectionMod.restores_with_initial_cache("patchin"), "patchin has a recoverable full-power condition")
	t.eq(SectionMod.section_discard_budget("ration"), 12, "ration shares twelve discarded cards")
	t.check(SectionMod.exclusive_action_tracks("switchtrack"), "switchtrack closes the unchosen route")
	t.eq(SectionMod.request_factor("request"), 0.9, "a missed request keeps ninety percent")
	t.eq(SectionMod.joker_power("patchin"), 0.5, "patchin defaults settlement Jokers to half power")
	t.check(SectionMod.tape_required("lastcall"), "clock faces declare their Tape requirement")
	t.check(SectionMod.discard_open("lastcall", 2.01), "lastcall permits discard before the final window")
	t.check(not SectionMod.discard_open("lastcall", 2.0), "lastcall closes exactly at two seconds left")
	t.check(SectionMod.swap_open("lockup", 2.01), "lockup permits swap before the final window")
	t.check(not SectionMod.swap_open("lockup", 2.0), "lockup closes exactly at two seconds left")
	t.check(SectionMod.discard_open("", 0.0) and SectionMod.swap_open("", 0.0),
		"a normal blind does not invent an action gate")
	# --- 「这张脸进不进 Settle」的分类 ---
	# ⚠ 这不是性能标注, 是**正确性**标注:分错了 Solver 的恒等快路径会跳过结算,
	# 那张脸就静默失效, 而目标分照着「它生效了」的难度算。所以直接对着 Settle 验:
	# 归为「不进 Settle」的脸, 必须真的一分不差。
	# 只锁**危险的那个方向**:归类为「不进 Settle」却其实会进 —— 那会被恒等快路径
	# 跳过, 脸静默失效, 而目标分照着「它生效了」算。反方向(归为进 Settle 其实不进)
	# 只是少一次优化, 无害。
	# ⚠ 必须**带小丑牌**测:unplugged 要有 Target 才有的放矢、static 要有奖励分才吃得到,
	# 空槽下它俩本来就不改分 —— 第一版就是这么写的, 两条红全是测试自己的错。
	var mod_res := Pattern.evaluate_best([t._c(14, 2), t._c(13, 2), t._c(12, 2), t._c(11, 2), t._c(9, 2)])
	var mod_slots: Array = [Joker.by_id("mono"), Joker.by_id("neonsign"), null, null]
	for m in SectionMod.roster():
		if SectionMod.affects_settle(m.id):
			continue
		for sl in [[null, null, null, null], mod_slots]:
			var ctx_m := {"prev_kind": Pattern.Kind.FLUSH, "discards": 0,
				"first_kind": Pattern.Kind.PAIR, "mod": m.id}
			t.eq(int(Settle.run(mod_res, sl, ctx_m)["score"]),
				int(Settle.run(mod_res, sl, {})["score"]),
				"%s is classified as NOT touching Settle — it must not" % m.id)

	var flush_res := Pattern.evaluate_best([t._c(2, 0), t._c(5, 0), t._c(8, 0), t._c(11, 0), t._c(13, 0)])
	var base: int = flush_res["score"]
	var mono := Joker.by_id("mono")
	# unplugged: half power — 因子由**数据**推导(tf -> 1+(tf-1)*power), 不手抄
	var tf: float = t._tmult("mono", "FLUSH")
	var weak := 1.0 + (tf - 1.0) * SectionMod.target_power("unplugged")
	t.eq(Settle.run(flush_res, [mono, null, null, null], {"mod": "unplugged"})["score"],
		int(round(float(base) * weak)), "unplugged halves the target's power")
	t.eq(Settle.run(flush_res, [mono, Joker.by_id("mirror"), null, null],
		{"mod": "unplugged", "prev_target_hit": true})["score"],
		int(round(float(base) * weak * (1.0 + (weak - 1.0) * 0.5))),
		"the mirror copies the weakened factor")
	# static: flat bonuses are eaten
	t.eq(Settle.run(flush_res, [null, Joker.by_id("neonsign"), null, null], {"mod": "static"})["score"],
		base, "static eats the flat bonus")
	t.eq(Settle.run(flush_res, [mono, null, null, null], {"mod": "static"})["score"],
		int(round(float(base) * tf)), "static leaves the multiplier alone")
	# norepeat: repeating halves the final score
	t.eq(Settle.run(flush_res, [null, null, null, null], {"mod": "norepeat", "prev_kind": Pattern.Kind.FLUSH})["score"],
		int(base / 2.0), "norepeat halves a repeated hand")
	t.eq(Settle.run(flush_res, [null, null, null, null], {"mod": "norepeat", "prev_kind": Pattern.Kind.PAIR})["score"],
		base, "norepeat spares a fresh hand")
	var hc_res := Pattern.evaluate_best([t._c(2, 0), t._c(5, 1), t._c(8, 2), t._c(11, 3), t._c(13, 0)])
	t.eq(Settle.run(hc_res, [null, null, null, null], {"mod": "norepeat", "prev_kind": Pattern.Kind.HIGH_CARD})["score"],
		int(hc_res["score"]), "a repeated high card is exempt")
	# rotation: zero discards halves the final score
	t.eq(Settle.run(flush_res, [null, null, null, null], {"mod": "rotation", "discards": 0})["score"],
		int(base / 2.0), "rotation halves a zero-discard phrase")
	t.eq(Settle.run(flush_res, [null, null, null, null], {"mod": "rotation", "discards": 1})["score"],
		base, "rotation spares an active phrase")
	# rerun: the hard tier zeroes it instead of halving
	t.eq(Settle.run(flush_res, [null, null, null, null], {"mod": "rerun", "prev_kind": Pattern.Kind.FLUSH})["score"],
		0, "rerun zeroes a repeated hand")
	t.eq(Settle.run(flush_res, [null, null, null, null], {"mod": "rerun", "prev_kind": Pattern.Kind.PAIR})["score"],
		base, "rerun spares a fresh hand")
	t.eq(Settle.run(hc_res, [null, null, null, null], {"mod": "rerun", "prev_kind": Pattern.Kind.HIGH_CARD})["score"],
		int(hc_res["score"]), "rerun keeps the high-card exemption")
	# setlist: the section's opening hand type locks; others are halved
	t.eq(Settle.run(flush_res, [null, null, null, null], {"mod": "setlist", "first_kind": Pattern.Kind.FLUSH})["score"],
		base, "setlist spares the locked hand type")
	t.eq(Settle.run(flush_res, [null, null, null, null], {"mod": "setlist", "first_kind": Pattern.Kind.PAIR})["score"],
		int(base / 2.0), "setlist halves an off-lock hand")
	# the opening phrase itself has nothing to lock against — it SETS the lock
	t.eq(Settle.run(flush_res, [null, null, null, null], {"mod": "setlist"})["score"],
		base, "setlist does not tax the phrase that sets the lock")
	# ⚠ deliberately NO high-card exemption here (unlike norepeat): getting
	# locked onto a high card is exactly the punishment this face is made of.
	t.eq(Settle.run(hc_res, [null, null, null, null], {"mod": "setlist", "first_kind": Pattern.Kind.FLUSH})["score"],
		int(int(hc_res["score"]) / 2.0), "setlist taxes an off-lock high card too")
