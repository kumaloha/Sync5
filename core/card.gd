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


## 理牌的比较器 —— **点数降序, 同点数按花色降序**。
## ⚑ 抽到这里是因为它有**两个消费者**:游戏侧 `Phrase.sort_hand()` 与
## 重放侧 `tools/replay.gd`。而重放此前根本没实现理牌(它的注释说「理牌不改集合,
## 所以只计一个决策点」)—— **那句话对集合成立, 对下标不成立**:`swap` 事件记的是
## `hand[h] ↔ cache[c]` 的**下标**, 理牌一重排, 之后每一次对调都换错了牌。
## 2026-09-01 真人 Tape(run_20260831T203232_01)实测 3 处重放违规, 根因就是这个。
## ⇒ 口径只许有一份, 谁要理牌谁调它。
static func sort_desc(a: Card, b: Card) -> bool:
	if a.rank != b.rank:
		return a.rank > b.rank
	return a.suit > b.suit


## `label()` 的逆 —— "10S" / "KC" / "★C" → Card。给重放/日志解析用。
## ⚠ 认不出的串返回 rank = -1(排序时沉底), **不抛错也不猜** ——
## 重放的判据是「手牌集合对不对」, 让一个坏串静默变成一张合法的牌才是真的危险。
static func from_label(s: String) -> Card:
	if s.length() < 2:
		return Card.new(-1, 0)
	var su := SUITS.find(s.substr(s.length() - 1, 1))
	if su < 0:
		return Card.new(-1, 0)
	var rs := s.substr(0, s.length() - 1)
	if rs == "★":
		return Card.new(JOKER_RANK, JOKER_BIG)
	if rs == "☆":
		return Card.new(JOKER_RANK, JOKER_LITTLE)
	for r in RANK_NAMES:
		if RANK_NAMES[r] == rs:
			return Card.new(int(r), su)
	if rs.is_valid_int():
		return Card.new(int(rs), su)
	return Card.new(-1, su)

func is_red() -> bool:
	if is_wild():
		return is_big_joker()      # 大王 reads warm, 小王 cool
	return suit == 1 or suit == 2
