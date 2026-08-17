class_name Beat
extends RefCounted

## 一拍的编排 —— **游戏和模型共用的那一份**(docs/design/tech.md)。
##
## `core/` 铁律照旧:引擎无关、不含时钟、不 import view。
##
## ## 为什么有这个文件
##
## 计分(`Pattern` + `Settle`)一直只有一份 —— 那是 `agree.gd` 退役时刻意做到的。
## 但**「一拍怎么走完」曾经被写了六遍**(`view/phrase.gd` + sim/curve/coin/blind/gate),
## 于是每加一条规则都要在六个地方各写一次, 漏一个就**静默分叉**。
## 五次「规则在游戏里、不在模型里」的事故里有三次直接出自这里:
##   · 赶场 −2s   —— 一拍时长的表达式两份, 模型那份当时不含时间维度
##   · cover 入场费 —— 扣钱五份, 我在求解器里找不到通路就下了结论(实测 −518 分)
##   · raisedbar  —— 段目标两份, `sim.gd` 那份漏乘 `target_mult`, 模型里整张脸是空气
##
## ## 为什么不是一个共用的 `for` 循环
##
## 游戏是**实时异步**的(8 秒钟 + tween + 玩家输入, 中间要 await), 探针是**同步**的。
## 所以共用不了循环, 只能共用**转移**:游戏从时钟回调里按顺序调, 探针连着调。
##
## ## ⚠ 光"提供共用函数"拦不住任何人再写一遍
##
## `sim.gd` 漏乘 `target_mult` 那次, `Run.target()` 就摆在旁边。所以这里记 `Run.stage`,
## **漏步直接拒绝执行**(`_expect` 返回 false, 调用方早退)——
## 把"忘记"从静默变成**一次响亮的失败**。
## ⚠ 这里曾经写着「漏步直接 push_error —— 把忘记从静默变成崩溃」,**那句话是假的**:
## `push_error` 不中断执行。2026-08-09 由外部审查发现并改成真正的 fail-closed。


## 开一拍:解析这一段的脸 → 发牌 → 收入场费。返回一个「可以开始做决定」的 `Phrase`。
##
## ⚠ **脸必须在 `start()` 之前定下来** —— 缓存容量(smallstage)是在 `start()` 里生效的,
## 之后再解析会让**段首那一拍用上一段的脸**算容量。这是 2026-08-07 在 `view/phrase.gd`
## 修过的一个真 bug, 现在它只可能在这一个地方发生。
## ⚠ **入场费(cover)曾经被抄了五份** —— 而我一度断言它「对完美玩家零效果」并退役了它,
## 实测是每局 −518.1 分 ±123(z=−4.21), 伤害 98% 走商店。现在只有这一处扣钱。
##
## 金币的口径:`run.coins` 是**拍与拍之间**的携带量, 一拍之内归 `Phrase` 管
## (弃牌与入场费都在那里扣)。调用方在开拍前把最新的钱写回 `run.coins` 即可 ——
## 游戏里商店会在两拍之间动钱, 所以那一步不能省。
static func begin(run: Run) -> Phrase:
	var mod := run.face()
	var p := Phrase.new(run.deck, run.cache, run.coins)
	p.mod = mod                        # ⚠ 必须在 start() 之前
	p.boon = run.boon()
	p.cache_meta = run.cache_meta
	var section_budget := SectionMod.section_discard_budget(mod)
	if section_budget >= 0:
		p.discard_budget = maxi(0, section_budget - run.section_discards_used)
	if SectionMod.request_factor(mod) < 1.0:
		p.request_prev_kind = run.prev_kind
	p.start()
	if SectionMod.request_factor(mod) < 1.0:
		p.request_goal = run.next_request_goal(p)
		p.request_met = p.request_goal == ""
	var toll := SectionMod.phrase_toll(mod)
	if toll > 0:
		p.coins = maxi(0, p.coins - toll)
	run.coins = p.coins
	run.phrase_index += 1
	run.stage = Run.Stage.DECISION
	return p


