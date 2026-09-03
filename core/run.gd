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
## 消耗品栏 —— **2 格**(2026-08-29 开轴, 原作同数)。存 `Consumable` 或 null。
## ⚑ 为什么是 2 格而不是 1:用户拍板**实时可点**(「只在商店用其实有点怪, 应该实时可以点」),
## 而实时可用的核心价值就是「攒着等关键拍」—— 1 格会退化成「拿到就烧」, 把这个价值废掉。
## ⚠ 它和 `joker_slots` 是**两套槽位, 互不占用** —— 让消耗品来抢那 4 个小丑槽,
## 等于逼玩家在「构筑」和「道具」之间做一个不该有的取舍(与 2026-08-29 修的
## 「转型和换旗抢同一个购买名额」同型:奖励某件事的东西不能和那件事抢同一个资源)。
## ⚑⚑ **待播队列(2026-09-01):不再是 2 格栏位, 而是一摞排队的碟。**
## 消耗牌全部自动触发 ⇒ 「栏位」这个概念本身没了:`buy` 类买下即执行、根本不进队,
## 只有时机卡(开场①/副歌④/彩头⑥/快闪▸)会在这里等它的拍号。
## ⚠ 上限是**算出来的 4** 而不是拍的:商店每 3 拍一次, 一张卡最长等 5 拍 ⇒ 跨得过
## 一次商店、跨不过两次;联票能在一店买 2 ⇒ 2 店 × 2 = 4。**不设硬上限** ——
## 一条几乎不触发的规则, 玩家要为它付理解成本却几乎用不上(UI 显示 3 + 「+1」)。
var consumables: Array = []
## ⚑ 预支的**待还款**(2026-08-30 三批转生)。玩家在商店烧掉预支 ⇒ 当场 +borrow、
## 记下 repay;**下一个段边界**结算, 付不起 = run 死(卡面写着 "or die")。
## ⚠⚠ 它取代了 `Joker.slots_loan` 的循环贷 —— 旧形态是**每段初自动借、段末自动还**,
## 玩家零决策, 而判据「每段一次也判一次性」正好指着它(consumables.md)。
## ⚠ 必须进存档:2026-08-30 code review 抓到过「存档没存消耗牌 ⇒ 续玩后凭空消失」,
## 债务比卡更要命 —— 丢了等于白拿 10◆。
var debt := 0


## 段末还预支 —— **只此一份**(2026-09-04 三侧复核收口)。工资入账之后调。
## 付得起 ⇒ 扣款并**清账**;付不起 ⇒ ok=false, 账不动, 由调用方判死(游戏侧 fail 屏 / RunLoop 的 mortal)。
## ⚠ 此前游戏侧扣了款**没清账**(`view/phrase.gd` 少一行 `run.debt = 0`), 一张预支在之后
## **每个**段边界都再扣一次 12◆;RunLoop 那份是清的 —— 两侧不一致, 而且 sim 量出来的
## 「advance 净负 −22.6%」还是**偏松**的那一侧。规则在 core 一份, 两边只许调它。
func repay_debt(coins_now: int) -> Dictionary:
	if debt <= 0:
		return {"ok": true, "coins": coins_now, "paid": 0, "owed": 0}
	if coins_now < debt:
		return {"ok": false, "coins": coins_now, "paid": 0, "owed": debt}
	var paid := debt
	debt = 0
	return {"ok": true, "coins": coins_now - paid, "paid": paid, "owed": 0}
