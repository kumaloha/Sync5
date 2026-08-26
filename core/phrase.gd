class_name Phrase
extends RefCounted

## Engine-agnostic logic for a single Phrase under the 2026-08 discard-refill
## rules: no candidate card. The hand always holds exactly HAND_SIZE cards;
## discarding selected cards (from hand or cache) costs DISCARD_COST per card
## and each discarded card is replaced in place immediately from the deck.
## The cache array is owned by the run (persists across phrases) and is only
## referenced here. Contains NO clock — the view drives timing and calls
## lock_and_settle() at LOCK_TIME.

var deck: Deck
var hand: Array[Card] = []
var cache: Array               # Array[Card], external run-owned reference
var coins: int
var discards_used: int = 0     # cards discarded this phrase (analytics)
# ---- 2026-08-13 引擎波次·子波1 的动作内容记账(设计规格 = docs/design/jokers_atlas.md) ----
var discard_batch_max: int = 0   # 单批弃牌张数峰值(断舍离 declutter)
var faces_discarded: int = 0     # 本拍弃掉的人头牌数(让位 stageexit)
var swapped_in: Dictionary = {}  # 本拍经交换进入手牌的 Card 集合(串场 segue;对象身份)
var _initial_hand: Dictionary = {}   # 开拍时手牌快照 —— 试探性换回(bot)不算「换入」
var discard_actions_used: int = 0
var swap_actions_used: int = 0
var discard_cards_used: int = 0  # 本拍已弃张数(一口气/打烊按张限:2026-08-25 张数重铸)
var action_cards_used: int = 0   # 本拍弃+换合计张数(限流按张限;换一次记一张)
var action_count: int = 0
var action_track := ""         # "discard" | "swap" once switchtrack commits
## 本拍在段内的序号(0 起), Beat.begin 从 run.phrase_in_section 灌入;-1 = 无段上下文
## (kit 之类的单拍探针)。倒计时(time_curve)与渐强(phase_factors)按它取曲线值。
var phrase_idx: int = -1
## 掷类脸的段级明掷结果(Beat.begin 从 run.mod_roll 灌入;轮盘的容量加扣读它)。
var mod_roll: Dictionary = {}
## 合奏(2026-08-25):缓存也进结算牌集(Beat.begin 按持仓灌入)。
var cache_scoring := false
## 回收(2026-08-25):本拍直弃的缓存牌点数之和(奖励分按它折算)。
var cache_discard_rank_sum := 0
## Remaining discard-card allowance supplied by Run for Ration; -1 = unlimited.
var discard_budget: int = -1
var locked: bool = false
var result: Dictionary = {}

## This section's Boss face id ("" = none). A plain field rather than a ctor
## argument so the three call sites (view orchestrator / sim / curve) opt in
## with one line and every existing `Phrase.new(...)` keeps working.
## ⚠ Set it BEFORE start() — the cache-capacity face is applied there.
var mod: String = ""
var boon: String = ""

## Cards the player cannot see this phrase (the hiding faces). Keyed by the
## Card OBJECT, never by index: swaps, sorts and in-place refills all move
## indices around, and an index-keyed set would silently point at the wrong
## card the moment the player sorts their hand.
##
## ⚠ A hidden card still scores normally — hiding takes away INFORMATION, not
## value (Balatro's own definition). And it lasts exactly one phrase: 用户
## 2026-08-07 拍板「盖上,这轮结束才能看到,结算的时候翻牌」, so `start()` clears
## it and anything kept in the cache is plainly visible next phrase.
var hidden: Dictionary = {}
## Cache ages are run-owned and shared across Phrase instances. Object keys
## survive sorting and slot changes, so "oldest" is not guessed from an index.
var cache_meta: Dictionary = {"ages": {}, "next": 0}
var initial_cache: Array = []
var sealed_hand_card: Card = null
var sealed_cache_card: Card = null
var locked_cache_cards: Dictionary = {}
var marked_cache_card: Card = null
var spotlight_card: Card = null
var ghost_cards: Array[Card] = []
var request_goal := ""
var request_prev_kind := -99
var request_met := true


func _init(deck_ref: Deck, cache_ref: Array, starting_coins: int) -> void:
	deck = deck_ref
	cache = cache_ref
	coins = starting_coins

