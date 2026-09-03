extends SceneTree
## 三条小对照臂 —— 一次回答 09-02 门里剩下的三个待测数。
##
## ⚠ 这是**替代把三个待验假设塞进 6 小时全量门**的做法:门那一轮要拿来验
## 随机流换基线 + 变体和解层, 不该同时背四个假设。
##
## ① ration —— 「每段 12 张弃牌预算」咬不咬得住?
##    判据:**基线**(无脸)每段实际弃了几张。远小于 12 ⇒ 这张脸是一堵不设防的墙,
##    效应小是**结构性**的, 不是数值没调好。
##    ⚠ 不能读 `run.section_discards_used` —— `core/beat.gd:167` 只在挂着带预算的脸时
##      才累加, 基线恒 0。**那会读到一个看起来正常的零。** ⇒ 从 on_beat 累 `p.discards_used`。
##
## ② trilogy —— 「每段凑 3 种牌型」的条件是不是几乎总被满足?
##    判据:基线每段的 `run.section_kinds.size()` 分布。恒 ≥3 ⇒ 惩罚永不触发。
##    (这个量 `core/beat.gd:84` 是无条件记的, 基线读得到。)
##
## ③ countdown —— +437.8 这个**正号**是不是金币约束造出来的?
##    求解器的弃牌预算是 `mini(coins, ...)`(tools/solver.gd:568/668), 而弃牌 1◆/张。
##    假设:countdown 砍掉后半段的动作预算, 等于替这个逐拍贪心的求解器**省了钱**。
##    ⇒ 2×2 干预:{无脸, countdown} × {coin_delta 0, coin_delta +100}。
##      假设成立的判据:coin_delta=0 时差为正, coin_delta=+100 时**翻负**。
##      (金币不再是约束 ⇒ 只剩「动作变少」这一条通道 ⇒ 必须是负的。)
##
## 跑法(NON-headless 不需要, 无渲染):
##   ./tools/run.sh probe _arms /tmp/sync5-arms.log

const N := 150

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	print("[arms] n=%d/臂  段数=%d" % [N, GameConfig.SECTIONS_PER_RUN])
	_baseline_stats()
	_countdown_2x2()
	_countdown_channel()
	quit()


## 一条基线臂, 顺便把 ① 和 ② 两个量都收了。
func _baseline_stats() -> void:
	var disc_per_sec: Array = []      # 每段弃了几张
	var kinds_per_sec: Array = []     # 每段凑出几种牌型
	var acc := {"d": 0}
	var rep := Report.new(N, GameConfig.SECTIONS_PER_RUN)
	rep.reset()
	var bot := Bot.new(_rng, rep)
	for r in range(N):
		_rng.seed = 620000 + r
		var o := RunLoop.Opts.new()
		o.rng = _rng
		o.deck_seed = r * 17 + 5
		o.faces = {}
		o.player = "adaptive"
		o.cfg = {"bot": "perfect"}
		o.shop = false
		o.mortal = false
		acc["d"] = 0
		o.on_beat = func(_run, p, _outcome, _ctx) -> void:
			acc["d"] += int(p.discards_used)
		o.on_section = func(run, _section, _sec_score, _coins) -> void:
			disc_per_sec.append(float(acc["d"]))
			kinds_per_sec.append(float(run.section_kinds.size()))
			acc["d"] = 0
		RunLoop.play(o, bot)

	print("\n---- ① ration:基线每段实际弃牌张数(预算写的是 %d)----"
		% SectionMod.section_discard_budget("ration"))
	_dump(disc_per_sec, SectionMod.section_discard_budget("ration"))
	print("\n---- ② trilogy:基线每段凑出的牌型种数(要求 %d 种)----"
		% SectionMod.required_kinds("trilogy"))
	_dump(kinds_per_sec, SectionMod.required_kinds("trilogy"))


## 2×2:脸 × 金币是否宽裕。
func _countdown_2x2() -> void:
	print("\n---- ③ countdown:金币约束是不是正号的来源 ----")
	for cd in [0, 100]:
		var a := _arm("", cd)
		var b := _arm("countdown", cd)
		var p := Stat.paired(a, b)
		var m: float = Stat.mean(a)
		print("    coin_delta=%+4d   基准 %.0f   countdown 差 %+9.1f ±%.1f  z=%+.2f  (%.1f%%)"
			% [cd, m, p["d"], p["se"], p["d"] / maxf(0.001, p["se"]),
				absf(p["d"]) / maxf(1.0, absf(m)) * 100.0])
	print("    判据:coin_delta=0 为正、+100 翻负 ⇒ 正号是金币约束造的, countdown 的 proof 通路选错了。")
	print("         两边同号 ⇒ 假设被推翻, 另找原因(别改内容)。")


