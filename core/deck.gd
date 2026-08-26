class_name Deck
extends RefCounted

## Standard 52-card deck with draw pile + discard pile.
## Hand and Cache live outside the deck, so they are naturally excluded
## from reshuffle.

var draw_pile: Array[Card] = []
var discard_pile: Array[Card] = []
var _rng := RandomNumberGenerator.new()

func _init(seed_value: int = -1) -> void:
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	_build_full()

## 大王/小王 are OFF by default — only a joker modifier puts them in the deck.
var wilds_enabled := false

## Run-owned rule flags set by rule-change jokers (shortcut / fourfingers /
## twotone). They live on the deck because the deck IS the run's card system —
## a fresh run builds a fresh deck, so the rules reset for free.
var rules: Dictionary = {}

func _build_full() -> void:
	draw_pile.clear()
	discard_pile.clear()
	for s in range(4):
		for r in range(2, 15):
			draw_pile.append(Card.new(r, s))
	if wilds_enabled:
		draw_pile.append(Card.new(Card.JOKER_RANK, Card.JOKER_BIG))
		draw_pile.append(Card.new(Card.JOKER_RANK, Card.JOKER_LITTLE))
	shuffle()

## Turn the two wild cards on mid-run: they are shuffled into the draw pile.
func enable_wilds() -> void:
	if wilds_enabled:
		return
	wilds_enabled = true
	draw_pile.append(Card.new(Card.JOKER_RANK, Card.JOKER_BIG))
	draw_pile.append(Card.new(Card.JOKER_RANK, Card.JOKER_LITTLE))
	shuffle()


## 修剪(trim):2 和 3 永久离开牌库 —— 牌库手术类规则牌,概率线最硬的 Δp
## (enable_wilds 是加牌先例,这是减牌先例)。
## ⚠ 手牌/缓存里已经握着的 2/3 不当场没收(玩家看得见的牌不许凭空消失),
## 它们被弃掉时经由 discard() 的过滤离场 —— 牌库在几拍内收敛到 44 张。
var trim_low := false
const TRIM_RANK_MAX := 3

func trim_low_ranks() -> void:
	if trim_low:
		return
	trim_low = true
	for i in range(draw_pile.size() - 1, -1, -1):
		if not draw_pile[i].is_wild() and draw_pile[i].rank <= TRIM_RANK_MAX:
			draw_pile.remove_at(i)
	for i in range(discard_pile.size() - 1, -1, -1):
		if not discard_pile[i].is_wild() and discard_pile[i].rank <= TRIM_RANK_MAX:
			discard_pile.remove_at(i)