## Deal the hand and bring the cache to this face's capacity. The cache is
## ALWAYS full: dealt full at run start, topped up whenever a slot would go
## empty. Trim runs BEFORE top-up so entering a smallstage section with a
## carried-over 3-card cache correctly drops to 2.
func start() -> void:
	hand.clear()
	for i in range(GameConfig.HAND_SIZE):
		var c := deck.draw()
		if c != null:
			hand.append(c)
	var cap := SectionMod.cache_cap(mod)
	if bool(mod_roll.get("worse", false)):
		# 轮盘(2026-08-25):开局掷出「封 2 格」时在基础扣格上再扣。
		cap = maxi(0, cap - SectionMod.roll_cache_extra(mod))
	while cache.size() > cap:
		deck.discard(cache.pop_back())
	while cache.size() < cap:
		var cc := deck.draw()
		if cc == null:
			break
		cache.append(cc)
	discards_used = 0
	discard_batch_max = 0
	faces_discarded = 0
	swapped_in.clear()
	_initial_hand.clear()
	for hc in hand:
		if hc != null:
			_initial_hand[hc] = true
	discard_actions_used = 0
	swap_actions_used = 0
	discard_cards_used = 0
	action_cards_used = 0
	cache_discard_rank_sum = 0
	action_count = 0
	action_track = ""
	locked = false
	result = {}
	request_met = request_goal == ""
	locked_cache_cards.clear()
	marked_cache_card = null
	spotlight_card = null
	ghost_cards.clear()
	_sync_cache_ages()
	if SectionMod.cache_evict(mod) == 1 and not cache.is_empty():
		marked_cache_card = cache[deck.pick_index(cache.size())]
	initial_cache = cache.duplicate()
	sealed_hand_card = _pick_sealed_hand()
	sealed_cache_card = _pick_sealed_cache()
	if BlindBoon.spotlight_cards(boon) > 0:
		spotlight_card = deck.draw()
	# fresh phrase, fresh sight: last phrase's cards were revealed at its settle
	hidden.clear()
	if SectionMod.hide_faces(mod):
		for c in hand:
			if c != null and c.rank >= 11 and c.rank <= 13:
				hidden[c] = true
		for c in cache:
			if c != null and c.rank >= 11 and c.rank <= 13:
				hidden[c] = true
	# 暗场(2026-08-25):每拍随机盖 N 张手牌 —— 不递增不全盲(「没抽到对策等于失败」
	# 违反无必解, 渐暗因此被砍)。抽签走 deck.pick_index, 与随机封同一条 RNG 纪律。
	var extra_hide := SectionMod.hide_random(mod)
	if extra_hide > 0 and not hand.is_empty():
		var pick_pool: Array = range(hand.size())
		for _k in range(mini(extra_hide, pick_pool.size())):
			var j := deck.pick_index(pick_pool.size())
			hidden[hand[pick_pool[j]]] = true
			pick_pool.remove_at(j)

## 洗牌(2026-08-26 超级百搭配套的付费动作):整手回弃牌堆 → 弃牌堆洗回抽牌堆
## → 重发 HAND_SIZE 张 —— 堆里的 JOKER 全部回到可抽态, 这是「付费钓卡」的实体。
## 只在牌堆里有万能时开放(否则它只是免费全弃的付费重复, 纯坑)。缓存不动。
## 封条随旧手牌离场(花金币洗掉封条 = versus.md「构筑相关成本」的合法解除);
## 暗场/蒙面按脸的语义对新手牌**重掷**(否则 3◆ 把脸洗成空气)。
func can_reshuffle() -> bool:
	if locked or coins < Economy.reshuffle_cost():
		return false
	return not deck.wild_extra.is_empty()


func reshuffle() -> void:
	if not can_reshuffle():
		return
	coins -= Economy.reshuffle_cost()
	for c in hand:
		if c != null:
			hidden.erase(c)
			deck.discard(c)
	hand.clear()
	deck.recycle()
	for i in range(GameConfig.HAND_SIZE):
		var c := deck.draw()
		if c != null:
			hand.append(c)
	if sealed_hand_card != null and not hand.has(sealed_hand_card):
		sealed_hand_card = null
	if SectionMod.hide_faces(mod):
		for c in hand:
			if c != null and c.rank >= 11 and c.rank <= 13:
				hidden[c] = true
	var extra_hide := SectionMod.hide_random(mod)
	if extra_hide > 0 and not hand.is_empty():
		var pick_pool: Array = range(hand.size())
		for _k in range(mini(extra_hide, pick_pool.size())):
			var j := deck.pick_index(pick_pool.size())
			hidden[hand[pick_pool[j]]] = true
			pick_pool.remove_at(j)