## 本拍已使用的消耗牌的加成 —— 结算时并进乘法链, 拍末清空。
## 放 Run 而不是 Phrase:它由**编排器**在玩家点击时写入(经济/装槽动作只发生在编排器),
## 而 Phrase 每拍重建, 存不住「这一拍我烧过一张牌」这件事。
var phrase_boosts: Array = []
var prev_kind := -99
## 上一拍旗条件是否触发(镜面的连击谓词;与 prev_kind 同生命周期同快照)。
var prev_target_hit := false
## 掷类脸的段级明掷结果:{"sec": 段号, "worse": bool, "suit": 0..3,
## "kind": 点名指定牌型, "solved": 是否已解除}。
## 懒掷(ensure_mod_roll)于段首第一次 Beat.begin;随快照续存。
var mod_roll := {}
## 点名的解除奖励:下次商店 +1 货架位(编排器开店时消费清零;随快照续存)。
var shelf_bonus := 0
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
## ⚑⚑ **掷类脸的专用随机流(2026-09-02)** —— 它**不许碰牌堆的流**。
##
## 病根:`ensure_mod_roll()` 原本走 `deck.pick_index()`(注释写着「共享流, 探针同序」),
## 而共享流对**配对对照**恰好是毁灭性的:基准臂没有脸 ⇒ 一次都不抽;脸臂抽 1~2 次
## ⇒ 从段首起两条臂发的牌就**不是同一副**, 公共随机数(CRN)当场失效。
## 实证(09-02 全量门 score 通路的 ±SE):带 `roll_*` 参数的 4 张脸落在 **±285~301**,
## 不带的 9 张落在 **±23~212** —— **零重叠**。`callout` 效应够大(18%/32%)扛得住,
## `colorlight`(5.5%/8.9%)被噪声淹掉, 于是两条都判了「量级够但不显著」。
## ⇒ 掷骰移到这条独立流, 牌堆流两臂保持逐位对齐。
## ⚠ 段首**重新播种**(而不是顺着抽), 所以结果与「这一段之前抽过几次」无关 ——
##   免得下一个新掷类脸又把顺序打乱一遍。
## ⚠⚠ **这会让所有既有读数换基线**(牌堆流的消耗变了), 与 bot_targets 换表同性质:
##   09-02 之前的门/sim 数字与之后**不可比**。
var _roll_rng := RandomNumberGenerator.new()
var _roll_seed: int = 0
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
	reset_section_state()     # 段内状态的清单只在那一处维护
	phrase_index = 0
	joker_slots = [null, null, null, null]
	prev_kind = -99
	prev_target_hit = false
	cache_meta = {"ages": {}, "next": 0}
	previous_raw_score = 0
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
		_roll_seed = face_seed
	else:
		_blind_rng.randomize()
		_roll_rng.randomize()
		_roll_seed = int(_roll_rng.randi())
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
	run_faces = Director.roll_run(run_index, _blind_rng, face_ranking, director_ctx)
	run_boon = BlindBoon.roll(_blind_rng, director_ctx.get("boons_seen", {}))


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
		"color_mix": return Lingo.t("红黑同台")
		"face_or_ace": return Lingo.t("含 J/Q/K/A")
		"initial_cache": return Lingo.t("用初始缓存")
		"fresh_kind": return Lingo.t("更换牌型")
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
## 玩家状态 m 的切片({streak, seen}, 2026-08-19「基于 context」)。与 face_ranking
## 同一条纪律:**编排器传入, core 不偷读存档**;缺省空 = 掷法逐字节不变。
var director_ctx: Dictionary = {}


