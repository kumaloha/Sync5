class_name Fx
extends RefCounted

## Effect-DSL interpreter (docs/design/tech.md). Entities carry
## effects: [{when, do}] — `when` predicates AND together, `do` writes one
## settle channel. Popup strings are generated per channel, matching the
## legacy hand-written formats byte-for-byte (tests enforce it).


## (升级系统的放大参数 2026-08-26 随路线 ③ 整体删除。)
## ⚑ 结算记忆的词汇表(2026-09-04, tools/solver.gd::best_score)。求解器一拍里对同一个 5 张组合
## 反复结算, 结果只在**「这一次尝试才会变的量」**(弃了几张 / 缓存里是什么 / 换了几次 / 弃了几张人头)
## 上有差别。一张卡的 when / per / do 只要不碰这些量, 它对同一组合的结算就是同一个数, 可以记住。
## ⚠ 三张表必须**覆盖 jokers.json 里出现的每个键**(tests/t_solver 锁着):新操作码没归类 = 红,
## 不许默认「安全」—— 默认安全就是静默算错。
const TRIAL_WHEN := ["discards_eq", "discards_gte", "discard_batch_gte", "cache_mono_color",
	"cache_mono_suit", "cache_run", "cache_trio", "cache_all_faces", "swaps_eq"]
const TRIAL_PER := ["discard", "cache_face", "face_discard", "swapped_scoring"]
const TRIAL_DO := ["additive_cache_top"]
const SAFE_WHEN := ["kind", "kind_in", "same_as_prev", "diff_from_prev", "acted_late", "acted_final",
	"coins_gte", "base_gte", "last_phrase", "first_phrase", "section_eq", "section_doubled",
	"counter_gte", "chance", "target_streak", "all_suits", "no_pair", "early_discards",
	"early_finish", "top_rank_gte"]
const SAFE_PER := ["second_left", "cache_rank_sum", "hidden_scoring"]   # 另有 counter:* / coins:* 前缀
const SAFE_DO := ["mult", "mult_add", "additive", "bonus", "bonus_pct", "bonus_target_pct", "coins",
	"coins_factor", "mult_from_target_factor", "additive_face_value", "additive_low_value",
	"chips_per_card", "card_filter", "per", "cap", "step"]


## 这组效果只读**拍内常量**吗(见上表)。未归类的键一律按「不安全」处理(宁可慢, 不许错)。
static func trial_free(effects: Array) -> bool:
	for e in effects:
		for k in e.get("when", {}):
			if TRIAL_WHEN.has(String(k)) or not SAFE_WHEN.has(String(k)):
				return false
		var d: Dictionary = e.get("do", {})
		for k in d:
			if TRIAL_DO.has(String(k)) or not SAFE_DO.has(String(k)):
				return false
		if d.has("per"):
			var per := String(d["per"])
			if TRIAL_PER.has(per):
				return false
			if not SAFE_PER.has(per) and not per.begins_with("counter:") and not per.begins_with("coins:"):
				return false
	return true


static func apply_effects(effects: Array, state: Dictionary, ctx: Dictionary) -> String:
	var popup := ""
	for e in effects:
		if not _when_ok(e.get("when", {}), state, ctx):
			continue
		var text := _do(e["do"], state, ctx)
		if popup == "" and text != "":
			popup = text
	return popup


