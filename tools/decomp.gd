extends Probe

## 五项难度分解 —— 回答「**难在哪**」而不是「多难」。
##   godot --headless --path . --script res://tools/decomp.gd
##   SYNC5_DECOMP_N=40 godot --headless --path . --script res://tools/decomp.gd
##
## ⚑ **为什么要它**(`docs/design/solving.md` §II-1):`solver_roadmap.md` 定义「难度 = 1/通过率」,
## 那是个**结果** —— 它回答「多难」, 不回答「难在哪」。而关卡设计要判断的恰恰是
## 「**这一级的难, 和上一级是不是同一种难**」。文档写着:
## 「**五项的仪器全都已经有了, 而且都在跑 —— 只是从来没有被并排放在一张表上。**」
## 本探针就是那张表。
##
## | # | 来源 | 公式 | 体感 |
## |---|---|---|---|
## | ① | 数值压力 | `target / E[ρ]` | 「要打更多分」 |
## | ② | 上界压缩 | `E[ρ(有脸)] / E[ρ(无脸)]` | 「我最好也就这样了」 |
## | ③ | 技巧惩罚 | `E[ρ(最优)] − E[ρ(退化玩家)]` | 「打错代价变大」 |
## | ④ | 信息惩罚 | `E[ρ(上帝)] − E[ρ(蒙住)]` | 「我算不准」 |
## | ⑤ | 运气暴露 | `Var[ρ] / E[ρ]²` | 「我控制不了」 |
##
## ⚠⚠ **这不是「难度的定义」**(那是拿地图当疆域)。它是**五个可测的量, 我认为它们和「难」有关**,
## 而这个「有关」**没有任何外部锚** —— `solving.md` 自己标注「这一条是本文最需要你审的」。
## **模型给形状, 给不了好坏。**
##
## ⚠ **③ 的口径有歧义, 所以两个都报**:`generating.md` 写的是「λ 开关」,
## 但 `solving.md §3.4` 实测 **λ 全谱只值 645 分, 而 ε 值 1894 分(2.9 倍)** ——
## 用 λ 量技巧惩罚会量到一个小得多的量。**ε 那一列才是主导维度。**
##
## ⚠ **四臂共用随机数**(项目铁律):每局掷脸后记下 RNG 状态,
## 四臂从**同一个状态**出发。不这么做的话噪声会吃掉臂间差异(踩过三次)。

const N_DEFAULT := 15
const EPS_DEGRADED := 8.0   # solving.md §8.2b 实测:ε≥8 已完全被噪声支配 ≈ 随机挑切法
const LAM_BASE := 0.2       # 基准玩家的跨拍权重(与 sim.json solver.lam 一致)


func watchdog_sec() -> float:
	return 120.0