## ---- 断点续玩(2026-08-24 用户;移动 Web 刚需:iOS 内存回收重载后局面全丢)----
##
## 快照/恢复只搬**事实**(与 Tape 的口径同源:「能重放任意时刻的局面」= 这些键)。
## ⚠ 恢复**不是**开局:不掷脸、不喂 Director、不 note_run_started —— 开局三步的产物
## (run_faces / boon / 局数)全在快照里。「第二条入口漏掉主路径的步骤」是这个项目
## 最贵的形状之一, 而恢复恰恰是**故意**跳过主路径的入口, 所以它必须从快照拿全部产物。
## ⚠ 存档点恒在拍边界(发牌之前), 拍中被杀 = 这一拍从头再来(8 秒一拍, 丢不了多少);
## 商店里被杀 = 回滚到商店前那一拍(结算后商店自然重开, 购物不会凭空消失)。
func snapshot(run_index: int) -> Dictionary:
	var slots_out: Array = []
	for j in joker_slots:
		slots_out.append(null if j == null \
			else {"id": j.id, "st": j.state.duplicate(true)})
	var consumables_out: Array = []
	for c in consumables:
		consumables_out.append({"id": String(c.id), "q": int(c.queued_beats)})
	var ages_out := {}
	var ages: Dictionary = cache_meta.get("ages", {})
	for i in range(cache.size()):
		if ages.has(cache[i]):
			ages_out[str(i)] = int(ages[cache[i]])
	var kinds_out := {}
	for k in section_kinds:
		kinds_out[str(int(k))] = section_kinds[k]   # 值原样搬(集合语义 true;曲目税只数键)
	var faces_out := {}
	for k in run_faces:
		faces_out[str(int(k))] = String(run_faces[k])
	return {
		"v": 1, "run_index": run_index,
		"section_idx": section_idx, "phrase_index": phrase_index,
		"phrase_in_section": phrase_in_section, "section_score": section_score,
		"section_discards_used": section_discards_used,
		"prev_kind": prev_kind, "prev_target_hit": prev_target_hit,
		"mod_roll": mod_roll.duplicate(), "shelf_bonus": shelf_bonus,
		"first_kind": first_kind,
		"previous_raw_score": previous_raw_score, "request_last": request_last,
		"boon": run_boon, "coins": coins, "faces": faces_out,
		"kinds": kinds_out, "cache": Deck.cards_out(cache),
		"cache_ages": ages_out, "cache_next": int(cache_meta.get("next", 0)),
		"slots": slots_out, "deck": deck.snapshot(),
		# ⚑ 消耗品栏(2026-08-30 code review 补):首版**漏了** —— 玩家买了两张牌、
		# 暂停退出、续玩时它们凭空消失, 钱还白花了。⚠ `phrase_boosts` **不存**:
		# 它是拍内的, 跨存档丢失反而是对的(那一拍本来就没结算完)。
		"consumables": consumables_out, "debt": debt,
	}