static func _when_ok(w: Dictionary, state: Dictionary, ctx: Dictionary) -> bool:
	for k in w:
		var v = w[k]
		match String(k):
			"kind":
				if int(ctx.kind) != int(Pattern.Kind[String(v)]):
					return false
			"kind_in":
				var hit := false
				for n in v:
					if int(ctx.kind) == int(Pattern.Kind[String(n)]):
						hit = true
				if not hit:
					return false
			"same_as_prev":
				if int(ctx.prev_kind) != int(ctx.kind):
					return false
			"diff_from_prev":
				if int(ctx.prev_kind) == -99 or int(ctx.prev_kind) == int(ctx.kind):
					return false
			"acted_late":
				if not bool(ctx.acted_late):
					return false
			"discards_eq":
				if int(ctx.discards) != int(v):
					return false
			"discards_gte":
				if int(ctx.discards) < int(v):
					return false
			"coins_gte":
				if int(ctx.coins) < int(v):
					return false
			"base_gte":
				if int(ctx.base_score) < int(v):
					return false
			"last_phrase":
				if int(ctx.get("phrase_idx", -1)) != GameConfig.PHRASES_PER_SECTION - 1:
					return false
			"cache_mono_color":
				# 低频卡族放宽(2026-08-26 用户拍板「改条件放宽」):全同花(4-5%)→
				# 全同色(红/黑, 先验 ≈25%)。和弦/和声共用;万能牌不计色(与同花版同口径)。
				var mc_cards: Array = ctx.get("cache_cards", [])
				if mc_cards.is_empty():
					return false
				var colors := {}
				for c in mc_cards:
					if not c.is_wild():
						colors[c.is_red()] = true
				if colors.size() != 1:
					return false
			"cache_mono_suit":
				var cards: Array = ctx.get("cache_cards", [])
				if cards.is_empty():
					return false
				var suits := {}
				for c in cards:
					if not c.is_wild():
						suits[c.suit] = true
				if suits.size() > 1:
					return false
			"top_rank_gte":
				var top := 0
				for c in ctx.get("scoring_cards", []):
					top = maxi(top, int(c.rank))
				if top < int(v):
					return false
			"counter_gte":
				if float(state.get(String(v[0]), 0.0)) < float(v[1]):
					return false
			"first_phrase":
				if int(ctx.get("phrase_idx", -1)) != 0:
					return false
			"section_eq":
				if int(ctx.get("section_idx", -1)) != int(v):
					return false
			"early_finish":
				if not bool(ctx.get("early_finish", false)):
					return false
			"chance":
				# 赌具(2026-08-25):掷点在 Beat 预掷(共享 RNG 纪律), 结算保持纯函数。
				# 无掷点上下文(直调 Settle 的测试 / kit 局部)= 永不触发, 基线确定。
				# 灌铅骰的 odds_mult 乘在阈值上(1/4 → 1/2), 封顶 1。
				var lucks: Array = ctx.get("luck_rolls", [])
				if lucks.is_empty():
					return false
				var rv: float = float(lucks.pop_front())
				var need: float = minf(1.0, float(v) * float(ctx.get("odds_mult", 1.0)))
				if rv >= need:
					return false
			"target_streak":
				# 镜面改造(2026-08-25, versus.md):连续两拍达成旗条件才生效 ——
				# 本拍旗已触发(支援在旗之后评估, target_factor 已定)且上一拍也触发过
				# (prev_target_hit 由 Run 维护, 与 prev_kind 同生命周期)。
				# 必买卡从此要「玩出来」, 且第一次对禁回/炒冷饭类脸敏感。
				if float(ctx.get("target_factor", 1.0)) <= 1.0:
					return false
				if not bool(ctx.get("prev_target_hit", false)):
					return false
			"acted_final":
				if not bool(ctx.get("acted_final", false)):
					return false
			"early_discards":
				# 早弃:本拍**弃过牌**且最后一次弃牌在早锁线之前。
				# ⚠ 没弃过牌不算 —— 否则「整拍不动手」白拿, 那是挂机(A4)。
				if not bool(ctx.get("early_discards", false)):
					return false
			"swaps_eq":
				if int(ctx.get("swaps", 0)) != int(v):
					return false
			"discard_batch_gte":
				if int(ctx.get("discard_batch_max", 0)) < int(v):
					return false
			"section_doubled":
				# 打包 doggybag:结算开始时段分已 ≥ 2×目标(悲观口径 —— 本拍自身的分
				# 在链上还没定, 循环依赖;翻倍后的每一拍持续付, 奖励「超标后继续打」)。
				var sd_target := int(ctx.get("section_target", 0))
				if sd_target <= 0 or int(ctx.get("section_score", 0)) < sd_target * 2:
					return false
			"all_suits":
				var seen_suits := {}
				for c in ctx.get("scoring_cards", []):
					if not c.is_wild():
						seen_suits[c.suit] = true
				if seen_suits.size() < 4:
					return false
			"no_pair":
				var seen_ranks := {}
				for c in ctx.get("scoring_cards", []):
					if c.is_wild():
						continue
					if seen_ranks.has(c.rank):
						return false
					seen_ranks[c.rank] = true
			"cache_all_faces":
				var cc: Array = ctx.get("cache_cards", [])
				if cc.is_empty():
					return false
				for c in cc:
					if not c.is_wild() and (c.rank < 11 or c.rank > 13):
						return false
			"cache_run":
				var run_ranks := []
				for c in ctx.get("cache_cards", []):
					if not c.is_wild():
						run_ranks.append(int(c.rank))
				if run_ranks.size() < 3:
					return false
				run_ranks.sort()
				for i in range(1, run_ranks.size()):
					if run_ranks[i] != run_ranks[i - 1] + 1:
						return false
			"cache_trio":
				var trio_ranks := []
				for c in ctx.get("cache_cards", []):
					if not c.is_wild():
						trio_ranks.append(int(c.rank))
				if trio_ranks.size() < 3:
					return false
				for r in trio_ranks:
					if r != trio_ranks[0]:
						return false
			_:
				push_error("[Fx] unknown predicate '%s'" % k)
				return false
	return true


