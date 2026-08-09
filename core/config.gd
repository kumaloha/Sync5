class_name GameConfig
extends RefCounted

## Facade over data/run.json + data/economy.json (design/tech.md). Every name
## keeps its old call-site syntax — the numbers just live in data/ now.
## 边做边改：手感/节奏数值全部在 data/,时长仍走 phrase_duration() 等钩子。

static var _run: Dictionary = DB.run()
static var _eco: Dictionary = DB.economy()

# --- Run structure (2026-08-06 节奏定案: run = 4 gigs × 1 blind, 6 phrases,
# shop every 3 — 商店与盲注**解耦**, 段中那次开在盲注进行当中) ---
static var PHRASES_PER_SECTION: int = int(_run["phrases_per_section"])
static var PHRASES_PER_SHOP: int = int(_run["phrases_per_shop"])
static var SHOPS_PER_SECTION: int = PHRASES_PER_SECTION / PHRASES_PER_SHOP
static var SECTIONS_PER_GIG: int = int(_run["sections_per_gig"])
static var GIGS_PER_RUN: int = int(_run["gigs_per_run"])
static var SECTIONS_PER_RUN: int = SECTIONS_PER_GIG * GIGS_PER_RUN
static var WALL_SECTIONS: Array = _walls()
static var BLIND_NAMES: Array = _run["blind_names"]
# venue arc placeholder (场地叙事弧 —— 文案在 data/run.json), shown on the home stage card
static var GIG_NAMES: Array = _run["gig_names"]
static var SECTION_TARGETS: Array = _ints(_run["section_targets"])

# --- Phrase timing (seconds) ---
static var RESOLVE_FEEDBACK := 0.25
static var LATE_ACT_WINDOW: float = float(_run["late_act_window"])
static var EARLY_FINISH_TIME: float = float(_run["early_finish_time"])

# --- Card flow ---
static var HAND_SIZE: int = int(_run["hand_size"])
static var CACHE_CAP: int = int(_run["cache_cap"])
static var CACHE_MAX: int = CACHE_CAP

# --- 手速预算 (design/solver_roadmap.md) ---
# 真人一拍(8s)物理上做得完几个动作。⚠ **故意不由 core/phrase.gd 强制**:
# 真人在游戏里只被时钟限制, 加一个硬计数器等于改游戏规则(用户没要这个)。
# 它的用途是让**求解器与模拟器共用同一个上限** —— 数学 D 在预算内求最优、
# sim 的完美玩家队列同预算, 三方对齐才谈得上「一致」。这条同时决定数学算不算得动:
# 预算无界 → 决策树无界 → 只能退回蒙特卡洛 = 又变成「用模拟冒充数学」。
static var BEAT_DISCARDS: int = int(_run["beat_budget"]["discards"])
static var BEAT_SWAPS: int = int(_run["beat_budget"]["swaps"])

## 盖牌脸下, 求解器给每张看不见的牌抽几组替身来估信念分。
## ⚠ 这些替身**必须给全部 56 个切法共用**(公共随机数) —— 否则切法之间的比较
## 会被替身噪声吃掉, 贪心退化成随机挑。同样的坑在 λ 扫描上栽过一次。
static var BLIND_SAMPLES: int = int(DB.sim()["solver"]["blind_samples"])


## 手速预算随**实际**拍长缩放。「赶场」砍 2 秒 → 能做的付费动作就少一档。
## ⚠ 这是赶场在模型里**唯一的着力点**:v1 求解器不弃牌时它是空气 ——
## S4 的池子是 [拔电, 赶场], 其中一张没效果, 那一半的局 S4 实际没有 Boss 规则、
## 难度被系统性低估。交换预算走不通(最多只要 cache_cap=3 次, 给了 5 次, 永远不binding)。
static func beat_discards(duration: float, section_idx: int) -> int:
	var full := phrase_duration(section_idx)
	return maxi(0, int(floor(float(BEAT_DISCARDS) * duration / maxf(0.1, full))))

# --- Economy ---
static var STARTING_COINS: int = int(_eco["starting_coins"])
static var DISCARD_COST: int = int(_eco["discard_cost"])
static var SECTION_CLEAR_REWARD: int = int(_eco["section_clear_reward"])
static var DRAFT_RARITY_WEIGHTS: Dictionary = _eco["draft_rarity_weights"]
static var JOKER_PRICES: Dictionary = _eco["joker_prices"]
static var JOKER_PRICE_OVERRIDES: Dictionary = _eco["joker_price_overrides"]
# ⚑ TARGET_SWAP_PRICE / CHANCE / FROM_SECTION 已删(2026-08-06 用户拍板 Target 回池:
# 「不应该有任何卡有固定概率, 大家都是一样的」)。换旗不再有专属骰子和专属价格 ——
# Target 按 rarity=rare 进同一个货架池, 出现率是**池子组成的推论**, 价格走同一张价目表。
# 顺带拆掉了 from_section 这颗地雷(它是按段号写死的绝对值, 改段数会静默漂到末段)。
static var DRAFT_REROLL_BASE: int = int(_eco["reroll"]["base"])
static var DRAFT_REROLL_STEP: int = int(_eco["reroll"]["step"])


static func phrase_duration(section_idx: int) -> float:
	return float(_run["gig_clocks"][mini(gig_of(section_idx), GIGS_PER_RUN - 1)])


static func warning_time(duration: float) -> float:
	return duration - float(_run["warning_offset"])


static func lock_time(duration: float) -> float:
	return duration - float(_run["lock_offset"])


static func is_wall(section_idx: int) -> bool:
	return (section_idx + 1) % SECTIONS_PER_GIG == 0


static func gig_of(section_idx: int) -> int:
	@warning_ignore("integer_division")
	return section_idx / SECTIONS_PER_GIG


static func blind_name(section_idx: int) -> String:
	return String(BLIND_NAMES[section_idx % SECTIONS_PER_GIG])


static func gig_name(section_idx: int) -> String:
	return String(GIG_NAMES[mini(gig_of(section_idx), GIGS_PER_RUN - 1)])


static func section_target(section_idx: int) -> int:
	return int(SECTION_TARGETS[clampi(section_idx, 0, SECTION_TARGETS.size() - 1)])


static func _walls() -> Array:
	var out: Array = []
	for i in range(SECTIONS_PER_RUN):
		if is_wall(i):
			out.append(i)
	return out


static func _ints(a: Array) -> Array:
	var out: Array = []
	for v in a:
		out.append(int(v))
	return out