## 返回 false = 快照坏了(版本不认识 / 关键键缺失), 调用方清掉它当无事发生 ——
## 与 SaveState「读失败当新玩家」同一取舍:坏档只该丢半局, 不该开不了机。
func restore(d: Dictionary) -> bool:
	if int(d.get("v", 0)) != 1 or not d.has("deck") or not d.has("faces"):
		return false
	deck = Deck.from_snapshot(d["deck"])
	cache.clear()
	for p in d.get("cache", []):
		cache.append(Card.new(int(p[0]), int(p[1])))
	cache_meta = {"ages": {}, "next": int(d.get("cache_next", 0))}
	var ages_in: Dictionary = d.get("cache_ages", {})
	for k in ages_in:
		var i := int(k)
		if i >= 0 and i < cache.size():
			cache_meta["ages"][cache[i]] = int(ages_in[k])
	joker_slots = [null, null, null, null]
	var slots_in: Array = d.get("slots", [])
	for i in range(mini(slots_in.size(), joker_slots.size())):
		var e = slots_in[i]
		if e == null:
			continue
		var j = Joker.by_id(String(e.get("id", "")))
		if j == null:
			continue          # 这张卡被退役了 —— 槽空着比开不了机好
		j.state = e.get("st", {}).duplicate(true)
		# ⚠ 不调 on_acquire:它改牌堆(百搭洗入大小王等), 而牌堆快照里已经是改完的样子
		joker_slots[i] = j
	# 消耗品栏 —— 与 slots 同款处理:认不出的 id 就空着(比开不了机好)。
	consumables = []
	debt = int(d.get("debt", 0))          # 旧档没有这个键 ⇒ 0(无债), 不需要升版
	# ⚠ 旧档存的是 `[id|null, id|null]`(2 格栏位), 新档是 `[{id, q}, …]`(待播队列)。
	# 两种都读得回来 —— 认不出的 id 就跳过, 与 slots 同款(比开不了机好)。
	for item in d.get("consumables", []):
		if item == null:
			continue
		var cid := String(item.get("id", "")) if typeof(item) == TYPE_DICTIONARY else String(item)
		for e in DB.consumables():
			if String(e["id"]) == cid:
				var c := Consumable.new(e)
				if typeof(item) == TYPE_DICTIONARY:
					c.queued_beats = int(item.get("q", 0))
				consumables.append(c)
				break
	phrase_boosts.clear()          # 拍内状态不跨存档
	run_faces = {}
	for k in d.get("faces", {}):
		run_faces[int(k)] = String(d["faces"][k])
	section_kinds = {}
	for k in d.get("kinds", {}):
		section_kinds[int(k)] = d["kinds"][k]
	section_idx = int(d.get("section_idx", 0))
	phrase_index = int(d.get("phrase_index", 0))
	phrase_in_section = int(d.get("phrase_in_section", 0))
	section_score = int(d.get("section_score", 0))
	section_discards_used = int(d.get("section_discards_used", 0))
	prev_kind = int(d.get("prev_kind", -99))
	prev_target_hit = bool(d.get("prev_target_hit", false))
	mod_roll = d.get("mod_roll", {}) if d.get("mod_roll", {}) is Dictionary else {}
	shelf_bonus = int(d.get("shelf_bonus", 0))
	first_kind = int(d.get("first_kind", -99))
	previous_raw_score = int(d.get("previous_raw_score", 0))
	request_last = String(d.get("request_last", ""))
	run_boon = String(d.get("boon", ""))
	coins = int(d.get("coins", 0))
	tutorial = false
	tutorial_step = 0
	stage = Stage.DECISION
	return true


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
## 掷类脸的开局明掷(轮盘掷严重度 / 变色灯掷花色)。懒掷:段首第一次 Beat.begin
## 调它 —— 开局/重开/转正三条入口都必经那里, 不给「第二条入口漏步骤」留缝。
## 掷一次记段号, 同段重复调是无操作。
## ⚠ RNG 走 `_roll_rng`(**专用流**, 段首重播种), **不是** `deck.pick_index` ——
## 走牌堆流会让基准臂与脸臂发的牌不同, 配对对照当场失效(理由全文见 `_roll_rng` 声明处)。
func ensure_mod_roll() -> void:
	if int(mod_roll.get("sec", -1)) == section_idx:
		return
	mod_roll = {"sec": section_idx}
	# 段首重播种:同一局同一段恒定, 且与本段之前抽过几次无关。
	_roll_rng.seed = _roll_seed + section_idx * 7919
	var m := face()
	if m == "":
		return
	var ch := SectionMod.roll_chance(m)
	if ch > 0.0:
		mod_roll["worse"] = _roll_rng.randi_range(0, 99) < int(round(ch * 100.0))
	if SectionMod.rolls_suit(m):
		mod_roll["suit"] = _roll_rng.randi_range(0, 3)
	if SectionMod.rolls_kind(m):
		# 点名的指定牌型池:构筑相关成本的四个中档型(对子太贱 = 单拍白嫖,
		# 葫芦以上太贵 = 变成硬吃;两对~同花对不同构筑贵贱不一, 正是「解还是忍」)。
		var kind_pool: Array = [Pattern.Kind.TWO_PAIR, Pattern.Kind.THREE_KIND,
			Pattern.Kind.STRAIGHT, Pattern.Kind.FLUSH]
		mod_roll["kind"] = int(kind_pool[_roll_rng.randi_range(0, kind_pool.size() - 1)])
		mod_roll["solved"] = false


static func phrase_duration_for(section: int, mod: String, phrase_idx: int = -1) -> float:
	return GameConfig.phrase_duration(section) - SectionMod.time_penalty_at(mod, phrase_idx)


func phrase_duration() -> float:
	if tutorial:
		return Tutorial.seconds(tutorial_step)
	return phrase_duration_for(section_idx, face(), phrase_in_section)


## ---- 教学关的进度 ----
##
## ⚑⚑ **步骤下标与拍数解耦(2026-08-16)** —— 从前这里全部读 `phrase_in_section`,
## 于是**一拍过去就下一步, 玩家做没做那个动作都一样**:第 3 步说「拖一张进去」,
## 不拖也照样进第 4 步。⇒ 教了不等于学会了, 而且连「有没有做」都不知道。
## 现在步骤只在**这一步要求的动作被做出来**之后才推进(外部调研的第 ② 条共识)。
var tutorial_step := 0