func can_discard(count: int) -> bool:
	if locked or count <= 0 or coins < Economy.discard_cost(count):
		return false
	var limit := SectionMod.discard_action_limit(mod)
	if limit >= 0 and discard_actions_used >= limit:
		return false
	var shared := SectionMod.action_limit(mod)
	if shared >= 0 and action_count >= shared:
		return false
	var cards_cap := SectionMod.discard_cards_max(mod)
	if cards_cap >= 0 and discard_cards_used + count > cards_cap:
		return false
	var combo_cap := SectionMod.action_cards_max(mod)
	if combo_cap >= 0 and action_cards_used + count > combo_cap:
		return false
	if SectionMod.exclusive_action_tracks(mod) and action_track == "swap":
		return false
	if discard_budget >= 0 and discards_used + count > discard_budget:
		return false
	return true


## Selection-aware validation lives before any animation/Tape feedback. A
## count-only check cannot see Hand Seal and used to let the view animate a
## discard which core correctly rejected.
func can_discard_selected(hand_indices: Array, cache_indices: Array = []) -> bool:
	if not can_discard(hand_indices.size() + cache_indices.size()):
		return false
	var seen_hand := {}
	for i in hand_indices:
		if i < 0 or i >= hand.size() or seen_hand.has(i):
			return false
		seen_hand[i] = true
		if hand[i] == sealed_hand_card:
			return false
	var seen_cache := {}
	for i in cache_indices:
		if i < 0 or i >= cache.size() or seen_cache.has(i):
			return false
		seen_cache[i] = true
		if cache[i] == sealed_hand_card:
			return false
	return true

## Discard selected cards from hand and/or cache in one paid action.
## Every discarded card is replaced in place immediately. Returns false (and
## does nothing) if locked, selection empty, coins short, or an index invalid.
func discard_selected(hand_indices: Array, cache_indices: Array = []) -> bool:
	var total: int = hand_indices.size() + cache_indices.size()
	if not can_discard_selected(hand_indices, cache_indices):
		return false
	coins -= Economy.discard_cost(total)
	discards_used += total
	discard_batch_max = maxi(discard_batch_max, total)
	for fi in hand_indices:
		if hand[fi] != null and hand[fi].rank >= 11 and hand[fi].rank <= 13:
			faces_discarded += 1
	for fi in cache_indices:
		if cache[fi] != null and cache[fi].rank >= 11 and cache[fi].rank <= 13:
			faces_discarded += 1
	# ⚠ A discarded card must leave `hidden` too — the dictionary is keyed by
	# object, and the deck recycles those same Card objects on reshuffle, so a
	# stale key would make a future draw arrive mysteriously face down.
	var blind_refill := SectionMod.hide_refill(mod)
	# facedown 的补牌一致性(2026-08-25 排查「非人头也盖」时抓到的反向洞):
	# 卡面写「J/Q/K 盖面发牌」, 补牌也是发牌 —— 此前补进来的人头明着, 与开局发的规则不一致。
	var face_refill := SectionMod.hide_faces(mod)
	if BlindBoon.ghost_first_discard(boon) and ghost_cards.is_empty() and not hand_indices.is_empty():
		for first_i in hand_indices:
			var first_card: Card = hand[int(first_i)]
			ghost_cards.append(Card.new(first_card.rank, first_card.suit))
	for i in hand_indices:
		hidden.erase(hand[i])
		deck.discard(hand[i])
		hand[i] = _draw_refill()
		if hand[i] != null and (blind_refill \
				or (face_refill and hand[i].rank >= 11 and hand[i].rank <= 13)):
			hidden[hand[i]] = true
	for i in cache_indices:
		var old_cache: Card = cache[i]
		cache_discard_rank_sum += old_cache.rank   # 回收:献祭按面值记账
		hidden.erase(old_cache)
		_forget_cache_age(old_cache)
		deck.discard(old_cache)
		cache[i] = _draw_refill()
		_remember_cache_age(cache[i])
		if cache[i] != null and (blind_refill \
				or (face_refill and cache[i].rank >= 11 and cache[i].rank <= 13)):
			hidden[cache[i]] = true
	discard_actions_used += 1
	discard_cards_used += total
	action_cards_used += total
	action_count += 1
	if action_track == "":
		action_track = "discard"
	return true


