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
var locked: bool = false
var result: Dictionary = {}

## This section's Boss face id ("" = none). A plain field rather than a ctor
## argument so the three call sites (view orchestrator / sim / curve) opt in
## with one line and every existing `Phrase.new(...)` keeps working.
## ⚠ Set it BEFORE start() — the cache-capacity face is applied there.
var mod: String = ""

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
	locked = false
	result = {}
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
	return not locked and count > 0 and coins >= Economy.discard_cost(count)

## Discard selected cards from hand and/or cache in one paid action.
## Every discarded card is replaced in place immediately. Returns false (and
## does nothing) if locked, selection empty, coins short, or an index invalid.
func discard_selected(hand_indices: Array, cache_indices: Array = []) -> bool:
	var total: int = hand_indices.size() + cache_indices.size()
	if not can_discard(total):
		return false
	for i in hand_indices:
		if i < 0 or i >= hand.size():
			return false
	for i in cache_indices:
		if i < 0 or i >= cache.size():
			return false
	coins -= Economy.discard_cost(total)
	discards_used += total
	# ⚠ A discarded card must leave `hidden` too — the dictionary is keyed by
	# object, and the deck recycles those same Card objects on reshuffle, so a
	# stale key would make a future draw arrive mysteriously face down.
	var blind_refill := SectionMod.hide_refill(mod)
	for i in hand_indices:
		hidden.erase(hand[i])
		deck.discard(hand[i])
		hand[i] = deck.draw()
		if blind_refill and hand[i] != null:
			hidden[hand[i]] = true
	for i in cache_indices:
		hidden.erase(cache[i])
		deck.discard(cache[i])
		cache[i] = deck.draw()
		if blind_refill and cache[i] != null:
			hidden[cache[i]] = true
	return true

## Swap a hand card with a cache card (free; time is the cost).
func swap_with_cache(hand_index: int, cache_index: int) -> bool:
	if locked or hand_index < 0 or hand_index >= hand.size():
		return false
	if cache_index < 0 or cache_index >= cache.size():
		return false
	var tmp: Card = hand[hand_index]
	hand[hand_index] = cache[cache_index]
	cache[cache_index] = tmp
	return true

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
	return Pattern.evaluate_best(hand, deck.rules)

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
	result = Pattern.evaluate_best(hand, deck.rules)
	hidden.clear()
	return result

## Send the hand to the discard pile at Phrase end. Cache persists — except
## under an eviction face, which drops `cache_evict` random cache cards here;
## the next start() tops the cache back up from the deck.
## ⚠ Charged by the phrase that just ENDED, i.e. by the face that was actually
## in play — a section boundary therefore bills the section you just left.
func cleanup() -> void:
	for c in hand:
		deck.discard(c)
	hand.clear()
	for _i in range(SectionMod.cache_evict(mod)):
		if cache.is_empty():
			break
		var j := deck.pick_index(cache.size())
		deck.discard(cache[j])
		cache.remove_at(j)
