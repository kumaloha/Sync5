extends SceneTree

## ⏸ **重构:本轮整块不动**(见 [TODO.md](../TODO.md) 的 R6)。
## 这五份(`formal`/`dp`/`dpcheck`/`dpdiag`/`udp`)的骨架与统计要收进 `Stat`/`Probe`,
## **解锁条件是 S3 结案** —— `dpdiag`/`dpcheck` 是 S3(通关率低估 8.4pp, 主因未定位)
## **正在用的**诊断仪器,而 S3 的下一步大概率还要改它们。
## **在仪器还在用的时候改仪器**是本项目吃过亏的形状 —— 别顺手「合并一下」。

## `design/solving.md` 的验证探针 —— 把形式化建模里**现在就能证伪的主张**跑一遍。
##   godot --headless --path . --script res://tools/formal.gd
##   SYNC5_FORMAL_ONLY=p|theta|time   只跑其中一组
##
## **为什么要有它**:上一轮的文档是**先写主张、后补证据**,于是
## `design/capability.md`(「模型的产出只有一个:分数分布」)和 `design/gates.md`
## (「目标函数不是难度,是留存」)互相打架却没人发现。这次反过来:
## **能验的先跑,结果回填文档**。
##
## 三组主张(编号对应 design/solving.md):
##   主张 7  `P` 的分量是**独立信息** —— 两两相关系数, |r|>0.9 的该合并
##   主张 8  `θ=⟨λ,τ,ε,d⟩` 足以刻画能力谱 —— 现在只有 λ 可调, 所以这一组
##           回答的是**「λ 一个人够不够」**;不够正是「要加 τ/ε」的证据
##   主张 10 时间约束真的 binding —— 交换预算 b 从 0 到 5, 最优切法的分数掉多少
##
## 口径按项目铁律:**配对(逐局共用种子)、报标准误、样本量显式**。
## ⚠ 循环骨架是薄的, 所有**转移**都走 `core/beat.gd`(design/tech.md:
## 实时与同步共用不了 `for`, 只能共用转移)。别在这里重写规则。