func shuffle() -> void:
	for i in range(draw_pile.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := draw_pile[i]
		draw_pile[i] = draw_pile[j]
		draw_pile[j] = tmp

func draw() -> Card:
	if draw_pile.is_empty():
		_reshuffle_discard()
	if draw_pile.is_empty():
		return null
	return draw_pile.pop_back()


## Draw the next available card whose rank is inside an inclusive range while
## leaving ineligible cards in the deck. Low End uses this only for discard
## refills; the opening deal still follows ordinary deck order.
func draw_rank_range(min_rank: int, max_rank: int) -> Card:
	if draw_pile.is_empty():
		_reshuffle_discard()
	var found := _take_rank_range(min_rank, max_rank)
	if found != null:
		return found
	# A filtered draw can exhaust eligible ranks before the ordinary pile is
	# empty. Recycle discards here; otherwise Low End can return a null live card
	# merely because a few ineligible high cards remain on top of the shoe.
	if not discard_pile.is_empty():
		draw_pile.append_array(discard_pile)
		discard_pile.clear()
		shuffle()
		return _take_rank_range(min_rank, max_rank)
	return null


func _take_rank_range(min_rank: int, max_rank: int) -> Card:
	for i in range(draw_pile.size() - 1, -1, -1):
		var card: Card = draw_pile[i]
		if card.rank >= min_rank and card.rank <= max_rank:
			draw_pile.remove_at(i)
			return card
	return null

## A random index in [0, n) drawn from the DECK's own rng, so anything that
## reseeds the deck stays reproducible. Used by the cache-eviction faces —
## core/ must not reach for a clock or a global rng.
func pick_index(n: int) -> int:
	if n <= 1:
		return 0
	return _rng.randi_range(0, n - 1)


func discard(card: Card) -> void:
	if card == null:
		return
	# trim 生效后,弃掉的 2/3 不回弃牌堆 —— 永久离场(见 trim_low_ranks 注释)。
	if trim_low and not card.is_wild() and card.rank <= TRIM_RANK_MAX:
		return
	discard_pile.append(card)

func _reshuffle_discard() -> void:
	draw_pile = discard_pile.duplicate()
	discard_pile.clear()
	shuffle()

## 设想抽 n 张但**不消耗牌堆**(docs/design/solver_roadmap.md:求解器是在"算", 不是在"玩" ——
## 真去 draw() 会让求解本身改变游戏状态, 那就不是同一局了)。
## **一次调用内不放回**:一副牌里没有两张一样的, 放回抽样会虚构出对子。
## 待抽区不够就并上弃牌堆 —— 那正是 draw() 抽空后会洗回来的那批。
func peek_many(rng: RandomNumberGenerator, n: int) -> Array:
	if n <= 0:
		return []
	# ⚠ **不要"优化"成拒绝采样**(试过, 已撤回):那样 RNG 的消耗个数会变,
	# 抽到的补牌就跟着变 —— 而它**一点速度都没换来**(实测 0 提升, 瓶颈在 _classify)。
	# **不提速却改结果的优化是纯亏**:所有历史读数当场失去可比性。
	var pool: Array = draw_pile.duplicate()
	if pool.size() < n:
		pool.append_array(discard_pile)
	if pool.size() < n:
		return []
	var out: Array = []
	for i in range(n):
		var j := rng.randi_range(0, pool.size() - 1)
		out.append(pool[j])
		pool.remove_at(j)
	return out


func remaining() -> int:
	return draw_pile.size()

func total() -> int:
	return draw_pile.size() + discard_pile.size()


## ---- 断点续玩(2026-08-24)----
## 快照 = 恢复一副牌堆所需的全部事实:两堆的**顺序**、规则旗、万能牌开关、低段裁剪、RNG 状态。
## ⚠ 顺序就是内容 —— 恢复后从同一副堆序重发, 玩家拿回的是同一手牌。
func snapshot() -> Dictionary:
	return {
		"draw": cards_out(draw_pile), "disc": cards_out(discard_pile),
		"wilds": wilds_enabled, "trim": trim_low,
		"rules": rules.duplicate(true), "rng": _rng.state,
	}


## Card 数组 → [[rank, suit], …](Run.snapshot 的缓存区也用它)。
static func cards_out(arr) -> Array:
	var out: Array = []
	for c in arr:
		out.append([c.rank, c.suit])
	return out


static func from_snapshot(d: Dictionary) -> Deck:
	var deck := Deck.new()
	deck.draw_pile.clear()
	deck.discard_pile.clear()
	for p in d.get("draw", []):
		deck.draw_pile.append(Card.new(int(p[0]), int(p[1])))
	for p in d.get("disc", []):
		deck.discard_pile.append(Card.new(int(p[0]), int(p[1])))
	deck.wilds_enabled = bool(d.get("wilds", false))
	deck.trim_low = bool(d.get("trim", false))
	deck.rules = d.get("rules", {}).duplicate(true)
	deck._rng.state = int(d.get("rng", 0))
	return deck


## 复制一份牌堆给**假想推演**用(docs/design/solving.md 第三部分)。
## ⚠⚠ 必须有**自己的 RNG** —— 推演若用真实牌堆的 rng, 就会消耗真实局的随机数序列,
## 于是「算了一下买哪张牌」这个动作本身改变了这一局。那是最恶劣的一种污染:
## 不报错, 只是这一局悄悄变成了另一局。
## ⚠ 两条对照臂用**同一个 seed** fork —— 这就是公共随机数, 噪声成对抵消。
func fork(seed_value: int) -> Deck:
	var d := Deck.new(seed_value)
	d.draw_pile = draw_pile.duplicate()
	d.discard_pile = discard_pile.duplicate()
	d.wilds_enabled = wilds_enabled
	d.trim_low = trim_low
	d.rules = rules.duplicate(true)
	return d
