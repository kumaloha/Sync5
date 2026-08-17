extends Probe

## λ 扫描 (docs/design/solver_roadmap.md, 2026-08-06 用户拍板「平衡贪心」取代跨拍 DP)。
##   godot --headless --path . --script res://tools/lam.gd
##
## 平衡贪心把跨拍权衡压成一条式子:
##     value(切法) = 本拍得分 + λ · E[下一拍得分 | 留下的 3 张]
## λ = 0 是单拍贪心(只顾眼前, 会把最差 3 张丢进缓存);λ 越大越"养牌"。
##
## **λ 不许拍脑袋。** 这个探针把它扫出来。判据 = `tools/agree.gd` 量到的缺口:
##   数学侧(缓存全新)188.6  vs  λ=0 真打 181.4  → **−3.8%**, 那就是跨拍视野的全部赌注。
##
## **统计口径 = 配对**(这是本探针的关键):所有 λ 档跑**同一组种子**, 所以逐局配对相减,
## 抽牌运气成对抵消。非配对时标准误 ≈5 分, 差异淹在噪声里看不出;配对能压掉一个量级。
## ⚠ 配对不完美:λ 不同 → 决策不同 → 牌堆消耗从第 1 拍之后就分岔了。
## 所以它压掉的是**初始发牌**的方差, 不是全部。
##
## ⚠ 用户给这条路线的理由(记档, 免得后人又想上 DP):缓存只有 3 张、
## **未来的小丑牌没有任何信息**(商店是随机的, 根本不在状态里, DP 假装能算等于自欺),
## 而整个跨拍视野的赌注实测只有 3.8% —— 拿最大的一块工程换它是坏买卖。

# n=40 时配对差 +4.90 ±3.82(λ=0.2), z=1.28 —— 方向像是正的但不显著。
# 奖金上限 ≈7 分(3.8% 的缺口), 要分辨它得把标准误压到 ~1.5 → 约 250 局。
# ⚠ 配对没能像预期那样压掉一个量级(±5 → ±3.8), 因为 λ 一变决策就分岔,
# 只有**第 1 拍的发牌**是真配上的。想再压方差得换招(比如固定整条发牌序列重放)。
const N_RUNS := 250
const SAMPLES := 2
const MATH_CEIL := 188.6      # tools/agree.gd 的数学侧均值(缓存全新, 空槽)
const LAMS := [0.0, 0.2, 0.5]

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var slots: Array = [null, null, null, null]
	print("\n=== λ 扫描 · 空槽(纯牌型) · %d 局/档 · 配对统计 ===" % N_RUNS)
	print("  数学侧天花板(缓存全新) = %.1f" % MATH_CEIL)
	print("  基准 λ=0 是单拍贪心; 下面的差是**逐局配对**后的\n")

	var base: Array = []
	for li in range(LAMS.size()):
		var lam := float(LAMS[li])
		var per_run := _run(slots, lam)          # 每局的平均单拍分
		var m := Stat.mean(per_run)
		if li == 0:
			base = per_run
			print("  λ = %-4.2f  均分 %7.2f  (基准)" % [lam, m])
			continue
		# 配对:逐局相减, 抽牌运气抵消
		var d: Array = []
		for i in range(mini(base.size(), per_run.size())):
			d.append(float(per_run[i]) - float(base[i]))
		var dm := Stat.mean(d)
		var dse := sqrt(Stat.variance(d) / float(maxi(1, d.size())))
		var verdict := "持平"
		if dm > 2.0 * dse:
			verdict = "✅ 更好"
		elif dm < -2.0 * dse:
			verdict = "❌ 更差"
		print("  λ = %-4.2f  均分 %7.2f   配对差 %+6.2f ±%.2f   z=%+5.2f   %s"
			% [lam, m, dm, dse, dm / maxf(0.001, dse), verdict])

	print("\n  参考:λ=0 与天花板的缺口是 −3.8%%(agree.gd, 400 局)。")
	print("  养牌真有价值的话, 配对差应当显著为正并把缺口吃掉一部分。")
	print("[lam] %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)


## 返回每局的**平均单拍分**(长度 = N_RUNS), 供配对。
func _run(slots: Array, lam: float) -> Array:
	var out: Array = []
	var rep := Report.new(N_RUNS, GameConfig.SECTIONS_PER_RUN)
	rep.reset()
	var bot := Bot.new(_rng, rep)
	var cfg := {"bot": "perfect", "target": "", "no_jokers": true,
		"lam": lam, "lam_samples": SAMPLES}
	var extra := {
		"prev_kind": -99, "acted_late": false, "discards": 0, "coins": 99,
		"phrase_idx": 0, "cache_cards": [], "mod": "", "character": null,
	}
	for r in range(N_RUNS):
		_rng.seed = 810000 + r          # 跨 λ 共用种子 —— 配对的前提
		var deck := Deck.new(r * 13 + 3)
		var cache: Array = []
		var tot := 0.0
		var n := 0
		for s in range(GameConfig.SECTIONS_PER_RUN):
			for _p in range(GameConfig.PHRASES_PER_SECTION):
				var ph := Phrase.new(deck, cache, 99)
				ph.start()
				bot._play_phrase(ph, cfg, slots, s, "")
				var res := ph.lock_and_settle()
				tot += float(Settle.run(res, slots, extra)["score"])
				n += 1
				ph.cleanup()
		out.append(tot / float(maxi(1, n)))
	return out