const K_CONFIGS := 10       # 主张 7:随机脸排布的条数
const N_P := 30             # 主张 7:每条配置的局数(×2 臂)
const N_THETA := 60         # 主张 8:每个 λ 的局数
const N_TIME := 40          # 主张 10:采样的局数
const LAMS: Array[float] = [0.0, 0.1, 0.2, 0.4]
# ⚠ 末尾那个巨大的 ε 是**极限探针**:ε→∞ 时 _noisy_argmax 退化成「在剪枝后的
# 候选里均匀随机挑」。若这个极限仍高于规则 bot, 那 bot 差的就**不是选切法的质量**,
# 而是别的维度(弃牌 / 养缓存) —— 那是一个决定性的诊断, 不是多跑一个点。
const EPSS: Array[float] = [0.0, 0.5, 1.0, 2.0, 4.0, 8.0, 64.0]

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var only := OS.get_environment("SYNC5_FORMAL_ONLY")
	print("=== design/solving.md 主张验证 ===")
	print("段数 %d × 每段 %d 拍, 缓存 %d, 手牌 %d" % [
		GameConfig.SECTIONS_PER_RUN, GameConfig.PHRASES_PER_SECTION,
		GameConfig.CACHE_CAP, GameConfig.HAND_SIZE])
	print("")
	if only == "" or only == "p":
		_claim_p()
	if only == "" or only == "theta":
		_claim_theta()
	if only == "" or only == "time":
		_claim_time()
	print("\n耗时 %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()


# ============================================================
# 主张 7:P 的分量是独立信息吗
# ============================================================
#
# 单位 = (配置 × 段)。每个单位算四个量:
#   p  通过率      Pr[段分 >= 目标]
#   Δ  技巧空间    E[带前瞻] − E[不带前瞻]      (λ=0.2 vs λ=0, 配对)
#   V  运气占比    Var_牌运 / (Var_牌运 + Var_决策)
#                  = 「这手牌好不好」相对「你怎么切」的方差占比
#                  ⚠ 这个口径比 design/gates.md 写的
#                    `Var[得分|决策已定]/Var[得分]` 更可算:56 个切法
#                    就是完整的决策空间, 不需要"固定决策再重抽"。
#   G  近失密度    Pr[ 0 <= (目标−段分)/目标 <= 0.30 ]  差一点没过的比例
#
# N(新鲜感)不进这张表:它是**外部编码**不是测出来的, 对同一配置无方差。
func _claim_p() -> void:
	print("── 主张 7:P 的分量是独立信息吗 ──")
	print("单位 = 配置 × 段, K=%d 配置 × N=%d 局 × 2 臂" % [K_CONFIGS, N_P])
	var rows: Array = []      # 每行 = [p, Δ, V, G]
	for k in range(K_CONFIGS):
		var faces := _roll_faces(9100 + k)
		var a_lam := _play_arm(faces, N_P, 3000 + k * 101, "perfect", 0.2, 0.0, true)
		var a_greedy := _play_arm(faces, N_P, 3000 + k * 101, "perfect", 0.0, 0.0, false)
		for sec in range(GameConfig.SECTIONS_PER_RUN):
			var sc_lam: Array = a_lam["sec_scores"][sec]
			var sc_gre: Array = a_greedy["sec_scores"][sec]
			var tgt := float(Run.section_target_for(
				GameConfig.SECTION_TARGETS, sec, String(faces.get(sec, ""))))
			if tgt <= 0.0:
				continue
			var p := 0.0
			var g := 0.0
			for v in sc_lam:
				if float(v) >= tgt:
					p += 1.0
				else:
					var gap := (tgt - float(v)) / tgt
					if gap <= 0.30:
						g += 1.0
			p /= float(sc_lam.size())
			g /= float(sc_lam.size())
			var delta := _mean(sc_lam) - _mean(sc_gre)
			var v_luck: float = a_lam["luck"][sec]
			rows.append([p, delta, v_luck, g])
	_print_corr(rows, ["p 通过率", "Δ 技巧空间", "V 运气占比", "G 近失密度"])


# ============================================================
# 主张 8:λ 一个人够不够刻画能力谱
# ============================================================
#
# 规则 bot 与「完美玩家在各个 λ 下」的分数分布对比。
# 若规则 bot 落在 λ 谱之外(比如比 λ=0 还低很多), 说明 λ 撑不起能力谱,
# 需要 τ(手速)和 ε(噪声)—— 那正是 design/solving.md 第二部分 主张的内容。
func _claim_theta() -> void:
	print("\n── 主张 8:λ 一个人够不够刻画能力谱 ──")
	print("N=%d 局/臂, 全部共用同一批种子(配对)" % N_THETA)
	var faces := {}
	for w in range(GameConfig.SECTIONS_PER_RUN):
		faces[w] = ""       # 无脸基准 —— 这一组只想看玩家能力, 不掺脸
	var ref: Array = _play_arm(faces, N_THETA, 7700, "adaptive")["totals"]
	var m_ref := _mean(ref)
	var sd_ref := sqrt(_var(ref))
	print("  规则 bot(adaptive)   总分 %8.0f  ±%.0f" % [m_ref, sd_ref / sqrt(float(N_THETA))])
	var best_lam := -1.0
	var best_gap := 1e18
	for lam in LAMS:
		var arm := _play_arm(faces, N_THETA, 7700, "perfect", lam)
		var tot: Array = arm["totals"]
		var pr := _paired(ref, tot)
		var m := _mean(tot)
		var z: float = pr["d"] / maxf(1e-9, pr["se"])
		var ratio := m / maxf(1.0, m_ref)
		print("  完美玩家 λ=%.2f      总分 %8.0f  vs bot 配对差 %+8.0f ±%.0f (z=%+.1f)  = bot 的 %.2f 倍"
			% [lam, m, pr["d"], pr["se"], z, ratio])
		if absf(pr["d"]) < best_gap:
			best_gap = absf(pr["d"])
			best_lam = lam
	print("  → 最接近规则 bot 的 λ = %.2f, 仍差 %.0f 分" % [best_lam, best_gap])
	print("  判据:若任何 λ 都无法逼近规则 bot, 则 λ 撑不起能力谱 → 需要 τ/ε(design/solving.md 第二部分)")

	# ── ε 扫描:能不能用噪声把完美玩家降到规则 bot 的水平 ──
	# 判据不是"降下来了"就行 —— 分数对上只是**必要**条件。
	print("  ── ε 扫描(λ 固定 0.2)──")
	for e in EPSS:
		var arm_e: Array = _play_arm(faces, N_THETA, 7700, "perfect", 0.2, e)["totals"]
		var pr_e := _paired(ref, arm_e)
		print("  λ=0.20 ε=%.1f       总分 %8.0f  vs bot 配对差 %+8.0f ±%.0f (z=%+.1f)"
			% [e, _mean(arm_e), pr_e["d"], pr_e["se"], pr_e["d"] / maxf(1e-9, pr_e["se"])])


# ============================================================
# 主张 10:时间约束真的 binding 吗
# ============================================================
#
# 一个切法要花几次交换 = 它的 5 张计分牌里有几张现在在缓存里。
# 预算 b 时只有 k<=b 的切法够得着。量:预算从 5 降到 0, 最优分掉多少。
# 现值 BEAT_SWAPS=5 >= CACHE_CAP=3, 所以 b=5 与 b=3 必须完全相同(不 binding)。
func _claim_time() -> void:
	print("\n── 主张 10:时间约束(交换预算)真的 binding 吗 ──")
	print("N=%d 局, 逐拍枚举 56 切法, 同一批牌面下比不同预算" % N_TIME)
	var cap: int = GameConfig.CACHE_CAP
	var loss := {}          # 预算 -> [每拍的分数损失]
	var reach := {}         # 预算 -> [每拍够得着的切法数]
	for b in range(cap + 1):
		loss[b] = []
		reach[b] = []
	# ⚠ GDScript 的 lambda **按值捕获局部变量** —— int 计数器在闭包里 += 不会传出来。
	# Dictionary/Array 是引用类型, 所以计数器装进 Dictionary。踩过一次才知道, 而且不报错。
	var cnt := {"beats": 0}
	var bot_t := Bot.new(_rng, Report.new(N_TIME, GameConfig.SECTIONS_PER_RUN))
	for r in range(N_TIME):
		_rng.seed = 55000 + r
		var o := RunLoop.Opts.new()
		o.rng = _rng
		o.deck_seed = r * 31 + 7
		o.player = "none"     # 不动手:量的是**牌面本身**的决策空间, 不是玩家的选择
		o.on_begin = func(run: Run, p: Phrase) -> void:
			var vis: Array = []
			vis.append_array(p.hand)
			vis.append_array(p.cache)
			if vis.size() < GameConfig.HAND_SIZE:
				return
			var extra := {
				"prev_kind": run.prev_kind, "acted_late": false,
				"discards": p.discards_used, "coins": p.coins,
				"phrase_idx": run.phrase_in_section, "mod": "", "character": run.character,
			}
			var sp := Solver.splits(vis, run.joker_slots, extra, p.deck.rules)
			if sp.is_empty():
				return
			cnt["beats"] += 1
			var best_any := -1
			var per_b := {}
			for b2 in range(cap + 1):
				per_b[b2] = -1
				reach[b2].append(0.0)
			for s in sp:
				var k := _swaps_needed(s, p.cache)
				if s.score > best_any:
					best_any = s.score
				for b3 in range(cap + 1):
					if k <= b3:
						reach[b3][reach[b3].size() - 1] += 1.0
						if s.score > per_b[b3]:
							per_b[b3] = s.score
			for b4 in range(cap + 1):
				loss[b4].append(float(best_any - int(per_b[b4])))
		RunLoop.play(o, bot_t)
	var beats: int = cnt["beats"]
	print("  共 %d 拍" % beats)
	print("  预算 b   够得着的切法   最优分损失(分/拍)   相对无约束")
	var base_score := 0.0
	for b in range(cap, -1, -1):
		var l := _mean(loss[b])
		var rr := _mean(reach[b])
		if b == cap:
			base_score = 1.0
		print("    %d      %5.1f / %d        %8.1f          %s" % [
			b, rr, 56, l, ("基准(不 binding)" if l < 0.001 else "−%.1f%%" % (l / maxf(1.0, _mean_abs_best(loss, cap)) * 100.0))])
	print("  判据:b=%d(=缓存容量)必须损失 0 —— 那正是「现在时间不 binding」的证据;" % cap)
	print("        b 更小时损失显著 > 0 → 把时间建成代价确实会改变决策(design/solving.md §2.7)")


func _mean_abs_best(loss: Dictionary, cap: int) -> float:
	# 用 b=0 的损失当尺度, 让百分比有个参照
	return maxf(1.0, _mean(loss[0])) if loss.has(0) else 1.0


## 一个切法需要几次交换:计分的 5 张里有几张此刻在缓存里。
func _swaps_needed(s, cache: Array) -> int:
	var n := 0
	for c in s.hold:
		if cache.has(c):
			n += 1
	return n


# ============================================================
# 共用:一局的薄循环。转移全部走 Beat(design/tech.md)。
# ============================================================


func _roll_faces(seed_v: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var out := {}
	for sec in range(GameConfig.SECTIONS_PER_RUN):
		var pool := SectionMod.pool_for(sec)
		if pool.is_empty():
			out[sec] = ""
		else:
			out[sec] = String(pool[r.randi_range(0, pool.size() - 1)])
	return out




## 方差分解:这一拍的 56 个切法, 均值进 between(牌运), 方差进 within(决策空间)。
func _collect_luck(run: Run, p: Phrase, mod: String, pidx: int,
		between: Array, within: Array) -> void:
	var vis: Array = []
	vis.append_array(p.hand)
	vis.append_array(p.cache)
	if vis.size() < GameConfig.HAND_SIZE:
		return
	var extra := {
		"prev_kind": run.prev_kind, "acted_late": false,
		"discards": p.discards_used, "coins": p.coins,
		"phrase_idx": pidx, "mod": mod, "character": run.character,
	}
	var sp := Solver.splits(vis, run.joker_slots, extra, p.deck.rules)
	if sp.is_empty():
		return
	var vals: Array = []
	for s in sp:
		vals.append(float(s.score))
	between.append(_mean(vals))
	within.append(_var(vals))



func _cohort() -> Dictionary:
	return {"bot": "adaptive", "target": "", "pivot": false}


## 打 n 局, 全部走共用的 `RunLoop`(一局的骨架只此一份)。
## 这一个函数取代了原先的 `_play_many` / `_play_eps` / `_play_rule_bot` **三份循环**。
## ⚠ RNG 消耗顺序与原实现逐位一致(seed → Deck.new → Character 抽取), 否则读数会整体漂移。
func _play_arm(faces: Dictionary, n: int, seed_base: int, player: String,
		lam: float = 0.0, eps: float = 0.0, want_luck: bool = false) -> Dictionary:
	var bot := Bot.new(_rng, Report.new(n, GameConfig.SECTIONS_PER_RUN))
	var totals: Array = []
	var sec_scores: Array = []
	var luck_between: Array = []
	var luck_within: Array = []
	for _s in range(GameConfig.SECTIONS_PER_RUN):
		sec_scores.append([])
		luck_between.append([])
		luck_within.append([])
	for r in range(n):
		_rng.seed = seed_base + r
		var o := RunLoop.Opts.new()
		o.rng = _rng
		o.deck_seed = r * 17 + 5
		o.faces = faces
		o.player = player
		o.lam = lam
		o.eps = eps
		o.lam_samples = int(DB.sim()["solver"]["lam_samples"])
		o.cfg = _cohort()
		if want_luck:
			# ⚠ 必须挂 on_begin(决策**之前**) —— 量的是「这一拍有多少决策空间」,
			# 挂到 on_beat 上量的是打完之后的局面, 那是另一回事。
			o.on_begin = func(run: Run, p: Phrase) -> void:
				var sec: int = run.section_idx
				_collect_luck(run, p, String(faces.get(sec, "")), run.phrase_in_section,
					luck_between[sec], luck_within[sec])
		var res := RunLoop.play(o, bot)
		totals.append(float(res["total"]))
		for sec2 in range(GameConfig.SECTIONS_PER_RUN):
			sec_scores[sec2].append(float(res["sec_scores"][sec2]))
	var luck: Array = []
	for sec3 in range(GameConfig.SECTIONS_PER_RUN):
		if want_luck and not luck_between[sec3].is_empty():
			var vb := _var(luck_between[sec3])          # 牌运:手牌之间的差异
			var vw := _mean(luck_within[sec3])          # 决策:同一手牌里切法之间的差异
			luck.append(vb / maxf(1e-9, vb + vw))
		else:
			luck.append(0.0)
	return {"totals": totals, "sec_scores": sec_scores, "luck": luck}


# ============================================================
# 统计
# ============================================================

func _print_corr(rows: Array, names: Array) -> void:
	if rows.size() < 3:
		print("  样本不足")
		return
	var m := names.size()
	var cols: Array = []
	for j in range(m):
		var c: Array = []
		for row in rows:
			c.append(float(row[j]))
		cols.append(c)
	print("  n = %d 个 (配置 × 段) 单位" % rows.size())
	print("  各分量  均值 ± 标准差:")
	for j in range(m):
		print("    %-12s %10.3f ± %.3f" % [names[j], _mean(cols[j]), sqrt(_var(cols[j]))])
	print("  两两相关系数 r (|r| > 0.9 ⇒ 该合并):")
	var worst := 0.0
	var worst_pair := ""
	for i in range(m):
		for j in range(i + 1, m):
			var r := _corr(cols[i], cols[j])
			var flag := ""
			if absf(r) > 0.9:
				flag = "  ⚠ 冗余"
			elif absf(r) > 0.7:
				flag = "  ~ 强相关"
			print("    %-12s × %-12s  r = %+.3f%s" % [names[i], names[j], r, flag])
			if absf(r) > absf(worst):
				worst = r
				worst_pair = "%s × %s" % [names[i], names[j]]
	print("  → 最强的一对:%s, r = %+.3f" % [worst_pair, worst])
	if absf(worst) > 0.9:
		print("  → 判定:**有冗余分量**, P 该降维")
	else:
		print("  → 判定:**四个分量都带独立信息**, P 是向量这条成立")


func _corr(a: Array, b: Array) -> float:
	var n: int = mini(a.size(), b.size())
	if n < 3:
		return 0.0
	var ma := _mean(a)
	var mb := _mean(b)
	var sab := 0.0
	var sa := 0.0
	var sb := 0.0
	for i in range(n):
		var da := float(a[i]) - ma
		var db := float(b[i]) - mb
		sab += da * db
		sa += da * da
		sb += db * db
	if sa <= 0.0 or sb <= 0.0:
		return 0.0
	return sab / sqrt(sa * sb)


func _paired(a: Array, b: Array) -> Dictionary:
	var n: int = mini(a.size(), b.size())
	var diffs: Array = []
	for i in range(n):
		diffs.append(float(b[i]) - float(a[i]))
	return {"d": _mean(diffs), "se": sqrt(_var(diffs) / maxf(1.0, float(n)))}


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())


func _var(a: Array) -> float:
	if a.size() < 2:
		return 0.0
	var m := _mean(a)
	var s := 0.0
	for v in a:
		s += (float(v) - m) * (float(v) - m)
	return s / float(a.size() - 1)
