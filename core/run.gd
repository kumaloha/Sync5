class_name Run
extends RefCounted

## Run progression state machine (docs/design/tech.md): everything about WHERE the
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
## exactly how the six copies of the phrase loop drifted apart (docs/design/tech.md).
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
	# ⚠ **`tutorial` 自己不在这里清**(调用方 reset 之后才设它, 见 roll_faces 那条注释),
	# 但**进度必须清** —— 否则重开会带着上一次的步骤下标继续走。
	tutorial_step = 0
	_tutorial_acted.clear()
	_tutorial_step_beats = 0
	roll_faces(face_seed)


## Boss faces are rolled for the whole run up front (Balatro's visible-boss
## mechanic — the preview one section ahead is what turns a face from an
## execution into a routing decision).
## ⚑ `run_index` = **这是第几局(1 起)**, 决定哪些脸已解锁(`min_run`)。
## **`-1` = 不设限、全部解锁**, 也是缺省 —— 探针/测试因此逐字节不变(见 `SectionMod.unlocked_at`)。
## ⚠ **显式参数, 不是实例字段** —— 上面那条「先设 tutorial 再调这里」的顺序契约
## 我自己一小时内就违反过一次, 所以这次不再造第二条顺序契约:忘了传 = 退回旧行为(全解锁),
## 而不是**静默用上一局的值**。
func roll_faces(face_seed: int = -1, run_index: int = -1) -> void:
	if face_seed >= 0:
		_blind_rng.seed = face_seed
	else:
		_blind_rng.randomize()
	# ⚑ **教学关不掷 Boss 脸** —— 起承転結 的「起」按定义是「安全的地方、**无惩罚**地
	# 理解机制」(docs/design/research_pacing_retention.md §5.5), 挂一张 Boss 规则直接违背它。
	# ⚠ 所以调用方必须**先设 `tutorial` 再调这里**;顺序反了教学关第一拍就带着一张脸。
	if tutorial:
		run_faces = {}
		run_boon = ""
		return
	# ⚑ 一局四张脸走 `SectionMod.roll_run` 这**一份**(2026-08-14 收口, 原来 7 份)——
	# 它保证「一局之内不偶然重复」, 而那条守卫只加在这里、探针各掷各的就是
	# 「规则在游戏里不在模型里」的第 6 次。
	# ⚑ 走 Director(B 轴 · 跨局序列)。`face_ranking` 为空时它**逐字节退回**
	# `SectionMod.roll`(Director 文件头承诺的), 所以现在接上**不改变任何掷法**,
	# 也不改 RNG 消耗 —— 排序表(tools/price.gd 的仪器输出)到位后才真正生效。
	# ⚠ 排序是**仪器读数不是设计常量**, 所以它是入参, 不进 data/(会过期)。
	run_faces = Director.roll_run(run_index, _blind_rng, face_ranking)
	run_boon = BlindBoon.roll(_blind_rng)


## This section's Boss face id ("" = none).
##
## ⚑⚑ 教学关在**这里**也挡一道, 而不是只靠「先设 tutorial 再 roll_faces」的顺序约定。
## 起因:我写下那条顺序契约不到一小时, 就在自己的测试里违反了它
## (`Run.reset()` 内部会 `roll_faces()`, 而测试在 reset 之后才设 `tutorial`)——
## **一条我自己都记不住的调用顺序契约, 是个坏契约。**
## 现在顺序怎么写都对:`roll_faces` 的提前返回只是省一次掷点, **正确性不依赖它**。
func face() -> String:
	if tutorial:
		return ""
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
## ⚑ **教学关模式**(docs/design/difficulty.md §4)—— 用户 2026-08-07 拍板「教学单开一关」。
## 它**不判生死、不进 curve.gd 的分位数反解**, 所以:
##   · `target()` 恒 0 ⇒ 分数永远够, 一拍都不会死(起承転結 的「起」= **无惩罚**);
##   · `phrase_duration()` 走 `Tutorial` 的脚本(12s 收到 8s), 不走 gig_clocks。
## ⚠ 只挂在**实例**方法上, 不碰 `phrase_duration_for` 那个静态口 ——
## 它是求解器/bot 共用的, 而教学关**不属于模型**, 混进去就是给尺子掺水。
var tutorial := false

## 脸的难度排序 `{段号: [face_id 由易到难]}` —— `tools/price.gd` 出数, **调用方传入**。
## 空 = Director 退回原掷法(见 roll_faces)。**别把它搬进 data/**:它是仪器读数,
## 抄进配置就会过期, 而「同一个口径抄第二份」是这个项目最贵的一类错。
var face_ranking: Dictionary = {}


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
		return Tutorial.seconds(tutorial_step)
	return phrase_duration_for(section_idx, face())


## ---- 教学关的进度 ----
##
## ⚑⚑ **步骤下标与拍数解耦(2026-08-16)** —— 从前这里全部读 `phrase_in_section`,
## 于是**一拍过去就下一步, 玩家做没做那个动作都一样**:第 3 步说「拖一张进去」,
## 不拖也照样进第 4 步。⇒ 教了不等于学会了, 而且连「有没有做」都不知道。
## 现在步骤只在**这一步要求的动作被做出来**之后才推进(外部调研的第 ② 条共识)。
var tutorial_step := 0

