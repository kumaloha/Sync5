extends SceneTree

## ⏸ **重构:本轮整块不动**(见 [TODO.md](../TODO.md) 的 R6)。
## 这五份(`formal`/`dp`/`dpcheck`/`dpdiag`/`udp`)的骨架与统计要收进 `Stat`/`Probe`,
## **解锁条件是 S3 结案** —— 本文件与 `dpcheck` 是 S3(通关率低估 8.4pp, 主因未定位)
## **正在用的**诊断仪器,而 S3 的下一步大概率还要改它们。
## **在仪器还在用的时候改仪器**是本项目吃过亏的形状 —— 别顺手「合并一下」。

## **诊断:构筑档内还缺哪一维**(design/solving_history.md 之后)。
##   godot --headless --path . --script res://tools/dpdiag.gd
##
## ## 问题
##
## DP 的通关率系统性低估 −0.084。已排掉两块(段内卷积、幸存者过滤), 剩下的
## 定位到「**构筑档 `b` 的分辨率不够**」—— 同一档里有人达标有人不达标,
## 而达标的那些「在档内更强」, 这个未捕获的差异每经过一次段间转移就累积一次。
##
## ## 这个探针问两个问题, 而且它们指向**不同的修法**
##
##   ① 档内, 达标组 vs 未达标组的**构筑评分**差多少?
##      → 差得明显 = **加档数就够**(b 这个维度是对的, 只是切得太粗)
##
##   ② 档内, 达标组 vs 未达标组的**缓存效果**(cache_value 的均值/方差)差多少?
##      → 差得明显 = **需要加 `c` 这一维**(b 捕获不了的信息在缓存里)
##
## ⚠ **两个都要量, 因为它们的修法完全不同**, 而且成本差一个量级:
## 加档数几乎免费, 加维度要把局数提到 2000+(一轮验证 25 分钟 → 2 小时)。
##
## 判据用 **Cohen's d**(标准化效应量), 不用 p 值 —— 样本量是自己定的,
## 只看显著性等于让判据跟着预算走(本项目铁律)。
##   |d| < 0.2  可忽略      0.2~0.5 小      0.5~0.8 中     > 0.8 大

