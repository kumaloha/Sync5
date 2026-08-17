extends RefCounted

# --- Data config (docs/design/tech.md): loader + validation ---
func run(t) -> void:
	t.eq(DB.load_error(), "", "all data files load clean")
	t.check(FileAccess.file_exists("res://data/boons.json"),
		"finale boons are configured independently from punitive faces")
	# 踩过两次的坑: sim 按 SECTIONS_PER_RUN 迭代, 表比段数长就被**静默截断**成
	# 一个放水盘(random 通关率一度从 0.8% 飙到 42%)。长度必须锁死在一起。
	t.eq(DB.sim()["bot_targets"].size(), GameConfig.SECTIONS_PER_RUN,
		"bot_targets has one entry per section")
	t.eq(int(DB.run()["phrases_per_section"]), 6, "run.json phrases per section")
	t.eq(int(DB.run()["phrases_per_shop"]), 3, "run.json phrases per shop")
	# the shop beat must divide the section evenly or the last "mid" break
	# would land on the section end
	t.check(DB.validate_run({"phrases_per_section": 6, "phrases_per_shop": 4}) != "",
		"non-divisible shop beat rejected")
	t.eq(int(DB.economy()["starting_coins"]), 6, "economy.json starting coins")
	# validation catches planted bad files
	t.check(DB.validate_run({"phrases_per_section": 5}) != "", "missing run key detected")
	t.check(DB.validate_economy({"starting_coins": 6, "typo_key": 1}) != "", "unknown economy key detected")
	t.eq(Character.roster().size(), 8, "8 characters from data")
	t.check(DB.validate_characters({"characters": [{"idx": 1, "cn": "x", "title": "t", "fx": "f"}]}) != "",
		"non-dense idx detected")
	t.eq(Joker.pool().size(), 63, "62 jokers from data(2026-08-16 双色调拆黑调/红调 61→62;declutter/trio/doggybag 仍在池外)")
	# 卡面文字随平衡改, 别抄死 —— 只锁「读得回来 + 符合 D2 的 ≤7 词」
	t.check(Joker.by_id("twin").fx_text.length() > 0, "joker text roundtrip")
	for oid in GameConfig.JOKER_PRICE_OVERRIDES:
		t.check(Joker.by_id(String(oid)) != null, "price override id '%s' exists" % oid)
	# ⚠ 夹具必须带 `proof` —— 否则 2026-08-09 加的「proof 必填」会**先**把它拦下,
	# 这条断言照样是绿的, 但它测的就不再是「未知谓词」了。
	# ⚠ 夹具同样必须带 `curve`(2026-08-10 必填)—— 理由同上面 proof 那条:
	# 缺了它断言照绿, 但测的就不再是「未知谓词」了。
	t.check(DB.validate_jokers({"jokers": [{"id": "x", "name": "X", "cn": "x", "kind": "support",
		"rarity": "common", "curve": "burst", "proof": "score", "fx": "f",
		"effects": [{"when": {"typo": 1}, "do": {"bonus": 1}}]}]}) != "",
		"unknown predicate detected")
	# 小丑牌的覆盖自证通路(docs/design/jokers.md 验证方案)—— 漏声明必须直接红,
	# 否则一张新牌可以悄悄绕过 `tools/kit.gd` 那道门。和脸的 `proof` 同一条锁。
	var good_joker := {"id": "x", "name": "X", "cn": "x", "kind": "support",
		"rarity": "common", "curve": "burst", "proof": "score", "fx": "f"}
	t.eq(DB.validate_jokers({"jokers": [good_joker]}), "",
		"a joker with a declared proof channel validates (sanity check on the fixture)")
	var no_proof := good_joker.duplicate()
	no_proof.erase("proof")
	t.check(DB.validate_jokers({"jokers": [no_proof]}) != "",
		"a joker with no proof channel is rejected")
	var bad_proof := good_joker.duplicate()
	bad_proof["proof"] = "vibes"
	t.check(DB.validate_jokers({"jokers": [bad_proof]}) != "",
		"an unknown proof channel is rejected")
	# 每张现役牌都声明了 —— 这条防的是「加了新牌忘了声明」在真实数据上溜过去
	# ⚠ 清单从 DB._JOKER_PROOFS 推导, 不手抄(2026-08-12 加 shop 通路时这里红过一次)
	for e in DB.jokers():
		t.check(DB._JOKER_PROOFS.has(String(e.get("proof", ""))),
			"joker '%s' declares a known proof channel" % e.get("id", "?"))
	t.eq(int(DB.sim()["runs"]), 1000, "sim.json runs")
	t.check(DB.ui().has("stage"), "ui.json has stage")
	# faces.json 是纯数据表(2026-08-09 散文搬去 docs/design/blinds.md)—— 与其余数据文件不同,
	# `_` 前缀键在这里**不**是免检的注释, 防的是散文悄悄长回来。
	var good_face := {"id": "x", "name": "X", "cn": "x", "fx": "f",
		"params": {"target_power": 0.5}, "proof": "score", "tier": 1}
	t.check(DB.validate_faces({"faces": [good_face]}) != "",
		"a lone tier with no fixed_tiers declaration is still rejected (sanity check on the fixture)")
	t.check(DB.validate_faces({"faces": [good_face], "_note": "hello"}) != "",
		"faces.json rejects an underscore-prefixed top-level key (prose must live in docs/design/blinds.md)")
	var face_with_why := good_face.duplicate()
	face_with_why["_why"] = "hello"
	t.check(DB.validate_faces({"faces": [face_with_why]}) != "",
		"faces.json rejects a per-face _why key (prose must live in docs/design/blinds.md §7)")
	var tape_face := good_face.duplicate(true)
	tape_face["proof"] = "tape"
	t.check(DB.validate_faces({"faces": [tape_face], "fixed_tiers": [1]}) != "",
		"'tape' is not a proof channel — proof stays model-side, gate has no tape arm to build")
	var rt_face := good_face.duplicate(true)
	rt_face["proof"] = "solver"
	rt_face["tape_required"] = true
	t.eq(DB.validate_faces({"faces": [rt_face], "fixed_tiers": [1]}), "",
		"real-time faces keep a model proof and declare tape_required separately")

	# ⚑ 轮次集 `tiers`(2026-08-14 用户:「有大量只有一轮生效的盲注我不喜欢」)。
	# 规格 = docs/design/difficulty.md §2.1。这几条锁的是 schema 的**边界**, 不是内容。
	var multi := good_face.duplicate(true)
	multi["tiers"] = [1, 2]
	t.eq(DB.validate_faces({"faces": [multi], "fixed_tiers": [1, 2]}), "",
		"一张脸可以声明多个合法轮次(tiers)")
	# ⚠ 缺省等价:这是「放开 tiers 后行为逐字节不变」那条的机器可读版本。
	var single := good_face.duplicate(true)
	var explicit := good_face.duplicate(true)
	explicit["tiers"] = [1]
	t.eq(DB.validate_faces({"faces": [single], "fixed_tiers": [1]}),
		DB.validate_faces({"faces": [explicit], "fixed_tiers": [1]}),
		"tiers 缺省 == [tier] —— 显式写单元素与不写完全等价")
	var orphan := good_face.duplicate(true)
	orphan.erase("tier")
	orphan["tiers"] = [1, 2]
	t.check(DB.validate_faces({"faces": [orphan], "fixed_tiers": [1, 2]}) != "",
		"只写 tiers 不写 tier 被拒 —— tier 是定价/门禁的基准位置")
	var offbase := good_face.duplicate(true)
	offbase["tiers"] = [2, 3]          # 主场 tier=1 不在里面
	t.check(DB.validate_faces({"faces": [offbase], "fixed_tiers": [2, 3]}) != "",
		"主场 tier 不在 tiers 里被拒 —— 定价基准会指向它不出现的轮次")
	var duped := good_face.duplicate(true)
	duped["tiers"] = [1, 1]
	t.check(DB.validate_faces({"faces": [duped], "fixed_tiers": [1]}) != "",
		"tiers 里重复的轮次被拒")
	var zero := good_face.duplicate(true)
	zero["tiers"] = [0, 1]
	t.check(DB.validate_faces({"faces": [zero], "fixed_tiers": [1]}) != "",
		"tiers 里的轮次必须 >= 1")
	# ⚑ 教学弧那条断言问的是「**最早**出现在第几轮」, 不是主场 —— 放开 tiers 之后
	# 这两个不再是同一个数。这条锁的就是那个区别:主场顺序对, 但 hard 更早露面 ⇒ 仍该红。
	var soft := {"id": "s", "name": "S", "cn": "s", "fx": "f",
		"params": {"repeat_factor": 0.5}, "proof": "score", "tier": 1, "tiers": [1, 3]}
	var hard := {"id": "h", "name": "H", "cn": "h", "fx": "f",
		"params": {"repeat_factor": 0.0}, "proof": "score", "tier": 3, "tiers": [3]}
	t.eq(DB.validate_faces({"faces": [soft, hard], "fixed_tiers": [1],
		"families": {"repeat_factor": {"soft": "s", "hard": "h"}}}), "",
		"soft 最早在 1、hard 最早在 3 —— 教学弧成立")
	# 反例:**主场顺序仍然是对的**(soft 主场 2 < hard 主场 3), 但 hard 的轮次集里有个 1,
	# 玩家第 1 轮就会先撞上硬的。⚑ 这正是「用主场问顺序」看不见的那个洞。
	var late_soft := {"id": "s", "name": "S", "cn": "s", "fx": "f",
		"params": {"repeat_factor": 0.5}, "proof": "score", "tier": 2, "tiers": [2, 3]}
	var early_hard := {"id": "h", "name": "H", "cn": "h", "fx": "f",
		"params": {"repeat_factor": 0.0}, "proof": "score", "tier": 3, "tiers": [1, 3]}
	# ⚠ fixed_tiers 要带上 1 和 2, 否则会先被「这一轮只有 1 张脸」拦下 ——
	# 那样这条断言就**为了错误的理由变绿**。所以下面连错误信息一起断言。
	var arc_err := DB.validate_faces({"faces": [late_soft, early_hard], "fixed_tiers": [1, 2],
		"families": {"repeat_factor": {"soft": "s", "hard": "h"}}})
	t.check(arc_err.contains("教学弧"),
		"hard 最早出现在 soft 之前被拒, 且是因为教学弧而不是别的规则(got: %s)" % arc_err)