## 这一拍已经做出来的动作(`Tutorial.ACTIONS` 的子集), 每拍开头清空。
## ⚠ 它是**这一拍**的账, 不是整关的 —— 「上一拍弃过牌」不该替这一拍的门买单。
var _tutorial_acted: Dictionary = {}

## 当前这一步已经打了几拍。⚠⚠ **软门必须有兜底, 否则做不出那个动作就永远卡在同一句上。**
## 2026-08-17 真人试玩报的:「同一条提示词放了太多轮」—— 第 6 步要「手牌和缓存一起选着弃」,
## 想不到这个操作就无限重复。⚑ 我给**时钟**做了 30 秒兜底(`TUTOR_HOLD_MAX`),
## 却忘了给**步进**做 —— 同一个道理漏了一半。
## ⚑ **1 拍 = 任何教学最多一次结算都要过**(2026-08-19 用户拍板, 推翻 3 拍练习位)。
## 动作门从此只剩一个作用:**做完动作提示立刻换**(tutorial_advance_if_done 的拍中路径);
## 拍末一律放行 —— 教学关的职责是让他见过, 不是把他扣在原地。
const STEP_MAX_BEATS := 1
var _tutorial_step_beats := 0


## 编排器报一个玩家动作。⚠ **只有编排器调**(view/phrase.gd)——
## 和「金币/装槽等经济动作只发生在编排器」「打点只在编排器打」同一条线:
## 组件各报各的必然报重、报漏。
func tutorial_note(action: String) -> void:
	if tutorial:
		_tutorial_acted[action] = true


## 这一拍结束时调。要求满足就推进一步并返回 `true`;没满足就**留在原地**返回 `false`。
## 无论推没推进, 这一拍的动作账都清空。
func tutorial_try_advance() -> bool:
	if not tutorial:
		return false
	var need := Tutorial.require(tutorial_step)
	var ok: bool = need == "" or bool(_tutorial_acted.get(need, false))
	_tutorial_acted.clear()
	_tutorial_step_beats += 1
	# ⚠ 兜底:同一步打满 STEP_MAX_BEATS 拍就放行, 哪怕动作没做出来。
	# 返回值仍是**真实的**「做到没有」—— 调用方要区分「学会了」和「超时放行」时看它。
	if ok or _tutorial_step_beats >= STEP_MAX_BEATS:
		tutorial_step += 1
		_tutorial_step_beats = 0
	return ok


## 拍中推进(2026-08-18 用户:「应该消失, 进入下一个提示」)—— 动作一做出来提示就该换,
## 等拍末才换在玩家眼里是「照做了但提示没消失」。与拍末那份(`tutorial_try_advance`)的分工:
## · 这里**只认真做到的**:空门(play 语义 = 把一拍打完)不在拍中放行, 留给拍末;
## · **不吃兜底**:拍数账(`_tutorial_step_beats`)不动, 超时放行仍然只属于拍末;
## · 推进时**清动作账** —— 第 3/4 步都是 swap, 不清的话一次交换会在拍末再顶一步,
##   把「再换一次」的练习位整个吞掉(t_tutorial 锁着这条)。
func tutorial_advance_if_done() -> bool:
	if not tutorial:
		return false
	var need := Tutorial.require(tutorial_step)
	if need == "" or not bool(_tutorial_acted.get(need, false)):
		return false
	tutorial_step += 1
	_tutorial_step_beats = 0
	_tutorial_acted.clear()
	return true


## 这一步还欠什么动作 —— 空串 = 不欠。给编排器做「再说一次」的反馈用。
func tutorial_pending() -> String:
	if not tutorial:
		return ""
	var need := Tutorial.require(tutorial_step)
	return "" if need == "" or bool(_tutorial_acted.get(need, false)) else need


## 教学关这一拍该亮哪些部件 / 说什么。非教学关时**全部解锁、无提示** ——
## 调用方因此不必到处写 `if run.tutorial`。
func tutorial_unlocked(component: String) -> bool:
	return (not tutorial) or Tutorial.is_unlocked(component, tutorial_step)


func tutorial_hint() -> Dictionary:
	return Tutorial.hint(tutorial_step) if tutorial else {"command": "", "signal": ""}


## 教学关走完了没有。⚠ 判据是**走完的步数**而不是拍数 —— 动作门解耦之后
## 两者不再相等(卡在某一步会一直打拍而不推进), 而教学关的长度由**脚本**定,
## 不受 `PHRASES_PER_SECTION` 约束(用户拍板:教学关可以突破 4.9 分钟)。
func tutorial_done() -> bool:
	return tutorial and tutorial_step >= Tutorial.steps()


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


## 曲目税(2026-08-13 裁决 #8, docs/design/blinds_review.md §6):种数配额**不再是硬门**,
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