const N_RUNS := 300
const BANDS := 4
const CACHE_SAMPLES := 8      # 估缓存效果的均值/方差用几组补牌

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var nsec: int = GameConfig.SECTIONS_PER_RUN
	var targets: Array = []
	for n in range(nsec):
		targets.append(float(Run.section_target_for(GameConfig.SECTION_TARGETS, n, "")))
	print("=== 诊断:构筑档内还缺哪一维 ===")
	print("N=%d 局(不死局) · %d 档 · 缓存效果采样 %d 组" % [N_RUNS, BANDS, CACHE_SAMPLES])

	# rows: 每条 = {n, strength, cmean, cstd, sec_score, alive}
	var rows: Array = []
	var bot := Bot.new(_rng, Report.new(N_RUNS, nsec))
	var lam: float = float(DB.sim()["solver"]["lam"])
	var lsamp: int = int(DB.sim()["solver"]["lam_samples"])
	var faces := {}
	for w in range(nsec):
		faces[w] = ""
	for r in range(N_RUNS):
		_rng.seed = 52000 + r
		var mine: Array = []
		var o := RunLoop.Opts.new()
		o.rng = _rng
		o.deck_seed = r * 17 + 5
		o.faces = faces
		o.player = "perfect"
		o.lam = lam
		o.lam_samples = lsamp
		o.cfg = {"bot": "perfect", "target": "", "pivot": false}
		o.shop = true
		o.mortal = false
		o.on_begin = func(run: Run, p: Phrase) -> void:
			if run.phrase_in_section != 0:
				return
			var st := _cache_stats(run, p, 770000 + r)
			mine.append({
				"n": run.section_idx,
				"strength": Draft._forward(run, null, -1, 660000 + r, 6, lam, lsamp),
				"cmean": st["mean"], "cstd": st["std"],
			})
		var res := RunLoop.play(o, bot)
		for i in range(mine.size()):
			var e: Dictionary = mine[i]
			var n: int = int(e["n"])
			e["sec"] = float((res["sec_scores"] as Array)[n])
			e["pass"] = float(e["sec"]) >= float(targets[n])
			rows.append(e)

	# 分档(全体强度的分位数)
	var all_s: Array = []
	for e in rows:
		all_s.append(float(e["strength"]))
	all_s.sort()
	var cuts: Array = []
	for i in range(1, BANDS):
		cuts.append(float(all_s[clampi(int(float(i) * float(all_s.size()) / float(BANDS)),
			0, all_s.size() - 1)]))
	print("  档分界 %s\n" % str(cuts))

	print("  档  n(过/没过)   构筑评分 d     缓存均值 d     缓存方差 d")
	var agg := {"s": [], "m": [], "v": []}
	for b in range(BANDS):
		var ps: Array = []
		var pm: Array = []
		var pv: Array = []
		var fs: Array = []
		var fm: Array = []
		var fv: Array = []
		for e in rows:
			if _band_of(float(e["strength"]), cuts) != b:
				continue
			if bool(e["pass"]):
				ps.append(float(e["strength"]))
				pm.append(float(e["cmean"]))
				pv.append(float(e["cstd"]))
			else:
				fs.append(float(e["strength"]))
				fm.append(float(e["cmean"]))
				fv.append(float(e["cstd"]))
		if ps.size() < 5 or fs.size() < 5:
			print("    %d  %3d/%3d       —— 样本不足, 跳过" % [b, ps.size(), fs.size()])
			continue
		var ds := _cohen(ps, fs)
		var dm := _cohen(pm, fm)
		var dv := _cohen(pv, fv)
		agg["s"].append(ds)
		agg["m"].append(dm)
		agg["v"].append(dv)
		print("    %d  %3d/%3d       %+7.3f %-6s %+7.3f %-6s %+7.3f %s"
			% [b, ps.size(), fs.size(), ds, _tag(ds), dm, _tag(dm), dv, _tag(dv)])

	print("\n  ── 判读 ──")
	print("    构筑评分 |d| 均值 %.3f  → 大 = **加档数就够**(b 这维对, 切得太粗)"
		% _absmean(agg["s"]))
	print("    缓存均值 |d| 均值 %.3f  → 大 = **需要加 c 这一维**" % _absmean(agg["m"]))
	print("    缓存方差 |d| 均值 %.3f  → 大 = 方差那一维也要(阈值决策对它敏感)"
		% _absmean(agg["v"]))
	print("\n耗时 %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()


## 段首缓存的效果:对若干组补牌算「这手缓存 + 5 张新牌」能打多少, 取均值与标准差。
## ⚠ 方差不是可选的:我们的目标是**达标**(阈值决策), 而阈值决策对方差极其敏感
## —— 稳过时要低方差, 要赌时要高方差。期望相同、形状不同的两手缓存打法不同。
func _cache_stats(run: Run, p: Phrase, seed_v: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var vals: Array = []
	var extra := {
		"prev_kind": -99, "acted_late": false, "discards": 0, "coins": 99,
		"phrase_idx": 0, "mod": "", "character": run.character,
	}
	for _i in range(CACHE_SAMPLES):
		var f: Array = p.deck.peek_many(rng, GameConfig.HAND_SIZE)
		if f.size() < GameConfig.HAND_SIZE:
			continue
		var trial: Array = run.cache.duplicate()
		trial.append_array(f)
		if trial.size() < GameConfig.HAND_SIZE:
			continue
		vals.append(float(Solver.best_score(trial, run.joker_slots, extra, p.deck.rules)))
	return {"mean": _mean(vals), "std": sqrt(_var(vals))}


## Cohen's d —— 标准化效应量。⚠ 不用 p 值:样本量是自己定的,
## 只看显著性等于让判据跟着预算走。
func _cohen(a: Array, b: Array) -> float:
	var ma := _mean(a)
	var mb := _mean(b)
	var va := _var(a)
	var vb := _var(b)
	var na := float(a.size())
	var nb := float(b.size())
	var sp: float = sqrt(maxf(0.0001, ((na - 1.0) * va + (nb - 1.0) * vb) / maxf(1.0, na + nb - 2.0)))
	return (ma - mb) / sp


func _tag(d: float) -> String:
	var x := absf(d)
	if x < 0.2:
		return "(忽略)"
	if x < 0.5:
		return "(小)"
	if x < 0.8:
		return "(中)"
	return "(大)"


func _band_of(v: float, cuts: Array) -> int:
	for i in range(cuts.size()):
		if v < float(cuts[i]):
			return i
	return cuts.size()


func _absmean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += absf(float(v))
	return s / float(a.size())


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
