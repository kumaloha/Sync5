class_name Run
extends RefCounted

## Run progression state machine (design/tech.md): everything about WHERE the
## run stands lives here, engine-free and directly testable — deck, cache,
## section/phrase counters, joker slots, rolled boss faces. view/phrase.gd
## keeps only presentation and input orchestration and reads the verdicts
## from advance().

var deck: Deck
var cache: Array = []
var section_idx := 0
var phrase_in_section := 0
var section_score := 0
var phrase_index := 0
var joker_slots: Array = [null, null, null, null]
var prev_kind := -99
## Hand type played on this SECTION's opening phrase, -99 until it happens.
## Only `setlist` reads it, but it lives here (not in the view) because it is
## run state, and sim/curve must see the same lock the player does.
var first_kind := -99
var run_faces: Dictionary = {}      # wall section -> face id, rolled at run start
var run_boon := ""                  # rolled up front, revealed only in section four
var section_discards_used := 0
var section_kinds: Dictionary = {}
var cache_meta: Dictionary = {"ages": {}, "next": 0}
var previous_raw_score := 0
var request_last := ""
var _blind_rng := RandomNumberGenerator.new()
var character: Character = null
## Coins carried across phrases. The Phrase owns them during a phrase (that is
## where tolls and discards are charged); this is the carry between phrases, so
## that a probe does not have to invent its own coin variable — inventing one is
## exactly how the six copies of the phrase loop drifted apart (design/tech.md).
var coins: int = 0

## Where this run stands INSIDE a phrase. `Beat` refuses to run a step out of
## order — see core/beat.gd. Only a state machine can catch "I forgot to call
## it": a merely-available shared function does not (tools/sim.gd read the target
## table by hand while Run.target() sat right there).
enum Stage {DECISION, SETTLED, ENDED}
var stage: int = Stage.DECISION


func reset(face_seed: int = -1) -> void:
	deck = Deck.new()
	cache.clear()
	section_idx = 0
	phrase_in_section = 0
	section_score = 0
	phrase_index = 0
	joker_slots = [null, null, null, null]
	prev_kind = -99
	first_kind = -99
	section_discards_used = 0
	section_kinds.clear()
	cache_meta = {"ages": {}, "next": 0}
	previous_raw_score = 0
	request_last = ""
	character = null
	coins = GameConfig.STARTING_COINS
	stage = Stage.DECISION
	roll_faces(face_seed)


## Boss faces are rolled for the whole run up front (Balatro's visible-boss
## mechanic — the preview one section ahead is what turns a face from an
## execution into a routing decision).
func roll_faces(face_seed: int = -1) -> void:
	if face_seed >= 0:
		_blind_rng.seed = face_seed
	else:
		_blind_rng.randomize()
	# ⚑ **教学关不掷 Boss 脸** —— 起承転結 的「起」按定义是「安全的地方、**无惩罚**地
	# 理解机制」(design/research_pacing_retention.md §5.5), 挂一张 Boss 规则直接违背它。
	# ⚠ 所以调用方必须**先设 `tutorial` 再调这里**;顺序反了教学关第一拍就带着一张脸。
	if tutorial:
		run_faces = {}
		run_boon = ""
		return
	# ⚑ 一局四张脸走 `SectionMod.roll_run` 这**一份**(2026-08-14 收口, 原来 7 份)——
	# 它保证「一局之内不偶然重复」, 而那条守卫只加在这里、探针各掷各的就是
	# 「规则在游戏里不在模型里」的第 6 次。
	run_faces = SectionMod.roll_run(_blind_rng)
	run_boon = BlindBoon.roll(_blind_rng)


## This section's Boss face id ("" = none).
func face() -> String:
	return String(run_faces.get(section_idx, ""))


## The positive finale surprise is deliberately unavailable to earlier-round
## previews even though its deterministic roll already lives in run state.
func boon() -> String:
	if section_idx < GameConfig.SECTIONS_PER_RUN - 1:
		return ""
	return run_boon


