class_name Joker
extends RefCounted

## Data shell over data/jokers.json (design/tech.md). Target jokers define WHAT a
## good answer is (pattern-family ×mult); support jokers define HOW to get
## there. All passive.
##
## Hook contract unchanged (design principle D1 — fixed set):
##   apply(ctx)        settle-time effect, returns popup text ("" = none)
##   on_acquire(deck)  once when installed (rule-change cards)
##   on_discard(n)     player discarded n cards (growth counters)
##   on_swap()         reserved — swaps are free, counters never hang on them
##   on_phrase_end(x)  phrase boundary (decay ticks, timing-growth)
##   on_section_end()  reserved
##
## Behaviors are DSL effects interpreted by core/fx.gd; growth counters are
## fed by the generic hooks reading the entry's `counters` spec. Channel ×
## rarity binding (principle B2) is a data convention now — see design/jokers.md/13.

var id: String
var name: String        # EN display name (US market)
var cn_name: String     # 中文名, used in design docs and dev tooling
var kind: String        # "target" | "support"
var rarity: String      # "common" | "uncommon" | "rare" | "" for targets
var fx_text: String     # card text — EN, ≤7 words (principle D2)
var state: Dictionary = {}   # per-run counters for growth/decay cards
var _effects: Array
var _counters: Dictionary
var _acquire: Dictionary
var _shelf: Dictionary   # 持续的**货架**影响(不是计分, 也不是一次性的 acquire)


func _init(e: Dictionary) -> void:
	id = String(e["id"])
	name = String(e["name"])
	cn_name = String(e["cn"])
	kind = String(e["kind"])
	rarity = String(e["rarity"])
	fx_text = String(e["fx"])
	_effects = e.get("effects", [])
	_counters = e.get("counters", {})
	_acquire = e.get("acquire", {})
	_shelf = e.get("shelf", {})
	state = Fx.init_state(_counters)


## 持有这张牌时, Target 在货架上的权重要乘多少 (design/solver_roadmap.md, 2026-08-06 用户批 A 案)。
##
## **为什么是卡面效果而不是暗改概率**:用户既拍板过「不应该有任何卡有固定概率, 大家都是
## 一样的」, 又要求「独狼一定要换旗」—— 两者只有一种活法:把那条保证**写到卡上**,
## 让玩家看得见(独狼卡面第二句就是 "more Targets")。规则出现在动作空间里, 不藏在掷点里。
## 声明式字段, 所以将来任何卡都能用, 不是给独狼开的后门。
func shelf_target_mult() -> float:
	return float(_shelf.get("target_weight_mult", 1.0))


## 持有这张牌时, 货架**必定**有一张 Target (2026-08-07 用户批 A 案)。
## 为什么从「×3 权重」升级成「必定」:独狼重做成经济/节奏卡之后,
## **拖的代价是确定的**(每拍少几百分), 而**换的回报只有 52% 会发生** ——
## 确定的代价配概率的回报, 期望上必然吃亏。做成必定, 两头就对称了:
## 前几段拖着攒钱, 到点必定能换成好构筑。
func shelf_target_guaranteed() -> bool:
	return bool(_shelf.get("target_guaranteed", false))


static func slots_guarantee_target(slots: Array) -> bool:
	for j in slots:
		if j != null and j.shelf_target_guaranteed():
			return true
	return false


## 当前装备下的合计倍率(多张就相乘)。
static func slots_target_mult(slots: Array) -> float:
	var m := 1.0
	for j in slots:
		if j != null:
			m *= j.shelf_target_mult()
	return m


## Called once when the joker is installed.
func on_acquire(deck: Deck) -> void:
	if deck == null:
		return
	if _acquire.has("wilds"):
		deck.enable_wilds()
	if _acquire.has("deck_rule"):
		deck.rules[String(_acquire["deck_rule"])] = true


## Player discarded `n` cards (hand or cache) in one paid action.
func on_discard(n: int) -> void:
	Fx.on_discard(_counters, state, n)


func on_swap() -> void:
	pass


## Phrase boundary. x: {early_finish: bool}
func on_phrase_end(x: Dictionary) -> void:
	Fx.on_phrase_end(_counters, state, x)


func on_section_end() -> void:
	pass


func apply(ctx: Dictionary) -> String:
	return Fx.apply_effects(_effects, state, ctx)


## 有无 effects 决定 kit 的 solver 臂用哪把判据(证物率 vs 分差)—— 见 tools/kit.gd::_run_solver。
func has_effects() -> bool:
	return not _effects.is_empty()


static func by_id(p_id: String) -> Joker:
	for j in pool():
		if j.id == p_id:
			return j
	return null


static func pool() -> Array:
	var out: Array = []
	for e in DB.jokers():
		out.append(Joker.new(e))
	return out


## 复制一张小丑牌给**假想推演**用。
## ⚠ `state` 是成长牌的计数器(黑胶/贝斯线/周转), **必须深拷贝** ——
## 共享它会让「算一下买哪张牌」把真实牌的成长进度也推进了, 而且不报错。
func clone() -> Joker:
	for e in DB.jokers():
		if String(e["id"]) == id:
			var j := Joker.new(e)
			j.state = state.duplicate(true)
			return j
	return null
