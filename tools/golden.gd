extends SceneTree

## 金样生成器(docs/design/mirror.md §6)—— Godot 侧算出「期望」, 写成 lua/golden/<族>.lua,
## Lua 镜像用 lua/check.lua 重放比对。**生成物手改无效**;改了 core/ 就重跑本脚本。
##   godot --headless --path . --script res://tools/golden.gd            # 全部五族
##   SYNC5_GOLDEN=rng,pattern godot --headless --path . --script res://tools/golden.gd
## ⚠ 浮点一律写成 H"<f64hex>"(IEEE 位串), 不写十进制 —— 两边 printf 的最后一位不可信。

const OUT_DIR := "res://lua/golden"

func _initialize() -> void:
	var only := OS.get_environment("SYNC5_GOLDEN")
	var fams := {
		"rng": Callable(self, "_fam_rng"),
		"pattern": Callable(self, "_fam_pattern"),
		"settle": Callable(self, "_fam_settle"),
		"fx": Callable(self, "_fam_fx"),
	}
	var n := 0
	for name in fams:
		if only != "" and not only.split(",").has(name):
			continue
		var body: String = fams[name].call()
		_write("%s/%s.lua" % [OUT_DIR, name], body)
		n += 1
	print("golden: wrote %d families" % n)
	quit(0)