const REQUEST_GOALS := ["color_mix", "face_or_ace", "initial_cache", "fresh_kind"]


func next_request_goal(p: Phrase = null) -> String:
	var pool: Array = REQUEST_GOALS.duplicate()
	if phrase_in_section == 0:
		pool.erase("fresh_kind")
	if p != null:
		var valid: Array = []
		for goal in pool:
			if p.request_goal_valid(String(goal)):
				valid.append(goal)
		pool = valid
	# Prefer the non-repeating contract whenever the dealt state offers a
	# second valid route. If the only achievable request is the previous one,
	# keep it public instead of silently turning the whole Request beat off.
	if pool.size() > 1:
		pool.erase(request_last)
	if pool.is_empty():
		return ""
	var picked := String(pool[_blind_rng.randi_range(0, pool.size() - 1)])
	request_last = picked
	return picked


static func request_label(goal: String) -> String:
	match goal:
		"color_mix": return "红黑同台"
		"face_or_ace": return "含 J/Q/K/A"
		"initial_cache": return "用初始缓存"
		"fresh_kind": return "更换牌型"
	return ""


## The section's target, after the face's multiplier (raisedbar 1.5).
## ⚠ raisedbar is the one face that is HONESTLY a difficulty knob — Balatro
## does the same (The Wall 4×, Violet Vessel 6×) and never disguises pure
## amount as a rule. Everything else must change the problem, not the bar.
## ⚑ **教学关模式**(design/difficulty.md §4)—— 用户 2026-08-07 拍板「教学单开一关」。
## 它**不判生死、不进 curve.gd 的分位数反解**, 所以:
##   · `target()` 恒 0 ⇒ 分数永远够, 一拍都不会死(起承転結 的「起」= **无惩罚**);
##   · `phrase_duration()` 走 `Tutorial` 的脚本(12s 收到 8s), 不走 gig_clocks。
## ⚠ 只挂在**实例**方法上, 不碰 `phrase_duration_for` 那个静态口 ——
## 它是求解器/bot 共用的, 而教学关**不属于模型**, 混进去就是给尺子掺水。
var tutorial := false


func target() -> int:
	if tutorial:
		return 0
	return int(round(float(section_target_for(GameConfig.SECTION_TARGETS, section_idx, face()))
		* variety_mult(face(), section_kinds.size())))


## 这一拍有多少秒 —— 关卡曲线钩子减去这张脸砍掉的时间。
##
## ⚠ 这个表达式曾经有三份(`view/phrase.gd` + `tools/bot.gd` ×2), 而「赶场 −2s」
## 正是五次「规则在游戏里、不在模型里」的第一次:模型那份当时不含时间维度, S4
## 有一半的局实际上没有 Boss 规则。**乘除只写一处, 谁要用谁来调。**
## 弃牌免费之后时间是唯一的闸门, 所以这一处比它看上去更重要。
static func phrase_duration_for(section: int, mod: String) -> float:
	return GameConfig.phrase_duration(section) - SectionMod.time_penalty(mod)


func phrase_duration() -> float:
	if tutorial:
		return Tutorial.seconds(phrase_in_section)
	return phrase_duration_for(section_idx, face())


## 教学关这一拍该亮哪些部件 / 说什么。非教学关时**全部解锁、无提示** ——
## 调用方因此不必到处写 `if run.tutorial`。
func tutorial_unlocked(component: String) -> bool:
	return (not tutorial) or Tutorial.is_unlocked(component, phrase_in_section)


func tutorial_hint() -> Dictionary:
	return Tutorial.hint(phrase_in_section) if tutorial else {"command": "", "signal": ""}


## 教学关走完了没有。⚠ 判据是**拍数**而不是段数 —— 教学关的长度由脚本定,
## 不受 `PHRASES_PER_SECTION` 约束(用户拍板:教学关可以突破 4.9 分钟)。
func tutorial_done() -> bool:
	return tutorial and phrase_in_section >= Tutorial.steps()


