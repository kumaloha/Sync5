extends Probe

## 分数归因探针 —— 「这个流派的分到底从哪来?」
##   godot --headless --path . --script res://tools/attrib.gd
##
## **为什么要它**(2026-08-06 用户提的问题):阶梯的 S4 段分中位是全场最高(4300),
## 但顺子按理说不好凑 —— 「实现的概率应该没那么高, 为什么期望分数那么高」。
##
## 这个疑问指出了一个真问题:**稀有的大爆发只抬高平均值, 抬不高中位数**。
## 中位数高 = 典型的一拍就打得好, 那就不能全靠偶尔一次同花顺。
## 所以要把分数按牌型拆开, 看两件事:
##   ① **频率**:每种牌型多久出现一次(是不是真的稀有)
##   ② **分数占比**:总分里有多少是它贡献的(是不是真的靠它)
## 频率低而占比高 = 靠爆发;频率高 = 「不好凑」这个前提本身就不成立。
##
## 用求解器(完美玩家)跑, 因为流派强弱是跟着玩家水平变的 —— 机器人不会追顺子。

const N_RUNS := 40


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	print("\n=== 分数归因 · 完美玩家 · %d 局/队列 ===" % N_RUNS)
	# ⚠ 频率是**策略下的分布**, 不是「牌堆能给什么」—— 求解器朝着装备走,
	# 装阶梯它就去凑顺子, 装双子它就收两对。所以必须分开量, 并且要有一个
	# **不装 Target 的中性档**当基准, 否则读到的是策略而不是可得性。
	# (同一个教训记过一次: model.gd 的 A 表把「贪心分布」当成了「转换率」。)
	for cid in ["", "stair", "mono", "twin", "lonewolf", "triplet"]:
		_run(cid, rng)
	print("\n[attrib] %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)


func _run(target_id: String, rng: RandomNumberGenerator) -> void:
	var rep := Report.new(N_RUNS, GameConfig.SECTIONS_PER_RUN)
	rep.reset()
	var bot := Bot.new(rng, rep)
	var cfg := {"bot": "perfect", "target": target_id, "no_jokers": true}
	var freq := {}          # kind -> 出现次数
	var share := {}         # kind -> 总分贡献
	var total := 0.0
	var beats := 0
	var slots: Array = [null, null, null, null]
	if target_id != "":
		slots[0] = Joker.by_id(target_id)
	for r in range(N_RUNS):
		rng.seed = 990000 + r
		var deck := Deck.new(r * 23 + 7)
		var cache: Array = []
		for s in range(GameConfig.SECTIONS_PER_RUN):
			for _p in range(GameConfig.PHRASES_PER_SECTION):
				var ph := Phrase.new(deck, cache, 99)
				ph.start()
				bot._play_phrase(ph, cfg, slots, s, "")
				var res := ph.lock_and_settle()
				var out := Settle.run(res, slots, {
					"prev_kind": -99, "acted_late": false, "discards": 0,
					"coins": 99, "phrase_idx": 0, "cache_cards": cache,
					# ⚠⚠ **`section_target` 必须传** —— 缺了它, 任何按「本段每拍目标的 x%」
					# 定额的卡(加分族 A 案)在这个探针里会**静默算成 0**, 而这正是
					# 牌型频率/中性基准的仪器 ⇒ 会「测出」那族卡没用。**自我实现的错误结论。**
					# 这是「规则在游戏里、不在模型里」的第 6 次的预防, 不是修 bug。
					"section_idx": s, "section_target": GameConfig.section_target(s),
					"mod": "", })
				var k := int(res.get("kind", -1))
				var sc := float(out["score"])
				freq[k] = int(freq.get(k, 0)) + 1
				share[k] = float(share.get(k, 0.0)) + sc
				total += sc
				beats += 1
				ph.cleanup()
	var label := target_id if target_id != "" else "(无 Target · 中性基准)"
	print("\n  ▶ %s   平均单拍 %.0f 分" % [label, total / float(maxi(1, beats))])
	var keys: Array = freq.keys()
	keys.sort()
	for k in keys:
		var f: float = 100.0 * float(freq[k]) / float(beats)
		var sh: float = 100.0 * float(share[k]) / maxf(1.0, total)
		if f < 0.4 and sh < 1.0:
			continue
		print("    %-16s 出现 %5.1f%%   贡献总分 %5.1f%%   命中时均分 %6.0f"
			% [Pattern.NAMES.get(k, "?"), f, sh,
				float(share[k]) / maxf(1.0, float(freq[k]))])