## 结算这一拍:锁定 → 组 ctx → `Settle.run` → 记 first/prev 牌型 → 金币与段分入账。
##
## ⚠ **`first_kind` 必须在 `Settle.run` 之后才更新** —— setlist(定调)锁的是
## 「本段第一拍打的牌型」, 而第一拍自己不受锁约束。先更新就把锁套在了它自己头上。
## ⚠ ctx 的 `mod` 走 `run.face()`, 不许调用方自己传:调用方各传各的正是分叉的入口。
##
## 返回 `Settle.run` 的 outcome, 外加 `res`(牌型/chips/resolved —— 打点和报表要读)。
static func settle(run: Run, p: Phrase, flags: Dictionary = {}) -> Dictionary:
	# ⚠ fail-closed:stage 不对就**什么都不做**。返回空字典而不是半个 outcome ——
	# 调用方读 `outcome["score"]` 会立刻炸, 那正是要的:响亮地失败, 而不是静默双重记账。
	if not _expect(run, Run.Stage.DECISION, "settle"):
		return {}
	var res := p.lock_and_settle()
	run.section_kinds[int(res.get("kind", -99))] = true
	var outcome := Settle.run(res, run.joker_slots, {
		"prev_kind": run.prev_kind,
		"acted_late": bool(flags.get("late", false)),
		"discards": p.discards_used,
		"coins": p.coins,
		"phrase_idx": run.phrase_in_section,
		"cache_cards": run.cache,
		"early_finish": bool(flags.get("early", false)),
		# ---- 2026-08-13 子波 2:时钟观测(谢幕/秒表/早弃)。**全部由调用方传** ——
		# core/ 不含时钟, 这里只是把 view/探针给的读数放进 ctx(late/early 的同款处理)。
		"acted_final": bool(flags.get("final", false)),
		"seconds_left": float(flags.get("secs_left", 0.0)),
		"early_discards": bool(flags.get("early_discards", false)),
		"section_idx": run.section_idx,
		# ---- 2026-08-13 子波1 信号(拼 ctx 只此一处, 分叉无从发生) ----
		"swaps": p.swap_actions_used,
		"discard_batch_max": p.discard_batch_max,
		"faces_discarded": p.faces_discarded,
		"swapped_scoring": p.swapped_scoring_count(res.get("resolved", [])),
		"section_score": run.section_score,
		"section_target": run.target(),
		"mod": run.face(),
		"character": run.character,
		"first_kind": run.first_kind,
		"request_met": p.request_met,
		"patch_restored": SectionMod.restores_with_initial_cache(run.face()) \
			and p.has_initial_cache_in_hand(),
	})
	var raw_score := int(outcome["score"])
	var boon_bonus := 0
	var replay_factor := BlindBoon.score_replay_factor(run.boon())
	if replay_factor > 0.0:
		boon_bonus += int(round(float(raw_score) * replay_factor))
	var previous_factor := BlindBoon.previous_raw_factor(run.boon())
	if previous_factor > 0.0:
		boon_bonus += int(round(float(run.previous_raw_score) * previous_factor))
	outcome["raw_score"] = raw_score
	outcome["boon_bonus"] = boon_bonus
	outcome["score"] = raw_score + boon_bonus
	# ---- 局外乘子(券 boost)· 2026-08-17 ----
	# ⚑ 券不进模型:探针拿不到券(SaveState 的探针闸), 也就永远不传这个 flag ——
	# 缺省 1.0 = 全部既有调用方逐字节不变。放在 boon 之后:它是**局外浮层**,
	# 吃完整的拍分;raw_score 保持不动(复读/回放读的是无浮层的原始分)。
	# ⚠ 记分必须留在这里而不是 view —— 「判生死只有一份」的同一条线:
	# view 自己乘再加回 section_score, 就是第二份记分。
	var meta_mult := float(flags.get("meta_mult", 1.0))
	if meta_mult != 1.0:
		var meta_bonus := int(round(float(outcome["score"]) * (meta_mult - 1.0)))
		outcome["meta_bonus"] = meta_bonus
		outcome["score"] = int(outcome["score"]) + meta_bonus
	run.previous_raw_score = raw_score
	if run.phrase_in_section == 0:
		run.first_kind = int(res.get("kind", -99))
	run.prev_kind = int(res.get("kind", -99))
	p.coins = Economy.grant(p.coins, int(outcome["coins"]), run.joker_slots)
	run.coins = p.coins
	if SectionMod.section_discard_budget(run.face()) >= 0:
		run.section_discards_used += p.discards_used
	run.section_score += int(outcome["score"])
	run.stage = Run.Stage.SETTLED
	outcome["res"] = res
	return outcome


## 一拍收尾:缓存驱逐(lostpage/freshsheet 在 `Phrase.cleanup()` 里)+ 小丑牌成长钩子。
##
## ⚠ 顺序不能换:`cleanup()` 先跑, 因为成长钩子里有读缓存的牌。游戏侧
## (`view/phrase.gd::_advance`)和全部探针本来就是这个顺序, 这里把它固定下来。
static func phrase_end(run: Run, p: Phrase, flags: Dictionary = {}) -> void:
	if not _expect(run, Run.Stage.SETTLED, "phrase_end"):
		return                    # ⚠ fail-closed:成长钩子绝不能跑第二次
	p.cleanup()
	for j in run.joker_slots:
		if j != null:
			j.on_phrase_end({"early_finish": bool(flags.get("early", false))})
	run.stage = Run.Stage.ENDED


## 漏步 = **拒绝执行**, 这是本文件存在的理由的一半。只提供共用函数是拦不住"再写一遍"的。
##
## ⚠⚠ **2026-08-09 修的真缺陷:此前它只 `push_error` 就返回, 而
## `push_error` 在 Godot 里根本不中断执行** —— 调用方照旧往下跑。后果是
## 重复 `settle()` 会**再结算一次**(金币与段分第二次入账, 而 `lock_and_settle()`
## 对重复调用返回缓存结果, 所以第二次的输入完整、看不出异常),
## 乱序 `phrase_end()` 会**再触发一次成长钩子**。
## 那时本文件顶部和 `LESSONS.md` 都写着「漏步会崩」—— **那句话是假的, 机制从未生效过**。
##
## 现在返回 `bool`, 调用方**必须早退**(fail-closed):宁可这一拍不发生,
## 也不许它发生两次 —— 静默的双重记账比缺一拍难查一个量级。
## ⚠ 不用 `assert()`:它只在 debug 构建里中断, 而且会让「重复调用」的负向测试整个中止。
static func _expect(run: Run, want: int, who: String) -> bool:
	if run.stage == want:
		return true
	push_error("[Beat] %s() 在 stage=%d 时被调用, 期望 %d —— 有一步被跳过了, 本次调用已拒绝"
		% [who, run.stage, want])
	return false