## 段目标 = 表里的基准 × 这一段的脸的加码。
##
## ⚠ **判生死的地方必须共用这一份。** 2026-08-07 抓到:`tools/sim.gd` 判生死时直接读
## `bot_targets[section]`, 没乘 `target_mult` —— 于是 **raisedbar 在模型里整个是空气**,
## 游戏里 ×1.5 而 sim 里当它不存在。这是「规则在游戏里, 不在模型里」的**第五次**,
## 而且和前四次一样不报错。两张表(真人锚 run.json / 机器人影子 sim.json)尺度不同,
## 所以表当参数传, 但**乘法只写这一处**。
static func section_target_for(table: Array, section: int, mod: String) -> int:
	if table.is_empty():
		return 0
	var base: int = int(table[mini(section, table.size() - 1)])
	return int(round(float(base) * SectionMod.target_mult(mod)))


## 曲目税(2026-08-13 裁决 #8, design/blinds_review.md §6):种数配额**不再是硬门**,
## 改成「缺一种, 目标升一档」—— 硬门是处决不是税(墙的健康带是 30-60%, 检查表即死
## 违反 bent-not-bricked 的手术原则), 且旧硬门只活在 advance() 的 cleared 里,
## runloop 的判生死根本没查它 —— 又是半个「游戏里活、模型里死」。
## **税是悲观实时的**:段首欠满额(0 种已覆盖 = 全额税), 每覆盖一种目标当场下降 ——
## HUD/商店缺口/判生死读的是同一个数, 覆盖种类的进度肉眼可见。
## ⚠ 判生死只有一份:游戏(`target()`)与探针(`RunLoop`)都必须乘这里, 别再各写。
static func variety_mult(mod: String, kinds_made: int) -> float:
	var quota := SectionMod.required_kinds(mod)
	if quota <= 0:
		return 1.0
	var missing := maxi(0, quota - kinds_made)
	return 1.0 + SectionMod.variety_penalty(mod) * float(missing)


## One phrase ended; step the counter and report where the run stands.
##
## `shop_break` = the mid-section shop (2026-08-06 用户拍板: 商店与盲注解耦).
## The section is NOT over — score keeps accumulating, no clear/fail verdict,
## no banner. That is the whole point: you shop having already played half the
## blind, so you buy AGAINST a known deficit instead of betting on an unseen
## one. Never both flags at once — the last phrase's boundary is section_done.
func advance() -> Dictionary:
	phrase_in_section += 1
	var done := phrase_in_section >= GameConfig.PHRASES_PER_SECTION
	# 曲目的种数配额已并进 target()(variety_mult, 裁决 #8)—— cleared 只比分数,
	# 不再有第二条判定;旧的 requirements_met 键随硬门一起删(零消费点)。
	return {"section_done": done,
		"shop_break": not done and phrase_in_section % GameConfig.PHRASES_PER_SHOP == 0,
		"cleared": done and section_score >= target(),
		"is_wall": GameConfig.is_wall(section_idx),
		"finale": section_idx >= GameConfig.SECTIONS_PER_RUN - 1}


## Phrases left in this section — the shop's 「还剩 N 拍」 readout, which is
## what makes a mid-section purchase a solvable problem instead of a bet.
func phrases_left() -> int:
	return maxi(0, GameConfig.PHRASES_PER_SECTION - phrase_in_section)


## Points still owed on this section's target (0 once it is already met).
func deficit() -> int:
	return maxi(0, target() - section_score)


## Phrases actually played in the section that just closed. Exists so a probe
## can audit "did this section really run its full length" WITHOUT depending on
## catching the boundary frame — the light-banner path advances synchronously,
## so `phrase_in_section == PHRASES_PER_SECTION` is never observable from
## outside on that route.
var last_section_phrases := 0


func next_section() -> void:
	last_section_phrases = phrase_in_section
	section_idx = mini(section_idx + 1, GameConfig.SECTIONS_PER_RUN - 1)
	phrase_in_section = 0
	section_score = 0
	# the lock is per-SECTION: a new blind opens with nothing locked
	first_kind = -99
	section_discards_used = 0
	section_kinds.clear()
	request_last = ""