## Count multiplier from `per` / `step`.
static func _count(d: Dictionary, state: Dictionary, ctx: Dictionary) -> float:
	var per := String(d.get("per", ""))
	var c := 1.0
	if per == "discard":
		c = float(int(ctx.discards))
	elif per == "cache_face":
		# 缓存区人头牌张数(包厢 Box Seats,Baron 的缓存直译;J/Q/K = 11..13)。
		var nf := 0
		for cc in ctx.get("cache_cards", []):
			if not cc.is_wild() and cc.rank >= 11 and cc.rank <= 13:
				nf += 1
		c = float(nf)
	elif per == "second_left":
		# 秒表:锁定时**每剩一秒**。整秒向下取(玩家读的是秒表上的整数)。
		c = floorf(maxf(0.0, float(ctx.get("seconds_left", 0.0))))
	elif per == "face_discard":
		c = float(int(ctx.get("faces_discarded", 0)))
	elif per == "swapped_scoring":
		c = float(int(ctx.get("swapped_scoring", 0)))
	elif per.begins_with("counter:"):
		c = float(state.get(per.substr(8), 0.0))
	elif per == "cache_rank_sum":
		c = float(ctx.get("cache_rank_sum", 0))
	elif per == "hidden_scoring":
		c = float(ctx.get("hidden_scoring", 0))
	elif per.begins_with("coins:"):
		@warning_ignore("integer_division")
		c = float(int(ctx.coins) / int(per.substr(6)))
	if d.has("step"):
		@warning_ignore("integer_division")
		c = float(int(c) / int(d["step"]))
	return c