## 已经做出来的动作(`Tutorial.ACTIONS` 的子集)。
## ⚑ **学分制(v6, 2026-08-27)**:**跨拍累计, 不再每拍清空** —— 玩家在 A 拍就
## 弃过牌, 到弃牌门那一步门即开;推进时只**消费本步的门**, 别步的学分保留。
## (旧口径「上一拍的动作不替这一拍买单」随 v6 作废:v5 起拍末本就一律放行,
## 门的作用只剩回执与打点, 学分制让「提前会了」的玩家不再被同一句话按住重讲。)
## 每步仍展示满 1 拍(门开 = 拍末必过, 不跳课)—— 展示由编排器负责, 与账无关。
var _tutorial_acted: Dictionary = {}

## 当前这一步已经打了几拍。⚠⚠ **软门必须有兜底, 否则做不出那个动作就永远卡在同一句上。**
## 2026-08-17 真人试玩报的:「同一条提示词放了太多轮」—— 第 6 步要「手牌和缓存一起选着弃」,
## 想不到这个操作就无限重复。⚑ 我给**时钟**做了 30 秒兜底(`TUTOR_HOLD_MAX`),
## 却忘了给**步进**做 —— 同一个道理漏了一半。
## ⚑ **1 拍 = 任何教学最多一次结算都要过**(2026-08-19 用户拍板, 推翻 3 拍练习位)。
## 动作门从此只剩一个作用:**做完动作提示当场熄掉当回执**(编排器读 tutorial_pending);
## 拍末一律放行 —— 教学关的职责是让他见过, 不是把他扣在原地。
const STEP_MAX_BEATS := 1
var _tutorial_step_beats := 0


## 编排器报一个玩家动作。⚠ **只有编排器调**(view/phrase.gd)——
## 和「金币/装槽等经济动作只发生在编排器」「打点只在编排器打」同一条线:
## 组件各报各的必然报重、报漏。
func tutorial_note(action: String) -> void:
	if tutorial:
		_tutorial_acted[action] = true


## 这一拍结束时调。要求满足就推进一步并返回 `true`;没满足就靠 STEP_MAX_BEATS 兜底。
## ⚑ 学分制:动作账**跨拍累计**, 推进时只消费(erase)本步的门, 别步动作保留 ——
## 提前做过的动作到那步门即开(v6)。
func tutorial_try_advance() -> bool:
	if not tutorial:
		return false
	var need := Tutorial.require(tutorial_step)
	var ok: bool = need == "" or bool(_tutorial_acted.get(need, false))
	_tutorial_step_beats += 1
	# ⚠ 兜底:同一步打满 STEP_MAX_BEATS 拍就放行, 哪怕动作没做出来。
	# 返回值仍是**真实的**「做到没有」—— 调用方要区分「学会了」和「超时放行」时看它。
	if ok or _tutorial_step_beats >= STEP_MAX_BEATS:
		if need != "":
			_tutorial_acted.erase(need)   # 消费这一步的门;别步的学分不动
		tutorial_step += 1
		_tutorial_step_beats = 0
	return ok


## 商店分镜(最后一步, shot D)的消费口 —— 它的展示面是**商店层**, 关店即算上完:
## 不消费的话下一拍还挂着一条锚在商店里的提示条。买 Target / 「继续 ▸」两条出口
## 都由编排器调这里(判定一份真相:步进只属于 run)。
func tutorial_shop_seen() -> void:
	if tutorial and tutorial_step == Tutorial.shop_step():
		tutorial_step += 1
		_tutorial_step_beats = 0


## (拍中推进 tutorial_advance_if_done 已删 2026-08-24 —— 用户:「换一下之后立刻就跳到
## 小丑牌了, 应该等结算完了再到」。拍中做完动作只熄提示当回执(编排器 `_note_tutorial`),
## **步进只在拍末**(`tutorial_try_advance`);08-18「提示应该消失」的拍板由熄灭满足,
## 不再靠提前上下一课。)