func _initialize() -> void:
	var n := env_int("SYNC5_DECOMP_N", N_DEFAULT)
	var t0 := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	var S := GameConfig.SECTIONS_PER_RUN

	# 每臂 × 每段的段分样本
	var arms := ["base", "noface", "eps", "lam0", "oracle"]
	var acc := {}
	for a in arms:
		var per: Array = []
		for _s in range(S):
			per.append([])
		acc[a] = per

	print("\n=== 五项难度分解 · %d 局/臂 · 四臂共用随机数 ===" % n)
	print("  ⚠ 不死局(打满 24 拍), 所以每局每段都有数 —— 不含幸存者条件。")

	for r in range(n):
		rng.seed = 880000 + r
		# ⚑ 一局四张脸走 SectionMod.roll_run 这一份(2026-08-14 收口, 原来 7 份)——
		# 保证「一局之内不偶然重复」。RNG 消耗与旧代码逐次相同。
		var faces := SectionMod.roll_run(rng)
		var st0 := rng.state          # ⚑ 四臂的共同起点

		_arm(acc["base"], rng, st0, r, faces, LAM_BASE, 0.0, false)
		_arm(acc["noface"], rng, st0, r, {}, LAM_BASE, 0.0, false)
		_arm(acc["eps"], rng, st0, r, faces, LAM_BASE, EPS_DEGRADED, false)
		_arm(acc["lam0"], rng, st0, r, faces, 0.0, 0.0, false)
		_arm(acc["oracle"], rng, st0, r, faces, LAM_BASE, 0.0, true)

	_report(acc, S, n)
	print("\n[decomp] %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)


## 跑一局并把 4 个段分记进 `sink`。⚠ 一局的循环走 `RunLoop`(铁律:不许再抄一份)。
func _arm(sink: Array, rng: RandomNumberGenerator, st0: int, r: int,
		faces: Dictionary, lam: float, eps: float, oracle: bool) -> void:
	rng.state = st0
	var prev_oracle := Solver.ORACLE
	Solver.ORACLE = oracle
	var o := RunLoop.Opts.new()
	o.rng = rng
	o.deck_seed = r * 17 + 5
	o.faces = faces
	o.player = "perfect"
	o.lam = lam
	o.eps = eps
	o.lam_samples = 2
	o.shop = true          # 构筑值 4.2 倍, 关掉它量的就不是这个游戏
	o.mortal = false       # 不死局 ⇒ 每段都有数
	var res := RunLoop.play(o, Bot.new(rng, Report.new(1, GameConfig.SECTIONS_PER_RUN)))
	Solver.ORACLE = prev_oracle
	for s in range(sink.size()):
		sink[s].append(float(res["sec_scores"][s]))


func _report(acc: Dictionary, S: int, n: int) -> void:
	var targets: Array = DB.run()["section_targets"]
	print("\n## 五项分解(按段)")
	print("| 段 | E[ρ] | ① 数值压力 | ② 上界压缩 | ③ 技巧惩罚(ε) | ③' 技巧(λ) | ④ 信息惩罚 | ⑤ 运气暴露 |")
	print("|---|---:|---:|---:|---:|---:|---:|---:|")
	var rows: Array = []
	for s in range(S):
		var base: Array = acc["base"][s]
		var m := Stat.mean(base)
		var p1: float = float(targets[s]) / maxf(1.0, m)
		var p2 := Stat.mean(acc["noface"][s])
		var comp: float = m / maxf(1.0, p2)
		var d_eps := Stat.paired(acc["eps"][s], base)
		var d_lam := Stat.paired(acc["lam0"][s], base)
		var d_inf := Stat.paired(base, acc["oracle"][s])
		var v: float = Stat.variance(base) / maxf(1.0, m * m)
		rows.append({"m": m, "p1": p1, "p2": comp, "p3": float(d_eps["d"]),
			"p3l": float(d_lam["d"]), "p4": float(d_inf["d"]), "p5": v})
		print("| S%d | %.0f | **%.2f×** | %.3f | %+.0f ±%.0f | %+.0f ±%.0f | %+.0f ±%.0f | %.3f |" % [
			s + 1, m, p1, comp,
			d_eps["d"], d_eps["se"], d_lam["d"], d_lam["se"], d_inf["d"], d_inf["se"], v])

	print("\n**读法**:")
	print("- ① >1 = 目标分高过完美玩家的期望段分(必须靠构筑或运气);<1 = 裸打够用。")
	print("- ② <1 = 脸把上界压下来了(越小压得越狠);=1 = 这段的脸不压上界。")
	print("- ③ = 从最优退化到「随机挑切法」丢多少分 —— **会玩的回报**。")
	print("- ④ = 上帝视角比蒙住多拿多少 —— 只有盖牌族该显著。")
	print("- ⑤ = 段分的变异系数平方 —— 越大越像抽签。")

	# ⚑ 本表要回答的那个具体问题。
	# ⚠⚠ **要检验的是「段与段之间有没有差」, 不是「每段的值本身显不显著」** ——
	# 第一版我用 (max−min)/mean 判「在动」, **完全没对照噪声**, 违反了
	# 「没有标准误的差值等于没有结论」。改成 **S4 − S1 的逐局配对差**:
	# 每一局都能算出 `d_s(r)`, 所以跨段差也是配对的, 有 se 可算。
	print("\n## ⚑ 四段是不是「同一种难收了四次费」(检验 S4 − S1,逐局配对)")
	print("| 项 | S1 → S4 | S4−S1 | se | z | 判读 |")
	print("|---|---|---:|---:|---:|---|")
	_ladder("③ 技巧惩罚(ε)", acc["base"], acc["eps"], S, true)
	_ladder("③' 技巧(λ)", acc["base"], acc["lam0"], S, true)
	_ladder("④ 信息惩罚", acc["oracle"], acc["base"], S, true)
	_ladder("② 上界压缩", acc["base"], acc["noface"], S, false)
	# ①⑤ 没有逐局值(① 的分子是常数目标分, ⑤ 是聚合方差), 只报趋势并显式声明
	var t1: Array = []
	var t5: Array = []
	for row in rows:
		t1.append("%.2f" % float(row["p1"]))
		t5.append("%.2f" % float(row["p5"]))
	print("| ① 数值压力 | %s | — | — | — | ⚠ **无 se**(分母是占位的目标分表, 口径还对不上)|"
		% " → ".join(t1))
	print("| ⑤ 运气暴露 | %s | — | — | — | ⚠ **无 se**(聚合方差, 要 bootstrap 才有)|"
		% " → ".join(t5))

	print("\n⚑ **判读规则**:`|z| ≥ 3` 才算「这一维真的参与了阶梯」;否则是**没测出来**,")
	print("   而「没测出来」既可能是它真平, 也可能是样本不够 —— **两者不许混为一谈**。")
	print("⚠ 判断权在设计者 —— 本表只让形状可见, 不说好坏(solving.md §II-1)。")
	print("⚠ n=%d。要让 ③ 达到 |z|≥3 约需 **n≈100**(se ∝ 1/√n 反推)。" % n)


## 一项的「阶梯检验」:逐局算 `d_s(r) = a[s][r] − b[s][r]`, 再检验 `d_last − d_first`。
## `as_diff=false` 时 `d` 取比值(上界压缩那种)。
func _ladder(label: String, a: Array, b: Array, S: int, as_diff: bool) -> void:
	var first: Array = []
	var last: Array = []
	var n: int = (a[0] as Array).size()
	var seq: Array = []
	for s in range(S):
		var col: Array = []
		for r in range(n):
			var x: float = float((a[s] as Array)[r])
			var y: float = float((b[s] as Array)[r])
			col.append(x - y if as_diff else x / maxf(1.0, y))
		seq.append("%.2f" % Stat.mean(col))
		if s == 0:
			first = col
		if s == S - 1:
			last = col
	var pr := Stat.paired(first, last)      # d = last − first
	var z: float = float(pr["d"]) / maxf(1e-9, float(pr["se"]))
	var verdict := "**参与了阶梯**" if absf(z) >= 3.0 \
		else ("倾向有差, 但**没到判据**" if absf(z) >= 2.0 else "**没测出来**(平 or 样本不够)")
	print("| %s | %s | %+.2f | %.2f | %.1f | %s |" % [
		label, " → ".join(seq), pr["d"], pr["se"], z, verdict])