static func _do(d: Dictionary, state: Dictionary, ctx: Dictionary) -> String:
	# escape-hatch opcodes first (docs/design/tech.md: the irreducible two)
	if d.has("mult_from_target_factor"):
		var tf: float = float(ctx.get("target_factor", 1.0))
		if tf > 1.0:
			var mf: float = 1.0 + (tf - 1.0) * float(d["mult_from_target_factor"])
			ctx.mult *= mf
			return "×%.1f" % mf
		return ""
	if d.has("additive_face_value"):
		var val := int(d["additive_face_value"])
		var boost := 0
		for c in ctx.get("scoring_cards", []):
			if c.rank >= 11 and c.rank <= 13:
				boost += val - c.rank
		if boost > 0:
			ctx.additive += boost
			return "+%d" % boost
		return ""
	# additive_face_value 的镜像:小牌(2..5)按 val 计 chips —— 低牌路的规则卡。
	if d.has("additive_low_value"):
		var lval := int(d["additive_low_value"])
		var lboost := 0
		for c in ctx.get("scoring_cards", []):
			if not c.is_wild() and c.rank >= 2 and c.rank <= 5:
				lboost += lval - c.rank
		if lboost > 0:
			ctx.additive += lboost
			return "+%d" % lboost
		return ""
	# 牌型金币的倍增器(分成 royalty)。乘的是**牌型自带的金币**, 不乘其他卡给的
	# coins_bonus —— 结算式:coins = round(牌型金币 × factor) + Σcoins_bonus(Settle 收口)。
	if d.has("coins_factor"):
		ctx.coins_factor = float(ctx.get("coins_factor", 1.0)) * float(d["coins_factor"])
		# ⚠ **不能用 %d** —— `int(1.5)` = 1, 分成从 ×2 改成 ×1.5 后浮标会显示
		# 「◆×1」, 卡在屏幕上说自己什么也没做(2026-08-30 code review)。
		return "◆×%s" % _fmt_factor(float(d["coins_factor"]))
	# 缓存区点数最高的一张按点数计 chips(替补 Bench,Splash 的缓存直译)。
	# 走 additive 通道吃全部倍率;值是倍数(1 = 原点数),留给调价用。
	if d.has("additive_cache_top"):
		var ctop := 0
		for c in ctx.get("cache_cards", []):
			if not c.is_wild():
				ctop = maxi(ctop, int(c.rank))
		ctop *= int(d["additive_cache_top"])
		if ctop > 0:
			ctx.additive += ctop
			return "+%d" % ctop
		return ""
	# 记分牌逐张过滤加 chips(走 additive 通道,吃全部倍率 —— B1:早抽才值钱)。
	# 一个操作码解锁整个牌面族(红/黑/低段), filter 值由 db.gd 校验。
	if d.has("chips_per_card"):
		var per_card := int(d["chips_per_card"])
		var filt := String(d.get("card_filter", ""))
		var hits := 0
		for c in ctx.get("scoring_cards", []):
			if c.is_wild():
				continue
			var hit := false
			match filt:
				"red": hit = c.is_red()
				"black": hit = not c.is_red()
				"rank_lte_5": hit = c.rank <= 5
				_: push_error("[Fx] unknown card_filter '%s'" % filt)
			if hit:
				hits += 1
		if hits > 0:
			var add := per_card * hits
			ctx.additive += add
			return "+%d" % add
		return ""

	var cnt := _count(d, state, ctx)
	if cnt <= 0.0:
		return ""
	for ch in ["mult", "mult_add", "additive", "bonus", "bonus_target_pct", "bonus_pct", "coins"]:
		if not d.has(ch):
			continue
		var raw = d[ch]
		var amt: float = float(state.get(String(raw["counter"]), 0.0)) if raw is Dictionary \
			else float(raw)
		var contrib: float = amt * cnt
		if d.has("cap"):
			contrib = minf(contrib, float(d["cap"]))
		match ch:
			"mult":
				ctx.mult *= contrib
				return ("×%d" % int(round(contrib))) if absf(contrib - roundf(contrib)) < 0.001 \
					else ("×%.1f" % contrib)
			"mult_add":
				var f: float = 1.0 + contrib
				ctx.mult *= f
				return "×%.2f" % f
			"additive":
				if int(round(contrib)) == 0:
					return ""
				ctx.additive += int(round(contrib))
				return "+%d" % int(round(contrib))
			"bonus":
				ctx.bonus += int(round(contrib))
				return "+%d" % int(round(contrib))
			"bonus_target_pct":
				# ⚑⚑ **奖励分跟着尺度走**(2026-08-16, 加分族 A 案)——
				# 数额 = 本段**每拍**目标 × pct, 而不是一个固定数。
				# 起因:S1→S4 每拍需求 70 → 933 = **13.3 倍跨度**, 固定数在两头只能选一头 ——
				# 调到 S4 够用就在 S1 打穿, 调到 S1 合理在 S4 只剩 +3%。**没有任何固定数成立。**
				# ⚠ 它仍落在 `ctx.bonus`(乘法链**之后**), 身份不变:**保底, 不是放大**。
				# ⚠⚠ `section_target` 缺失时**响一声**, 不静默给 0 —— 三个探针曾经就没传它,
				# 那会让这一族在仪器里测出 0 = 自我实现的错误结论(见 LESSONS 三)。
				# ⚠⚠ **缺 `section_target` 时退回「一局的平均每拍目标」, 不返回 0。**
				# 第一版是 `push_error` + 返回 0, 两个后果都很糟:
				#   ① **这族卡在模型里隐身** —— 求解器给它们估值 0, bot 永远不买
				#      (`t_draft.gd` 的 SOLVER_BLIND 断言当场抓到);
				#   ② 单测日志刷出 **120 万行** ERROR —— 求解器的 ctx 由调用方组, 漏传的路径太多。
				# ⇒ 「所有路径都必须传」这个要求不现实, 而**近似值远好过隐身**:
				# 游戏与 Beat 路径始终传真值(精确), 求解器的假想局面用全局平均(粗但不为零)。
				# ⚑ 与 `tools/bot.gd::_avg_beat_target()` **同一个基准**, 两处都从
				# `SECTION_TARGETS` 推导 —— 目标分一改两边一起动, 不会漂开。
				var st: int = int(ctx.get("section_target", 0))
				var per_beat: float = 0.0
				if st > 0:
					per_beat = float(st) / float(GameConfig.PHRASES_PER_SECTION)
				else:
					var tot := 0.0
					for v in GameConfig.SECTION_TARGETS:
						tot += float(v)
					var n := float(GameConfig.SECTION_TARGETS.size())
					if n > 0.0:
						per_beat = tot / n / float(GameConfig.PHRASES_PER_SECTION)
				var amt_pts: int = int(round(per_beat * contrib))
				if amt_pts == 0:
					return ""
				ctx.bonus += amt_pts
				return "+%d" % amt_pts
			"bonus_pct":
				if contrib < 0.001:
					return ""
				ctx.bonus_pct += contrib
				return "+%d%%" % int(round(contrib * 100.0))
			"coins":
				if int(round(contrib)) == 0:
					return ""
				ctx.coins_bonus += int(round(contrib))
				return "+%d◆" % int(round(contrib))
	push_error("[Fx] do has no known channel: %s" % str(d))
	return ""