## 这一步还欠什么动作 —— 空串 = 不欠。给编排器做「再说一次/拍中回执」的判据用。
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
## ⚠⚠ **「达标即收工」已整体退役**(2026-08-31 用户拍板:「不要提前结束的机制了。
## 我玩起来也不用」)。连带退役:`can_cash_out()` · `Economy.cashout()` · 唱片主动锁定。
## ⇒ 每一段都打满 `PHRASES_PER_SECTION` 拍, 早收只剩**被动判据**(见 `EARLY_FINISH_LEFT`)。
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
## ⚑ 用掉一张消耗牌。`ctx` = "phrase"(对局中点) | "shop"(商店里点)。
## 返回它的 `action`(要由**调用方**去执行 —— 牌堆/货架/构筑的改动各有各的家),
## `boost` 则就地并进本拍加成。用不了返回空字典。
##
## ⚠ **这里只做「取出并记账」, 不执行 action** —— core/ 是纯逻辑, 不认识货架也不碰 view。
## 商店类动作(4选2/降价/必出规则牌)由 `view/shop.gd` 消费, 牌堆类由 `Deck` 消费,
## 与 `Joker.on_acquire` 分工一致。
## 取出一张并记账(一次性:取出即销毁)。`boost` 就地并进本拍加成。
func _take(c) -> Dictionary:
	consumables.erase(c)
	if not c.boost.is_empty():
		phrase_boosts.append(c.boost)
	return {"id": c.id, "action": c.action, "boost": c.boost}


## 买下的那一刻:`buy` 类直接返回它的 action 交给调用方执行, 其余排进队列。
## ⚠ 返回空字典 = 「它排队去了, 这一刻什么也不执行」, **不是失败**。
func take_consumable(c) -> Dictionary:
	if c.is_instant():
		if not c.boost.is_empty():
			phrase_boosts.append(c.boost)
		return {"id": c.id, "action": c.action, "boost": c.boost}
	c.queued_beats = 0
	consumables.append(c)
	return {}


## 一拍开始时推进队列的年龄。**必须在 `due_consumables` 之前调一次**, 否则
## 「下一拍」永远等不到(它判的是 `queued_beats >= 1`)。
func age_consumables() -> void:
	for c in consumables:
		c.queued_beats += 1


## 这一拍轮到谁了 —— 取出并返回它们的 {id, action, boost}。`beat` 从 1 起。
## ⚠ 一拍可能同时到期多张(两枚都刻着 ④), 所以返回数组而不是单张。
func due_consumables(beat: int) -> Array:
	var out: Array = []
	for c in consumables.duplicate():
		if c.due_on(beat, c.queued_beats):
			out.append(_take(c))
	return out


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
	# 客串(2026-08-25):段寿命卡在段末计一岁, 到寿自动谢幕离场;
	# 游戏与探针共用这一个推进点(单一咬合)。顺带激活 on_section_end 钩子。
	for i in range(joker_slots.size()):
		var j = joker_slots[i]
		if j != null and j.tick_section_life():
			joker_slots[i] = null
	section_idx = mini(section_idx + 1, GameConfig.SECTIONS_PER_RUN - 1)
	reset_section_state()


## 进一段时要清的**全部**段内状态 —— 游戏(next_section)与探针(RunLoop 的段循环)共用这一份。
## 2026-08-21 外部审查:RunLoop 开新段只清了 section_score 与 first_kind, section_kinds /
## section_discards_used / request_last 跨段继承 ⇒ 曲目税、配给预算、点歌在模型里与游戏分叉
## (「规则在游戏里不在模型里」又一例)。清单只许在这里维护。
func reset_section_state() -> void:
	phrase_in_section = 0
	section_score = 0
	# the lock is per-SECTION: a new blind opens with nothing locked
	first_kind = -99
	section_discards_used = 0
	section_kinds.clear()
	request_last = ""
