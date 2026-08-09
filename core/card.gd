class_name Card
extends RefCounted

## A single playing card. rank 2..14 (J/Q/K/A = 11/12/13/14), suit 0..3.

const SUITS := ["C", "D", "H", "S"]        # 梅花/方块/红桃/黑桃
const SUIT_GLYPHS := ["♣", "♦", "♥", "♠"]
const RANK_NAMES := {11: "J", 12: "Q", 13: "K", 14: "A"}

## Wild cards (大王/小王). They are NOT in the deck by default — a joker
## modifier has to put them there. rank 15, suit carries big/little.
const JOKER_RANK := 15
const JOKER_BIG := 0
const JOKER_LITTLE := 1

var rank: int
var suit: int

func _init(r: int, s: int) -> void:
	rank = r
	suit = s

func is_wild() -> bool:
	return rank == JOKER_RANK

func is_big_joker() -> bool:
	return rank == JOKER_RANK and suit == JOKER_BIG

func rank_label() -> String:
	if is_wild():
		return "★" if is_big_joker() else "☆"
	return RANK_NAMES.get(rank, str(rank))

func label() -> String:
	return rank_label() + SUITS[suit]

func glyph() -> String:
	return rank_label() + SUIT_GLYPHS[suit]

func is_red() -> bool:
	if is_wild():
		return is_big_joker()      # 大王 reads warm, 小王 cool
	return suit == 1 or suit == 2