## ---- Counter feeding (replaces the hand-written growth hooks) ----

static func init_state(counters: Dictionary) -> Dictionary:
	var st: Dictionary = {}
	for cname in counters:
		if counters[cname].has("init"):
			st[cname] = float(counters[cname]["init"])
	return st


static func on_discard(counters: Dictionary, state: Dictionary, n: int) -> void:
	if n <= 0:
		return
	for cname in counters:
		if String(counters[cname].get("on_discard", "")) == "sum":
			state[cname] = float(state.get(cname, 0.0)) + float(n)


## 商店事件喂计数器(2026-08-13 子波 3)。`kind` = "reroll" | "buy" | "target_swap"。
##
## ⚠ **为什么值得开第七个钩子**(D1 门要硬理由):A4 要求成长只挂**有代价的动作**,
## 而商店动作(刷新付钱 / 买卡付钱 / 换旗弃掉旧旗)是**唯一一整片没有钩子覆盖的
## 动作空间** —— 既有六个钩子全在对局内。三张已定稿的卡(淘碟/收藏家/转型)都要它,
## 且它们的代价天然真实(钱), 不需要额外设计一个人造成本。
static func on_shop_event(counters: Dictionary, state: Dictionary, kind: String) -> void:
	var key := "on_" + kind
	for cname in counters:
		var spec: Dictionary = counters[cname]
		if spec.has(key):
			state[cname] = float(state.get(cname, 0.0)) + float(spec[key])


static func on_phrase_end(counters: Dictionary, state: Dictionary, x: Dictionary) -> void:
	for cname in counters:
		var spec: Dictionary = counters[cname]
		if spec.has("on_early_finish") and bool(x.get("early_finish", false)):
			state[cname] = float(state.get(cname, 0.0)) + float(spec["on_early_finish"])
		# 脉冲计数器(定格 freeze):早锁 → 下一拍置 1, 否则归 0 —— 只活一拍,
		# 与 on_early_finish 的「永久累加」(惯性)是同一事件的两种时间形状。
		if spec.has("pulse_on_early_finish"):
			state[cname] = 1.0 if bool(x.get("early_finish", false)) else 0.0
		if spec.has("decay_per_phrase"):
			state[cname] = maxf(float(spec.get("floor", 0.0)),
				float(state.get(cname, 0.0)) - float(spec["decay_per_phrase"]))


## 倍数的显示:整数不带小数点(×2), 非整数保留一位(×1.5)。
static func _fmt_factor(v: float) -> String:
	return "%d" % int(v) if absf(v - roundf(v)) < 0.01 else "%.1f" % v
