class_name GameConfig
extends RefCounted

## Facade over data/run.json + data/economy.json (docs/design/tech.md). Every name
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
# 首墙两层放水(2026-08-24 拍板, 语义见 data/run.json _comment_s1)
static var S1_FACE_MIN_RUN: int = int(_run["s1_face_min_run"])
static var S1_EASY_CHANCE: float = float(_run["s1_easy_chance"])

# --- Phrase timing (seconds) ---
static var RESOLVE_FEEDBACK := 0.25
static var LATE_ACT_WINDOW: float = float(_run["late_act_window"])
## 谢幕(curtain)的压哨窗口 —— 尾声(finale)那 2 秒之内更窄的一档。
## 与 `late_act_window` 同族配置, 不写死:两张卡的窗口宽度是可调的平衡旋钮。
static var FINAL_ACT_WINDOW: float = float(_run["final_act_window"])
## 早弃(earlyout)的「前段」线。⚠ **与 `early_finish_time`(早锁线)是两条独立的旋钮** ——
## 早锁问「你是不是不动了」, 早弃问「你的弃牌是不是都做完了」, 概念不同, 调一条不该连带另一条。
## ⚠ 卡面写死了秒数("in first N seconds"), 所以改这个值要连卡面一起改(同数额章的纪律)。
## ⚑ **4.0 → 6.0(2026-08-28)**:τ 的真人读数判了 4 秒窗口**物理上关着** ——
## 认知(开拍→首个动作)中位 **3.37s**,一批弃 2.41 张要 2.41×0.56+0.66 = **2.01s**,
## 最早也要 **5.38s** 才弃得完。实测触发率 4% = `numbers.md §3.2` 的死档
## (<5% 禁止入池),而窗口扫描 5s→12% / **6s→27%(爆发档)** / 7s→43%。
## ⇒ 这**不是数额问题,是条件与手速打架**;数额一分没动,只把门槛挪到人做得到的地方。
static var EARLY_DISCARD_WINDOW: float = float(_run["early_discard_window"])
## ⚠ `EARLY_LOCK_MIN`(点唱片的防手滑下限)已随主动收工一起退役(2026-08-31)。
## ⚑⚑ 早收判据 **B**(2026-08-31 用户拍板):「**本轮最后一次动作距离结算的时间**」。
## 旧口径是「最后动作 ≤ 3.5s」(距**开拍**), 8 秒拍下与本口径等价 —— 但**拍长一变就分叉**,
## 而拍长是个会动的旋钮(`phrase_duration()`)。⇒ 改成距**结算**的相对剩余, 自动跟随。
## ⚠ 同批退役了「点唱片主动收工」与「达标即收工」⇒ 每一拍无论如何走满全长,
## 「早点动完手然后干等」的**干等代价因此消失** —— 这个条件现在只奖励**决策速度**,
## 不奖励挂机(实测真人认知 3.37s、平均 6.16s 才动完手, 4.5s 剩余是真难度)。
static var EARLY_FINISH_LEFT: float = float(_run["early_finish_left"])

# --- Card flow ---
static var HAND_SIZE: int = int(_run["hand_size"])
static var CACHE_CAP: int = int(_run["cache_cap"])
static var CACHE_MAX: int = CACHE_CAP

# --- 手速预算 (docs/design/solver_roadmap.md) ---
# 真人一拍(8s)物理上做得完几个动作。⚠ **故意不由 core/phrase.gd 强制**:
# 真人在游戏里只被时钟限制, 加一个硬计数器等于改游戏规则(用户没要这个)。
# 它的用途是让**求解器与模拟器共用同一个上限** —— 数学 D 在预算内求最优、
# sim 的完美玩家队列同预算, 三方对齐才谈得上「一致」。这条同时决定数学算不算得动:
# 预算无界 → 决策树无界 → 只能退回蒙特卡洛 = 又变成「用模拟冒充数学」。
# ⚑ 动作粒度(2026-08-27, 新基线):BEAT_DISCARDS = 每拍弃牌**动作次数**预算 ——
# 一次跨区多选批量弃 = 1 个动作(真人手势如此;旧口径把张数当动作数, 弃 6 结构性不可达)。
# 单批能圈几张走 BEAT_DISCARD_BATCH(8 = 全部可见牌)。
static var BEAT_DISCARDS: int = int(_run["beat_budget"]["discards"])
static var BEAT_DISCARD_BATCH: int = int(_run["beat_budget"]["discard_batch"])
static var BEAT_SWAPS: int = int(_run["beat_budget"]["swaps"])

## 盖牌脸下, 求解器给每张看不见的牌抽几组替身来估信念分。
## ⚠ 这些替身**必须给全部 56 个切法共用**(公共随机数) —— 否则切法之间的比较
## 会被替身噪声吃掉, 贪心退化成随机挑。同样的坑在 λ 扫描上栽过一次。
static var BLIND_SAMPLES: int = int(DB.sim()["solver"]["blind_samples"])


## 手速预算随**实际**拍长缩放。「赶场」砍 2 秒 → 能做的付费动作就少一档。
## ⚠ 这是赶场在模型里**唯一的着力点**:v1 求解器不弃牌时它是空气 ——
## S4 的池子是 [拔电, 赶场], 其中一张没效果, 那一半的局 S4 实际没有 Boss 规则、
## 难度被系统性低估。交换预算走不通(最多只要 cache_cap=3 次, 给了 5 次, 永远不binding)。
## ⚑ 2026-08-27 起返回的是**动作次数**(见 BEAT_DISCARDS 头注), 不再是张数。
static func beat_discards(duration: float, section_idx: int) -> int:
	var full := phrase_duration(section_idx)
	return maxi(0, int(floor(float(BEAT_DISCARDS) * duration / maxf(0.1, full))))


## 单批弃牌张数上限, 同样随实际拍长缩放(时间少 ⇒ 圈牌的手也慢)——
## 赶场的时间压力因此在**两层**都咬得住:动作更少、单批也更小。
## 与 beat_discards 同一条缩放公式, 「乘除只写一处」在 GameConfig 这层成立。
static func discard_batch(duration: float, section_idx: int) -> int:
	var full := phrase_duration(section_idx)
	return maxi(0, int(floor(float(BEAT_DISCARD_BATCH) * duration / maxf(0.1, full))))

# --- Economy ---
static var STARTING_COINS: int = int(_eco["starting_coins"])
static var DISCARD_COST: int = int(_eco["discard_cost"])
static var RESHUFFLE_COST: int = int(_eco.get("reshuffle_cost", 3))
## ⚠ `CASHOUT_PER_PHRASE`(落袋单价)已随「达标即收工」一起退役(2026-08-31)。
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
