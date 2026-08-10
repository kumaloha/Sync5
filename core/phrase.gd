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
var discard_actions_used: int = 0
var swap_actions_used: int = 0
var action_count: int = 0
var action_track := ""         # "discard" | "swap" once switchtrack commits
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
	while cache.size() > cap:
		deck.discard(cache.pop_back())
	while cache.size() < cap:
		var cc := deck.draw()
		if cc == null:
			break
		cache.append(cc)
	discards_used = 0
	discard_actions_used = 0
	swap_actions_used = 0
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
	sealed_hand_card = _lowest_starting_hand() if SectionMod.seals_lowest_start(mod) else null
	sealed_cache_card = _oldest_cache_card() if SectionMod.seals_oldest_cache(mod) else null
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

func can_discard(count: int) -> bool:
	if locked or count <= 0 or coins < Economy.discard_cost(count):
		return false
	var limit := SectionMod.discard_action_limit(mod)
	if limit >= 0 and discard_actions_used >= limit:
		return false
	var shared := SectionMod.action_limit(mod)
	if shared >= 0 and action_count >= shared:
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
	# ⚠ A discarded card must leave `hidden` too — the dictionary is keyed by
	# object, and the deck recycles those same Card objects on reshuffle, so a
	# stale key would make a future draw arrive mysteriously face down.
	var blind_refill := SectionMod.hide_refill(mod)
	if BlindBoon.ghost_first_discard(boon) and ghost_cards.is_empty() and not hand_indices.is_empty():
		for first_i in hand_indices:
			var first_card: Card = hand[int(first_i)]
			ghost_cards.append(Card.new(first_card.rank, first_card.suit))
	for i in hand_indices:
		hidden.erase(hand[i])
		deck.discard(hand[i])
		hand[i] = _draw_refill()
		if blind_refill and hand[i] != null:
			hidden[hand[i]] = true
	for i in cache_indices:
		var old_cache: Card = cache[i]
		hidden.erase(old_cache)
		_forget_cache_age(old_cache)
		deck.discard(old_cache)
		cache[i] = _draw_refill()
		_remember_cache_age(cache[i])
		if blind_refill and cache[i] != null:
			hidden[cache[i]] = true
	discard_actions_used += 1
	action_count += 1
	if action_track == "":
		action_track = "discard"
	return true

## Swap a hand card with a cache card (free; time is the cost).
func swap_with_cache(hand_index: int, cache_index: int) -> bool:
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
	_forget_cache_age(hand[hand_index])
	_remember_cache_age(tmp)
	if SectionMod.cache_lock_phrases(mod) > 0:
		locked_cache_cards[tmp] = true
	swap_actions_used += 1
	action_count += 1
	if action_track == "":
		action_track = "swap"
	return true


func can_swap_action() -> bool:
	if locked or hand.is_empty() or cache.is_empty():
		return false
	var swap_limit := SectionMod.swap_action_limit(mod)
	if swap_limit >= 0 and swap_actions_used >= swap_limit:
		return false
	var shared := SectionMod.action_limit(mod)
	if shared >= 0 and action_count >= shared:
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
