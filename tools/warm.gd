extends Probe

## 养牌价值探针 —— 「缓存跨拍养成」值多少分?
##   godot --headless --path . --script res://tools/warm.gd
##
## **前身是 `agree.gd`(一致性探针), 2026-08-06 用户拍板把「数学侧」退役后改成这个。**
## 旧版在探针里**重写了一遍游戏的一拍**(从全新 52 张发牌、弃牌、补牌、选切法),
## 拿它和真打对账。那是 docs/design/solver_roadmap.md 设想的「快速数学 D」的原型。三条理由让它退役:
##   ① 生成器 `curve.gd` **从来没用过它** —— 它跑的是真实链条;
##   ② 它**本身是错的** —— 实测不建缓存跨拍就低估 10%;
##   ③ 它是「分布对不上、像 bug」那三轮排查的**唯一来源** —— 两份实现才需要对账。
## **删掉之后一致性问题按构造消失**;「求解器 = 游戏代码」这条线由 `tools/pair.gd` 守
## (确定性、逐手精确、不靠统计)。
##
## 现在这个探针只量**链条内部**的一件事:
##   第 1 拍(缓存全新, 无历史)  vs  第 2 拍起(缓存是上一拍挑剩/养出来的)
## 差额 = **养牌的价值**。它同时验证 `sim.json solver.lam` 调对了没有。
## ⚠ 判据随规则变过一次:**弃牌收费时代 λ=0 的缓存会退化**(单拍视野把最差 3 张丢进去,
## 实测 −5.2 分);**弃牌免费后退化机制自己消失了** —— 贪心弃的正是那 3 张,
## 垃圾当场被换掉。实测 λ=0 变成 +6.0, λ=0.20 是 +24.6(z=8.24)。
## **教训:探针里写死的"应当为负"这类判据会随规则过期, 要跟着改。**

## ⚠ 成本:每拍约 3250 次 Pattern+Settle。快档抓方向, 全量档才够判定。
## 上一轮的真读数在 ±5 的噪声量级, **用快档下结论等于掷硬币**。
const QUICK := false
const N_FRESH: int = 800 if QUICK else 4000    # 「缓存全新」样本(每局只打 1 拍)
const N_RUNS: int = 80 if QUICK else 400       # 整局样本

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var slots: Array = [null, null, null, null]
	var lam := float(DB.sim()["solver"]["lam"])

	print("\n=== 养牌价值 · 空槽(纯牌型) ===")
	print("  基准 = 缓存全新的一拍(每局只打 1 拍, n=%d)" % N_FRESH)

	for arm in [0.0, lam]:
		var fresh := _one_beat(slots, arm, N_FRESH)
		var all: Array = []
		var first: Array = []
		var rest: Array = []
		_chain(slots, arm, all, first, rest)
		var mf := Stat.mean(fresh)
		var mr := Stat.mean(rest)
		var se := sqrt(Stat.variance(fresh) / float(fresh.size()) + Stat.variance(rest) / float(rest.size()))
		var d := mr - mf
		print("\n  ---- λ = %.2f%s ----" % [arm, "  (sim.json 配置值)" if arm == lam else "  (单拍贪心, 不养牌)"])
		_row("缓存全新(基准)", fresh)
		_row("第 2 拍起(养过的缓存)", rest)
		print("    ⭐ 养牌价值 %+.1f 分 (%+.1f%%)   标准误 %.1f   z = %+.2f   %s"
			% [d, 100.0 * d / maxf(1.0, mf), se, d / maxf(0.001, se),
				"显著" if absf(d) > 2.0 * se else "不显著"])

	print("\n  判据(2026-08-06 实测后修正):")
	print("    λ=0   应当 ≈0 或微正。**弃牌收费时代它是负的**(单拍视野把最差 3 张丢进缓存),")
	print("          但弃牌免费后贪心弃的正是那 3 张 —— 垃圾当场被换掉, 退化机制自己消失了。")
	print("    λ>0   应当**显著为正**, 那是养牌净挣的。不为正就回去查 solver.lam。")
	print("\n[warm] %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)


## 每局只打 1 拍 —— 缓存与牌堆都是全新的, 没有任何历史。
func _one_beat(slots: Array, lam: float, n: int) -> Array:
	var out: Array = []
	var bot := Bot.new(_rng, Report.new(n, GameConfig.SECTIONS_PER_RUN))
	var cfg := {"bot": "perfect", "target": "", "no_jokers": true, "lam": lam}
	for r in range(n):
		_rng.seed = 700000 + r
		var deck := Deck.new(700000 + r)
		var cache: Array = []
		var ph := Phrase.new(deck, cache, 99)
		ph.start()
		bot._play_phrase(ph, cfg, slots, 0, "")
		out.append(float(Settle.run(ph.lock_and_settle(), slots, _extra(s))["score"]))
		ph.cleanup()
	return out


## 完整一局 24 拍 —— 缓存跨拍带过去, 牌堆持续消耗。
func _chain(slots: Array, lam: float, out: Array, first: Array, rest: Array) -> void:
	var bot := Bot.new(_rng, Report.new(N_RUNS, GameConfig.SECTIONS_PER_RUN))
	var cfg := {"bot": "perfect", "target": "", "no_jokers": true, "lam": lam}
	for r in range(N_RUNS):
		_rng.seed = 810000 + r
		var deck := Deck.new(r * 13 + 3)
		var cache: Array = []
		var beat := 0
		for s in range(GameConfig.SECTIONS_PER_RUN):
			for _p in range(GameConfig.PHRASES_PER_SECTION):
				var ph := Phrase.new(deck, cache, 99)
				ph.start()
				bot._play_phrase(ph, cfg, slots, s, "")
				var sc := float(Settle.run(ph.lock_and_settle(), slots, _extra(s))["score"])
				out.append(sc)
				if beat == 0:
					first.append(sc)
				else:
					rest.append(sc)
				beat += 1
				ph.cleanup()


## ⚠⚠ `sec` 决定 `section_target` —— 缺了它, 按「本段每拍目标的 x%」定额的卡
## (加分族 A 案)在这个探针里会**静默算成 0**, 而这是养牌价值的仪器。
## **缺省 0 是有意的**:本探针大部分调用点确实只模拟第一段。
func _extra(sec: int = 0) -> Dictionary:
	return {
		"prev_kind": -99, "acted_late": false, "discards": 0, "coins": 99,
		"phrase_idx": 0, "cache_cards": [], "mod": "", "character": null,
		"section_idx": sec, "section_target": GameConfig.section_target(sec),
	}


func _row(label: String, a: Array) -> void:
	var s := a.duplicate()
	s.sort()
	print("    %-22s n=%-6d 均值 %7.1f   中位 %7.1f   P90 %7.1f"
		% [label, s.size(), Stat.mean(s), s[int(s.size() * 0.5)], s[int(s.size() * 0.9)]])