## ⚑ countdown 的**通路二选一**(2026-09-03)。
##
## 2×2 已经证明:金币宽裕后 countdown 对**完美玩家**是 z=1.02(什么都没量到)。
## 把它对上 ① 的数 —— 完美玩家每段弃 14.15 张 ÷ 6 拍 ≈ **2.4 张/拍**, 而 countdown
## 压到最狠仍留 **4 张/拍** ⇒ **闸门够不着它**。
## 于是只剩两种可能, 含义完全不同:
##   A. **通路选错** —— 规则 bot 手牌 5 张、单批可弃满 5, countdown 压到 4 就咬住了
##      ⇒ 改 `proof: score` 即可, **一行配置**;
##   B. **杠杆没有行程** —— 规则 bot 也用不到 4 张/拍 ⇒ 两条臂都够不着,
##      这张脸对模型近乎空气, 和 trilogy 同类, **是内容问题不是仪器问题**。
## ⇒ 区分它俩只要一个数:**规则 bot 每拍实际弃几张**。
## ⚠ 规则 bot 的队列 = 门 score 通路用的那条(`_cohort()` 取第一条非 random 非 no_jokers,
##   实为 `adaptive:twin`), 且**开商店** —— 口径必须与它要服务的那条臂一致。
func _countdown_channel() -> void:
	print("\n---- ④ countdown 的通路:规则 bot 每拍弃几张? ----")
	var per_beat: Array = []
	var rep := Report.new(N, GameConfig.SECTIONS_PER_RUN)
	rep.reset()
	var bot := Bot.new(_rng, rep)
	for r in range(N):
		_rng.seed = 620000 + r
		var o := RunLoop.Opts.new()
		o.rng = _rng
		o.deck_seed = r * 17 + 5
		o.faces = {}
		o.player = "adaptive"
		o.cfg = {"bot": "adaptive", "target": "twin"}   # = 门 score 通路的队列
		o.shop = true                                   # score 通路开商店
		o.mortal = false
		o.on_beat = func(_run, p, _outcome, _ctx) -> void:
			per_beat.append(float(p.discards_used))
		RunLoop.play(o, bot)
	var floor_cards := int(GameConfig.discard_batch(4.0, 0))   # countdown 末两拍的单批上限
	print("    规则 bot 每拍弃牌张数:")
	_dump(per_beat, floor_cards)
	print("    对照:完美玩家 ≈ 2.4 张/拍 · countdown 压到最狠仍留 %d 张/拍" % floor_cards)
	print("    判据:达到/超过 %d 的比例**高** ⇒ A 通路选错(改 proof: score);" % floor_cards)
	print("         比例**接近 0** ⇒ B 杠杆没行程(内容问题, 别改通路)。")


func _arm(mod: String, coin_delta: int) -> Array:
	var out: Array = []
	var rep := Report.new(N, GameConfig.SECTIONS_PER_RUN)
	rep.reset()
	var bot := Bot.new(_rng, rep)
	var faces := {}
	if mod != "":
		for w in GameConfig.WALL_SECTIONS:
			faces[w] = mod
	for r in range(N):
		_rng.seed = 620000 + r          # ⚠ 配对:每条臂的第 r 局用同一个种子
		var o := RunLoop.Opts.new()
		o.rng = _rng
		o.deck_seed = r * 17 + 5
		o.faces = faces
		o.player = "adaptive"
		o.cfg = {"bot": "perfect"}
		o.shop = false
		o.mortal = false
		o.coin_delta = coin_delta
		out.append(RunLoop.play(o, bot)["total"])
	return out


func _dump(v: Array, threshold: int) -> void:
	if v.is_empty():
		print("    (空 —— 这条臂什么都没收到, 读数作废)")
		return
	var s := v.duplicate()
	s.sort()
	var over := 0
	for x in v:
		if float(x) >= float(threshold):
			over += 1
	print("    均值 %.2f   中位 %.0f   p10 %.0f   p90 %.0f   最大 %.0f   n=%d"
		% [Stat.mean(v), s[int(s.size() * 0.5)], s[int(s.size() * 0.1)],
			s[mini(int(s.size() * 0.9), s.size() - 1)], s[s.size() - 1], v.size()])
	print("    达到/超过阈值 %d 的比例:%.1f%%  ← 这就是这张脸的触发率"
		% [threshold, float(over) / float(v.size()) * 100.0])