## Swap a hand card with a cache card (free; time is the cost).
##
## `probe = true` = **假想交换**:牌真的对调(调用方要拿它算 EV), 但**不计入动作数**。
## ⚠ 存在的理由:规则 bot 每拍要试探 15 次(换过去→算→换回来), 每次都是真调用 ——
## 于是「本拍零交换」这个条件在模型里**永不成立**(静物 stilllife 的 kit 触发率 0%)。
## 这与 `Deck.peek_many` 那条注释是同一个病:**求解的过程不许污染被求解的对象**。
## 留下来的那一次由调用方调 `commit_probe_swap()` 补记 —— 显式, 因为「玩家真的动了手」
## 和「模型算了一下」必须可区分。
func swap_with_cache(hand_index: int, cache_index: int, probe: bool = false) -> bool:
	if not can_swap_action() or hand_index < 0 or hand_index >= hand.size():
		return false
	if cache_index < 0 or cache_index >= cache.size():
		return false
	if SectionMod.cache_blocks_red(mod) and hand[hand_index].is_red():
		return false
	if cache[cache_index] == sealed_cache_card or locked_cache_cards.has(cache[cache_index]):
		return false
	var tmp: Card = hand[hand_index]
	hand[hand_index] = cache[cache_index]
	cache[cache_index] = tmp
	# 串场的记账:换入的进集合、换出的出集合 —— bot 的试探换回于是自然抵消,
	# 计数时再叠一层「不在初始手牌」的过滤(见 swapped_scoring_count)。
	swapped_in[hand[hand_index]] = true
	swapped_in.erase(tmp)
	_forget_cache_age(hand[hand_index])
	_remember_cache_age(tmp)
	if SectionMod.cache_lock_phrases(mod) > 0:
		locked_cache_cards[tmp] = true
	if not probe:
		commit_probe_swap()
	return true


## 把一次交换记成玩家动作(计数 + 动作轨)。`swap_with_cache` 正常路径自动调它;
## 试探路径(probe)由调用方在**决定留下**时显式调。
func commit_probe_swap() -> void:
	swap_actions_used += 1
	action_cards_used += 1
	action_count += 1
	if action_track == "":
		action_track = "swap"


## 参与成牌的「换入牌」张数(串场 segue)。换入 = 经交换进手 **且** 不是开拍原手牌
## —— 后一半挡掉 bot 试探性换回把原牌记成换入的伪影。
func swapped_scoring_count(resolved: Array) -> int:
	var n := 0
	for c in resolved:
		if c != null and swapped_in.has(c) and not _initial_hand.has(c):
			n += 1
	return n


func can_swap_action() -> bool:
	if locked or hand.is_empty() or cache.is_empty():
		return false
	var swap_limit := SectionMod.swap_action_limit(mod)
	if swap_limit >= 0 and swap_actions_used >= swap_limit:
		return false
	var shared := SectionMod.action_limit(mod)
	if shared >= 0 and action_count >= shared:
		return false
	var combo_cap := SectionMod.action_cards_max(mod)
	if combo_cap >= 0 and action_cards_used + 1 > combo_cap:
		return false
	if SectionMod.exclusive_action_tracks(mod) and action_track == "discard":
		return false
	return true


func discard_blocked_hand() -> Dictionary:
	var out := {}
	if sealed_hand_card != null:
		out[sealed_hand_card] = true
	return out


func swap_blocked_hand() -> Dictionary:
	var out := {}
	if SectionMod.cache_blocks_red(mod):
		for card in hand:
			if card.is_red():
				out[card] = true
	return out


func swap_blocked_cache() -> Dictionary:
	var out: Dictionary = locked_cache_cards.duplicate()
	if sealed_cache_card != null:
		out[sealed_cache_card] = true
	return out