func _write(path: String, body: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("golden: cannot write " + path)
		quit(1)
		return
	f.store_string("-- 由 tools/golden.gd 生成 —— 仪器输出, 手改无效(docs/design/mirror.md §6)\n")
	f.store_string(body)
	f.close()
	print("  wrote ", path, " (", body.length(), " chars)")


# ---------------------------------------------------------------- Lua 序列化

static func f64hex(x: float) -> String:
	var b := PackedFloat64Array([x]).to_byte_array()
	var s := ""
	for i in range(7, -1, -1):
		s += "%02x" % b[i]
	return s


static func state_hex(st: int) -> String:
	return "%08x%08x" % [(st >> 32) & 0xFFFFFFFF, st & 0xFFFFFFFF]


static func lstr(s: String) -> String:
	var out := "\""
	for ch in s:
		match ch:
			"\\": out += "\\\\"
			"\"": out += "\\\""
			"\n": out += "\\n"
			"\r": out += "\\r"
			"\t": out += "\\t"
			_: out += ch
	return out + "\""


## 任意 Variant → Lua 字面量。int → 十进制, float → H"hex", null → nil, Object → 走它的 to_golden()(若有)。
static func lua(v) -> String:
	match typeof(v):
		TYPE_NIL: return "nil"
		TYPE_BOOL: return "true" if v else "false"
		TYPE_INT: return "%d" % v
		TYPE_FLOAT: return "H\"%s\"" % f64hex(v)
		TYPE_STRING, TYPE_STRING_NAME: return lstr(String(v))
		TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			var parts: Array = []
			for e in v:
				parts.append(lua(e))
			return "{" + ",".join(parts) + "}"
		TYPE_DICTIONARY:
			var parts: Array = []
			for k in v:
				var ks: String
				if typeof(k) == TYPE_INT:
					ks = "[%d]" % k
				else:
					ks = "[%s]" % lstr(String(k))
				parts.append(ks + "=" + lua(v[k]))
			return "{" + ",".join(parts) + "}"
		TYPE_OBJECT:
			if v.has_method("to_golden"):
				return lua(v.to_golden())
			return lstr(str(v))
		_:
			return lstr(str(v))


# ---------------------------------------------------------------- rng 族

## 若干种子 × 混合调用序列;每一步的返回值都是期望。第 54 步记状态、第 104 步写回, 验 setter。
func _fam_rng() -> String:
	var seeds := [0, 1, -1, 2147483648, 4294967301, 700000, 9007199254740991, -123456789012, 90000, 41000,
		12345, 2026, 777, 31337, 65536, 4294967295, 8675309, 999999937, 3, 42]
	var cases: Array = []
	for s in seeds:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var ops: Array = []
		var saved := 0
		for k in range(200):
			match k % 5:
				0: ops.append(["i", rng.randi()])
				1: ops.append(["r", 0, k + 1, rng.randi_range(0, k + 1)])
				2: ops.append(["r", -7, 7, rng.randi_range(-7, 7)])
				3: ops.append(["f", rng.randf()])
				4:
					ops.append(["s", state_hex(rng.state)])
					if k == 54:
						saved = rng.state
					if k == 104:
						rng.state = saved
						ops.append(["S", state_hex(saved)])
		cases.append({"seed": s, "ops": ops})
	return "return " + lua(cases) + "\n"


# ---------------------------------------------------------------- pattern 族

static func cards_out(arr: Array) -> Array:
	var out: Array = []
	for c in arr:
		out.append([c.rank, c.suit])
	return out


static func labels(arr: Array) -> Array:
	var out: Array = []
	for c in arr:
		out.append(c.label())
	return out


## 1500 手:8 张(种子牌堆抽)+ 强制 0~5 张万能 + 16 种规则位组合(每三手带 false 键)。
## 期望 = evaluate_best 的全部字段 + best_score_of + 前五张的 score_five。
func _fam_pattern() -> String:
	var cases: Array = []
	var keys := ["shortcut", "fourfingers", "redtone", "blacktone"]
	for i in range(1500):
		var deck := Deck.new(41000 + i)
		var cards: Array = []
		for _j in range(8):
			cards.append(deck.draw())
		var w: int = 0 if i % 5 < 3 else (i % 3) + 1   # 四成带万能(全带时 Lua 5.5 重放要 30 s)
		if i % 97 == 0:
			w = 4
		if i % 193 == 0:
			w = 5
		for j in range(w):
			cards[j] = Card.new(Card.JOKER_RANK, 2 + (j % 2))
		var bits: int = i % 16
		var rules := {}
		for b in range(4):
			var on: bool = (bits >> b) & 1 == 1
			if on or i % 3 == 0:
				rules[keys[b]] = on
		var res: Dictionary = Pattern.evaluate_best(cards, rules)
		var five: Array = cards.slice(0, 5)
		cases.append({
			"cards": cards_out(cards), "rules": rules,
			"kind": int(res["kind"]), "name": String(res["name"]), "chips": int(res["chips"]),
			"pmult": int(res["pmult"]), "rank_sum": int(res["rank_sum"]), "score": int(res["score"]),
			"coins": int(res["coins"]), "resolved": labels(res["resolved"]),
			"best": Pattern.best_score_of(cards, rules),
			"five": Pattern.score_five(five, rules),
			"five_kind": int(Pattern.evaluate_best(five, rules)["kind"]),
		})
	return "return " + lua(cases) + "\n"


# ---------------------------------------------------------------- 共用:随机上下文

static func slots_out(slots: Array) -> Array:
	var out: Array = []
	for j in slots:
		if j == null:
			out.append(false)
		else:
			out.append({"id": j.id, "state": j.state.duplicate(true)})
	return out


static func popups_out(popups: Array) -> Array:
	var out: Array = []
	for p in popups:
		out.append([int(p["slot"]), String(p["text"])])
	return out


static func outcome_out(o: Dictionary) -> Dictionary:
	return {
		"score": int(o["score"]), "coins": int(o["coins"]), "base": int(o["base"]),
		"mult": float(o["mult"]), "bonus": int(o.get("bonus", 0)),
		"pattern_mult": float(o.get("pattern_mult", 1.0)), "joker_mult": float(o.get("joker_mult", 1.0)),
		"bonus_pct": float(o.get("bonus_pct", 0.0)), "target_hit": bool(o.get("target_hit", false)),
		"face_bit": bool(o.get("face_bit", false)), "popups": popups_out(o["popups"]),
	}


## 随机的一组槽:n 张, 0 号只放 target, 1..3 只放 support;计数器随机初值。
static func rand_slots(rng: RandomNumberGenerator, n: int, force_id: String = "") -> Array:
	var targets: Array = []
	var supports: Array = []
	for e in DB.jokers():
		if String(e["kind"]) == "target":
			targets.append(String(e["id"]))
		else:
			supports.append(String(e["id"]))
	var slots: Array = [null, null, null, null]
	var forced: Joker = null
	if force_id != "":
		forced = Joker.by_id(force_id)
	if forced != null and forced.kind == "target":
		slots[0] = forced
	elif n > 0 and rng.randi_range(0, 3) > 0:
		slots[0] = Joker.by_id(targets[rng.randi_range(0, targets.size() - 1)])
	var k := 1
	if forced != null and forced.kind != "target":
		slots[1] = forced
		k = 2
	while k <= 3 and k <= n:
		var sid: String = supports[rng.randi_range(0, supports.size() - 1)]
		var dup := false
		for j in slots:
			if j != null and j.id == sid:
				dup = true
		if not dup:
			slots[k] = Joker.by_id(sid)
		k += 1
	for j in slots:
		if j != null:
			# 按 counters 表(不是 state):没 init 的计数器(贝斯线的 n)在 state 里本来没有键。键名排序 = 两侧同序。
			var names: Array = j._counters.keys()
			names.sort()
			for cname in names:
				j.state[String(cname)] = float(rng.randi_range(0, 12))
	return slots


static func rand_cache(rng: RandomNumberGenerator, deck: Deck, i: int) -> Array:
	var cache: Array = []
	match i % 6:
		1:   # 三条
			var r := rng.randi_range(2, 14)
			for s in range(3):
				cache.append(Card.new(r, s))
		2:   # 顺
			var lo := rng.randi_range(2, 12)
			for s in range(3):
				cache.append(Card.new(lo + s, rng.randi_range(0, 3)))
		3:   # 全人头 / 同色
			for s in range(3):
				cache.append(Card.new(rng.randi_range(11, 13), 1 + (s % 2)))
		4:   # 同花
			var su := rng.randi_range(0, 3)
			for s in range(3):
				cache.append(Card.new(rng.randi_range(2, 14), su))
		_:
			for s in range(3):
				cache.append(deck.draw())
	if i % 11 == 0:
		cache[0] = Card.new(Card.JOKER_RANK, 2)
	return cache


static func rand_extra(rng: RandomNumberGenerator, deck: Deck, res: Dictionary, slots: Array, i: int) -> Dictionary:
	var faces: Array = SectionMod.pooled_ids()
	var mod := ""
	if i % 4 != 0:
		mod = String(faces[rng.randi_range(0, faces.size() - 1)])
	var section := rng.randi_range(0, 3)
	var kind: int = int(res.get("kind", -1))
	var prev_choices := [-99, kind, rng.randi_range(0, 9)]
	var lucks: Array = []
	for _k in range(rng.randi_range(0, 3)):
		lucks.append(float(rng.randi_range(0, 9999)) / 10000.0)
	var boosts: Array = []
	if i % 3 == 0:
		var bpool: Array = []
		for e in DB.consumables():
			if e.has("boost"):
				bpool.append(e["boost"])
		for _b in range(rng.randi_range(1, 2)):
			boosts.append((bpool[rng.randi_range(0, bpool.size() - 1)] as Dictionary).duplicate(true))
	var cache := rand_cache(rng, deck, i)
	var crs := 0
	for c in cache:
		crs += c.rank
	return {
		"prev_kind": prev_choices[rng.randi_range(0, 2)],
		"prev_target_hit": rng.randi_range(0, 1) == 1,
		"phrase_boosts": boosts,
		"rolled_suit": rng.randi_range(-1, 3),
		"callout_unsolved": rng.randi_range(0, 2) == 0,
		"luck_rolls": lucks,
		"odds_mult": Joker.slots_odds_mult(slots),
		"cache_rank_sum": crs if rng.randi_range(0, 1) == 1 else 0,
		"acted_late": rng.randi_range(0, 1) == 1,
		"discards": rng.randi_range(0, 3),
		"coins": rng.randi_range(0, 24),
		"phrase_idx": rng.randi_range(0, 5),
		"cache_cards": cache,
		"early_finish": rng.randi_range(0, 1) == 1,
		"acted_final": rng.randi_range(0, 2) == 0,
		"seconds_left": float(rng.randi_range(0, 80)) / 10.0,
		"early_discards": rng.randi_range(0, 1) == 1,
		"section_idx": section,
		"swaps": rng.randi_range(0, 3),
		"discard_batch_max": rng.randi_range(0, 8),
		"faces_discarded": rng.randi_range(0, 3),
		"swapped_scoring": rng.randi_range(0, 3),
		"section_score": rng.randi_range(0, 4000),
		"section_target": int(GameConfig.SECTION_TARGETS[section]) if rng.randi_range(0, 5) > 0 else 0,
		"mod": mod,
		"first_kind": prev_choices[rng.randi_range(0, 2)],
		"request_met": rng.randi_range(0, 2) > 0,
		"patch_restored": rng.randi_range(0, 3) == 0,
	}


static func extra_out(x: Dictionary) -> Dictionary:
	var o := x.duplicate(true)
	o["cache_cards"] = cards_out(x["cache_cards"])
	return o


static func rand_result(rng: RandomNumberGenerator, deck: Deck, i: int) -> Array:
	var cards: Array = []
	var n: int = 8 if i % 9 == 0 else 5
	for _j in range(n):
		cards.append(deck.draw())
	if i % 7 == 0:
		cards[0] = Card.new(Card.JOKER_RANK, 2)
	if i % 13 == 0:   # 凑对/三条, 让牌型谓词多触发
		cards[1] = Card.new(cards[0].rank if not cards[0].is_wild() else 9, (cards[0].suit + 1) % 4)
	var res: Dictionary = Pattern.evaluate_best(cards, {})
	var hidden := rng.randi_range(0, 2) if i % 5 == 0 else 0
	res["hidden_scoring"] = hidden
	return [cards, res, hidden]


# ---------------------------------------------------------------- settle 族

func _fam_settle() -> String:
	var cases: Array = []
	for i in range(2000):
		var rng := RandomNumberGenerator.new()
		rng.seed = 52000 + i
		var deck := Deck.new(52000 + i)
		var rr := rand_result(rng, deck, i)
		var cards: Array = rr[0]
		var res: Dictionary = rr[1]
		var slots := rand_slots(rng, i % 5)
		var extra := rand_extra(rng, deck, res, slots, i)
		var extra_in := extra_out(extra)      # 结算会消耗 luck_rolls, 先存输入
		var outcome := Settle.run(res, slots, extra)
		cases.append({
			"cards": cards_out(cards), "hidden": int(rr[2]), "slots": slots_out(slots),
			"extra": extra_in, "out": outcome_out(outcome),
		})
	return "return " + lua(cases) + "\n"


# ---------------------------------------------------------------- fx 族(每张卡的电池 + 钩子 + 统计 + 经济 + 脸 + 消耗牌 + 增益 + 配置)

static func state_out(st: Dictionary) -> Dictionary:
	return st.duplicate(true)


func _fam_fx() -> String:
	var g := {}
	# ① 每张小丑牌 × 24 个上下文(它在自己的槽位上;support 时 0 号放随机 target)
	var per_joker: Array = []
	var jid := 0
	for e in DB.jokers():
		var id := String(e["id"])
		for k in range(24):
			var i := jid * 24 + k
			var rng := RandomNumberGenerator.new()
			rng.seed = 61000 + i
			var deck := Deck.new(61000 + i)
			var rr := rand_result(rng, deck, i)
			var slots := rand_slots(rng, 1 + (k % 3), id)
			var extra := rand_extra(rng, deck, rr[1], slots, i)
			var extra_in := extra_out(extra)
			var outcome := Settle.run(rr[1], slots, extra)
			per_joker.append({"cards": cards_out(rr[0]), "hidden": int(rr[2]), "slots": slots_out(slots),
				"extra": extra_in, "out": outcome_out(outcome)})
		jid += 1
	g["battery"] = per_joker
	# ② 钩子序列 + 元数据
	var hooks: Array = []
	for e in DB.jokers():
		var j := Joker.by_id(String(e["id"]))
		var trail: Array = [state_out(j.state)]
		j.on_discard(2); trail.append(state_out(j.state))
		j.on_shop_event("reroll"); trail.append(state_out(j.state))
		j.on_shop_event("buy"); trail.append(state_out(j.state))
		j.on_shop_event("target_swap"); trail.append(state_out(j.state))
		j.on_phrase_end({"early_finish": true}); trail.append(state_out(j.state))
		j.on_phrase_end({"early_finish": false}); trail.append(state_out(j.state))
		j.on_discard(0); trail.append(state_out(j.state))
		var life1 := j.tick_section_life(); trail.append(state_out(j.state))
		var life2 := j.tick_section_life(); trail.append(state_out(j.state))
		var d2 := Deck.new(77)
		j.on_acquire(d2)
		hooks.append({"id": j.id, "trail": trail, "life": [life1, life2],
			"trial_free": j.trial_free(), "rolls": j.chance_rolls_needed(), "swap_bonus": j.swap_bonus_pct(),
			"rule": j.is_rule_card(), "has_fx": j.has_effects(), "shelf_mult": j.shelf_target_mult(),
			"shelf_guar": j.shelf_target_guaranteed(), "cn": j.cn_name, "kind": j.kind, "rarity": j.rarity,
			"deck_total": d2.total(), "deck_rules": d2.rules.duplicate(true), "deck_trim": d2.trim_low,
			"deck_wildx": d2.wild_extra.duplicate(true), "clone_state": state_out(j.clone().state)})
	g["hooks"] = hooks
	# ③ 槽统计 + 经济
	var statics: Array = []
	for s in range(40):
		var rng := RandomNumberGenerator.new()
		rng.seed = 70000 + s
		var slots := rand_slots(rng, s % 5)
		var pool := Joker.pool()
		var rm := {} if s % 2 == 0 else {"common": 1.5, "uncommon": 0.7, "rare": 2.0}
		var boost := {} if s % 3 != 0 else {"twin": 3.0, "stair": 0.5}
		var tm: float = 1.0 if s % 4 != 0 else 3.0
		var picked: Array = Economy.weighted_pick(pool, 3, tm, rng, rm, boost)
		var pids: Array = []
		for pj in picked:
			pids.append(pj.id)
		var prices: Array = []
		var weights: Array = []
		for pj in pool:
			prices.append([pj.id, Economy.joker_price(pj, false), Economy.joker_price(pj, true),
				Economy.sell_value(pj), Economy.shelf_price(pj, slots)])
			weights.append(Economy.shelf_weight(pj, tm, rm))
		statics.append({"slots": slots_out(slots), "shelf_size": Joker.slots_shelf_size(slots, s % 3),
			"buy_limit": Joker.slots_buy_limit(slots), "price_delta": Joker.slots_price_delta(slots),
			"coin_cap": Joker.slots_coin_cap(slots), "odds": Joker.slots_odds_mult(slots),
			"cache_scoring": Joker.slots_cache_scoring(slots), "target_mult": Joker.slots_target_mult(slots),
			"copy_cons": Joker.slots_copy_consumable(slots), "free_support": Joker.first_free_support(slots),
			"room_t": Joker.has_room_for(slots, "target"), "room_s": Joker.has_room_for(slots, "support"),
			"guar": Joker.slots_guarantee_target(slots), "loan": Joker.slots_loan(slots),
			"rule_guar": Joker.slots_rule_guaranteed(slots),
			"picked": pids, "tm": tm, "rm": rm, "boost": boost, "prices": prices, "weights": weights,
			"grant": [Economy.grant(3, 4, slots), Economy.grant(20, 4, slots), Economy.grant(20, -2, slots)],
			"cap_held": Economy.cap_held(30, slots), "reroll": [Economy.reroll_cost(0), Economy.reroll_cost(3), Economy.reroll_cost(1, -2), Economy.reroll_cost(0, -9)],
			"discard_cost": [Economy.discard_cost(0), Economy.discard_cost(3)]})
	g["statics"] = statics
	# ④ 脸:参数电池 + 掷脸
	var faces: Array = []
	for m in SectionMod.roster():
		var id: String = m.id
		var pf: Array = []
		var tp: Array = []
		for idx in range(6):
			pf.append(SectionMod.phase_factor(id, idx))
			tp.append(SectionMod.time_penalty_at(id, idx))
		faces.append({"id": id, "cn": m.cn_name, "params": m.params.duplicate(true),
			"axes": SectionMod.attack_axes(id), "settle": SectionMod.affects_settle(id),
			"tiers": SectionMod.tiers_of(id), "tier": SectionMod.tier_of(id), "base": SectionMod.base_of(id),
			"combo": SectionMod.combo_of(id), "proof": SectionMod.proof(id), "tape": SectionMod.tape_required(id),
			"unlocked": [SectionMod.unlocked_at(id, -1), SectionMod.unlocked_at(id, 1), SectionMod.unlocked_at(id, 9)],
			"v": [SectionMod.time_penalty(id), SectionMod.phrase_toll(id), SectionMod.target_power(id),
				SectionMod.repeat_factor(id), SectionMod.zero_discard_factor(id), SectionMod.cache_evict(id),
				SectionMod.cache_cap(id), SectionMod.lock_first(id), SectionMod.target_mult(id),
				SectionMod.hide_refill(id), SectionMod.hide_faces(id), SectionMod.discard_lock_last(id),
				SectionMod.swap_lock_last(id), SectionMod.discard_action_limit(id), SectionMod.swap_action_limit(id),
				SectionMod.action_limit(id), SectionMod.discard_cards_max(id), SectionMod.action_cards_max(id),
				SectionMod.cache_blocks_red(id), SectionMod.refill_rank_min(id), SectionMod.refill_rank_max(id),
				SectionMod.cache_lock_phrases(id), SectionMod.seals_lowest_start(id), SectionMod.seals_oldest_cache(id),
				SectionMod.seals_random_start(id), SectionMod.seals_random_cache(id), SectionMod.hide_random(id),
				SectionMod.hide_suits(id), SectionMod.hide_ranks(id), SectionMod.roll_chance(id),
				SectionMod.roll_cache_extra(id), SectionMod.rolls_suit(id), SectionMod.suit_half(id),
				SectionMod.callout_factor(id), SectionMod.rolls_kind(id), SectionMod.required_kinds(id),
				SectionMod.variety_penalty(id), SectionMod.restores_with_initial_cache(id),
				SectionMod.section_discard_budget(id), SectionMod.exclusive_action_tracks(id),
				SectionMod.request_factor(id), SectionMod.joker_power(id), SectionMod.bonus_disabled(id),
				SectionMod.discard_open(id, 2.0), SectionMod.swap_open(id, 2.0), SectionMod.discard_open(id, 1.5)],
			"pf": pf, "tp": tp})
	var pools: Array = []
	for sidx in range(GameConfig.SECTIONS_PER_RUN):
		pools.append(SectionMod.pool_for(sidx))
	var rolls: Array = []
	for s in range(120):
		var rng := RandomNumberGenerator.new()
		rng.seed = 80000 + s
		var ri: int = [-1, 1, 3, 5, 9][s % 5]
		var out := SectionMod.roll_run(rng, ri)
		var arr: Array = []
		for w in GameConfig.WALL_SECTIONS:
			arr.append(String(out.get(int(w), "")))
		rolls.append({"seed": 80000 + s, "run_index": ri, "faces": arr, "after": rng.randi(),
			"single": SectionMod.roll(s % 4, rng, [String(arr[0])], ri)})
	g["faces"] = {"list": faces, "pools": pools, "pooled": SectionMod.pooled_ids(), "axes": SectionMod.axis_ids(),
		"fixed": [SectionMod.tier_is_fixed(1), SectionMod.tier_is_fixed(4)], "rolls": rolls}
	# ⑤ 消耗牌
	var cons: Array = []
	for e in DB.consumables():
		var c := Consumable.new(e)
		var due: Array = []
		for beat in range(1, 7):
			for q in range(0, 3):
				due.append(c.due_on(beat, q))
		cons.append({"id": c.id, "instant": c.is_instant(), "rule": c.is_rule_card(), "label": c.fire_label(),
			"price": c.price, "due": due, "name": c.display_name(), "clone_q": c.clone().queued_beats})
	var shelves: Array = []
	for s in range(60):
		var rng := RandomNumberGenerator.new()
		rng.seed = 90000 + s
		var held := {}
		if s % 3 == 1:
			held["superwild"] = true
		if s % 3 == 2:
			held["doublebill"] = true
			held["opener"] = true
		var rows: Array = Consumable.roll_shelf(held, s % 2 == 0, 2 + (s % 2),
			func(n): return rng.randi_range(0, n - 1))
		var ids: Array = []
		for r in rows:
			ids.append("" if r == null else String(r["id"]))
		shelves.append({"seed": 90000 + s, "held": held, "rule_first": s % 2 == 0, "n": 2 + (s % 2), "ids": ids})
	g["consumables"] = {"list": cons, "shelves": shelves}
	# ⑥ 增益 + 配置
	var boons: Array = []
	for s in range(30):
		var rng := RandomNumberGenerator.new()
		rng.seed = 95000 + s
		boons.append(BlindBoon.roll(rng))
	var bparams: Array = []
	for bid in BlindBoon.ids():
		bparams.append([bid, BlindBoon.score_replay_factor(bid), BlindBoon.spotlight_cards(bid),
			BlindBoon.previous_raw_factor(bid), BlindBoon.ghost_first_discard(bid), BlindBoon.by_id(bid).cn_name])
	g["boons"] = {"ids": BlindBoon.ids(), "rolls": boons, "params": bparams}
	var cfg := {
		"pps": GameConfig.PHRASES_PER_SECTION, "shop": GameConfig.PHRASES_PER_SHOP, "sps": GameConfig.SHOPS_PER_SECTION,
		"spg": GameConfig.SECTIONS_PER_GIG, "gpr": GameConfig.GIGS_PER_RUN, "spr": GameConfig.SECTIONS_PER_RUN,
		"walls": GameConfig.WALL_SECTIONS, "targets": GameConfig.SECTION_TARGETS, "avg": GameConfig.avg_beat_target(),
		"hand": GameConfig.HAND_SIZE, "cache": GameConfig.CACHE_CAP, "bd": GameConfig.BEAT_DISCARDS,
		"bb": GameConfig.BEAT_DISCARD_BATCH, "bs": GameConfig.BEAT_SWAPS, "blind": GameConfig.BLIND_SAMPLES,
		"coins": GameConfig.STARTING_COINS, "dc": GameConfig.DISCARD_COST, "wage": GameConfig.SECTION_CLEAR_REWARD,
		"rb": GameConfig.DRAFT_REROLL_BASE, "rs": GameConfig.DRAFT_REROLL_STEP,
		"s1": [GameConfig.S1_FACE_MIN_RUN, GameConfig.S1_EASY_CHANCE], "windows": [GameConfig.LATE_ACT_WINDOW,
			GameConfig.FINAL_ACT_WINDOW, GameConfig.EARLY_DISCARD_WINDOW, GameConfig.EARLY_FINISH_LEFT, GameConfig.RESOLVE_FEEDBACK],
		"per_section": [], "budget": [],
	}
	for sidx in range(GameConfig.SECTIONS_PER_RUN):
		var d := GameConfig.phrase_duration(sidx)
		cfg["per_section"].append([d, GameConfig.warning_time(d), GameConfig.lock_time(d), GameConfig.is_wall(sidx),
			GameConfig.gig_of(sidx), GameConfig.blind_name(sidx), GameConfig.gig_name(sidx), GameConfig.section_target(sidx)])
		for dur in [8.0, 6.0, 4.0]:
			cfg["budget"].append([sidx, dur, GameConfig.beat_discards(dur, sidx), GameConfig.discard_batch(dur, sidx)])
	g["config"] = cfg
	return "return " + lua(g) + "\n"