func discard_blocked_cache() -> Dictionary:
	var out := {}
	if sealed_hand_card != null:
		out[sealed_hand_card] = true
	return out


func _draw_refill() -> Card:
	var min_rank := SectionMod.refill_rank_min(mod)
	var max_rank := SectionMod.refill_rank_max(mod)
	if min_rank > 2 or max_rank < Card.JOKER_RANK:
		return deck.draw_rank_range(min_rank, max_rank)
	return deck.draw()


func _lowest_starting_hand() -> Card:
	var out: Card = null
	for card in hand:
		if out == null or card.rank < out.rank:
			out = card
	return out


## 随机封优先(2026-08-25 用户:「封条不如随机封,双封也可以随机」);
## 旧的最低/最老参数仍然认(白名单保留)。抽签走 deck.pick_index ——
## 与丢谱标记同一条共享 RNG 纪律:游戏与探针同序、可复现。
func _pick_sealed_hand() -> Card:
	if SectionMod.seals_random_start(mod) and not hand.is_empty():
		return hand[deck.pick_index(hand.size())]
	return _lowest_starting_hand() if SectionMod.seals_lowest_start(mod) else null


func _pick_sealed_cache() -> Card:
	if SectionMod.seals_random_cache(mod) and not cache.is_empty():
		return cache[deck.pick_index(cache.size())]
	return _oldest_cache_card() if SectionMod.seals_oldest_cache(mod) else null


func _sync_cache_ages() -> void:
	if not cache_meta.has("ages") or not cache_meta["ages"] is Dictionary:
		cache_meta["ages"] = {}
	if not cache_meta.has("next"):
		cache_meta["next"] = 0
	var ages: Dictionary = cache_meta["ages"]
	for card in ages.keys():
		if not cache.has(card):
			ages.erase(card)
	for card in cache:
		_remember_cache_age(card)


func _remember_cache_age(card: Card) -> void:
	if card == null:
		return
	var ages: Dictionary = cache_meta["ages"]
	if ages.has(card):
		return
	ages[card] = int(cache_meta["next"])
	cache_meta["next"] = int(cache_meta["next"]) + 1


func _forget_cache_age(card: Card) -> void:
	if card != null and cache_meta.has("ages"):
		cache_meta["ages"].erase(card)


func _oldest_cache_card() -> Card:
	var out: Card = null
	var best_age := 9223372036854775807
	var ages: Dictionary = cache_meta["ages"]
	for card in cache:
		var age := int(ages.get(card, best_age))
		if age < best_age:
			best_age = age
			out = card
	return out

## Sort hand by rank (desc), then suit — the 理牌 button.
func sort_hand() -> void:
	if locked:
		return
	hand.sort_custom(func(a: Card, b: Card) -> bool:
		if a.rank != b.rank:
			return a.rank > b.rank
		return a.suit > b.suit)

## Live best-five preview of the current hand (for UI).
func current_best() -> Dictionary:
	return Pattern.evaluate_best(_scoring_cards(), deck.rules)


func _scoring_cards() -> Array:
	var cards: Array = hand.duplicate()
	if spotlight_card != null:
		cards.append(spotlight_card)
	for ghost in ghost_cards:
		cards.append(ghost)
	# 合奏(2026-08-25):缓存也上台 —— 8 张挑最好 5 张(与聚光灯 boon 同一条最优五张路)。
	if cache_scoring:
		for cc in cache:
			if cc != null:
				cards.append(cc)
	return cards


func has_initial_cache_in_hand() -> bool:
	for card in hand:
		if initial_cache.has(card):
			return true
	return false

## Indices into `visible` (= hand + cache, the solver's view) that the player
## cannot see. Lives here rather than in the solver because `hidden` is game
## state; the solver only consumes it.
func hidden_indices(visible: Array) -> Array:
	var out: Array = []
	# 蒙点/蒙色(2026-08-25):属性遮蔽在 bot 侧按「整张全盲」**保守近似** ——
	# 现有盲牌采样只有整张一种粒度。方向安全:bot 只会更弱, 脸只会被标得更狠
	# (与「目标读数偏严」同一安全方向);属性级信念是这两张脸补 tier 入池前的必修课。
	if SectionMod.hide_ranks(mod) or SectionMod.hide_suits(mod):
		for i in range(visible.size()):
			out.append(i)
		return out
	if hidden.is_empty():
		return out
	for i in range(visible.size()):
		if hidden.has(visible[i]):
			out.append(i)
	return out


## Lock input and evaluate the hand.
## ⚠ Hidden cards score EXACTLY as normal — the face took away sight, not
## value. Settling is also the moment they turn face up (用户拍板), so the
## set is cleared here and the view can play the reveal off `result`.
func lock_and_settle() -> Dictionary:
	if locked:
		return result
	locked = true
	result = Pattern.evaluate_best(_scoring_cards(), deck.rules)
	if request_goal != "":
		request_met = _request_satisfied(result)
	# 盲奏(2026-08-25):盖着上台的得分牌在翻开前点清 —— 全盖(盖牌脸)按张数,
	# 属性遮蔽(蒙色/蒙点)整手算盲(每张都只见一半)。翻开与结算是同一时刻。
	var hs := 0
	if SectionMod.hide_ranks(mod) or SectionMod.hide_suits(mod):
		hs = result.get("resolved", []).size()
	else:
		for hc in result.get("resolved", []):
			if hidden.has(hc):
				hs += 1
	result["hidden_scoring"] = hs
	hidden.clear()
	return result


func _request_satisfied(res: Dictionary) -> bool:
	match request_goal:
		"color_mix":
			var has_red := false
			var has_black := false
			for card in hand:
				has_red = has_red or card.is_red()
				has_black = has_black or not card.is_red()
			return has_red and has_black
		"face_or_ace":
			for card in hand:
				if card.rank >= 11 and card.rank <= 14:
					return true
			return false
		"initial_cache":
			for card in hand:
				if initial_cache.has(card):
					return true
			return false
		"fresh_kind":
			return request_prev_kind != -99 and int(res.get("kind", -99)) != request_prev_kind
	return true


## Conservative public-goal validation: every accepted request has a visible,
## deterministic route in the dealt hand/cache. Unknown future draws are never
## used to excuse an otherwise impossible objective.
func request_goal_valid(goal: String) -> bool:
	var visible: Array = hand.duplicate()
	visible.append_array(cache)
	match goal:
		"color_mix":
			var has_red := false
			var has_black := false
			for card in visible:
				has_red = has_red or card.is_red()
				has_black = has_black or not card.is_red()
			return has_red and has_black
		"face_or_ace":
			for card in visible:
				if card.rank >= 11 and card.rank <= 14:
					return true
			return false
		"initial_cache":
			return not initial_cache.is_empty()
		"fresh_kind":
			if request_prev_kind == -99:
				return false
			if int(current_best().get("kind", -99)) != request_prev_kind:
				return true
			for hi in range(hand.size()):
				for ci in range(cache.size()):
					var candidate: Array = hand.duplicate()
					candidate[hi] = cache[ci]
					if int(Pattern.evaluate_best(candidate, deck.rules).get("kind", -99)) != request_prev_kind:
						return true
			return false
	return false

## Send the hand to the discard pile at Phrase end. Cache persists — except
## under an eviction face, which drops `cache_evict` random cache cards here;
## the next start() tops the cache back up from the deck.
## ⚠ Charged by the phrase that just ENDED, i.e. by the face that was actually
## in play — a section boundary therefore bills the section you just left.
func cleanup() -> void:
	for c in hand:
		deck.discard(c)
	hand.clear()
	if spotlight_card != null:
		deck.discard(spotlight_card)
		spotlight_card = null
	ghost_cards.clear()
	var evict_left := SectionMod.cache_evict(mod)
	if marked_cache_card != null and evict_left > 0:
		evict_left -= 1
		var marked_i := cache.find(marked_cache_card)
		if marked_i >= 0:
			_forget_cache_age(marked_cache_card)
			deck.discard(marked_cache_card)
			cache.remove_at(marked_i)
		marked_cache_card = null
	for _i in range(evict_left):
		if cache.is_empty():
			break
		var j := deck.pick_index(cache.size())
		_forget_cache_age(cache[j])
		deck.discard(cache[j])
		cache.remove_at(j)
