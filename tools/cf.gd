extends SceneTree

## 反事实重放 —— 每张支援卡的**实测 EV(分/拍)**。
##   godot --headless --path . --script res://tools/cf.gd
##   SYNC5_CF_ID=curtain,hush   只算这几张(默认全部支援卡)
##
## `numbers.md §8.1` 用过这把尺(「12 局 168 拍, scale 重放」),但**当年是一次性手算,
## 工具没留下** —— 于是 §8.2 那张 v3 目标价表只覆盖了 17 项,谢幕/静物/早弃/静场/
## 二重唱那一族**从来没进过任何一轮定价**。这里把它固化。
##
## ⚑ 做法 = **同一拍跑两次 `Settle.run`,只差 `joker_slots`**:
##   `Δ分 = Settle.run(res, [卡], ctx).score − Settle.run(res, [], ctx).score`
## `Settle.run` 是**纯函数**(res + slots + ctx 进,分数出),ctx 全是**事实** ——
## 所以反事实不需要重建 Phrase,只要从 Tape 把 ctx 拼回来。
## **判定一行都不重写**:条件谓词照样走 `core/fx.gd`,这是它与 probbook 基线列
## (那边手写判定 + fired 自证)的分工。
##
## ⚠⚠ **它是下界,不是预测**:反事实假设玩家的操作**不因为装了这张卡而改变**,
## 而 2026-08-28 实测行为适应是真实且巨大的(谢幕:基线 21% → 持有态 67%,3.2 倍)。
## ⇒ 对**可控卡**读它要配 probbook 的持有态那一列,两头夹出区间。
##
## ⚠ ctx 里有两项 Tape 没记(`early_finish` 提前收工 / `seconds_left` 结算剩余秒),
## 一律填 false/0。**以它们为条件的卡(速弹/秒表/定格/快进/惯性)读数无效**,
## 表里单独标 `ctx缺` —— 宁可标出来,也不要一个静默偏低的数。

## ctx 拼不全的卡 —— Tape 没记那几项事实, 读数**无效**(不是「这卡没用」)。
##   early_finish/seconds_left 没记 → 速弹/秒表/定格/快进/惯性
##   luck_rolls 没记(掷点是结算当场掷的, 不入 Tape)→ 孤注/彩头 **会恒定走坏的那一支**
##     (孤注一度读出 −123.6 分/拍, 那是空掷数组的产物, 不是它的真实强度)
##   per 的计数没记 → 串场(swapped_scoring)/让位(faces_discarded)/盲奏(hidden_scoring)/
##     回收(cache_discard_rank_sum)
##   依赖 Target 状态 → 镜面(prev_target_hit)
## ⚠⚠ **这 12 张算不出来, 是因为记录里的信息不够**(2026-08-30 复核):
## 它们的效果取决于「这一拍具体弃了哪几张牌」(按牌面 / 花色 / 计数器算),
## 而我们只记了「弃了 3 张」这个数字, **没记是哪 3 张**。
## ⇒ 要么让 Tape 记下每次弃牌的牌面, 要么重放时从 `disc` 事件逐张还原 ——
## 两条都是独立一批的工作量, **不在这个文件里修**。
## ⚑ 代价:机器人判断这 12 张时**没有实测保底值**, 只能靠手写公式,
## 而手写公式正是 2026-08-30 证明会系统性算低的东西(23 张卡因此从没被买过)。
const NO_CTX := ["shredder", "stopwatch", "freeze", "fastforward", "momentum",
	"allin", "jackpot", "segue", "stageexit", "blindplay", "recycle", "mirror"]

## ⚠ 依赖**缓存状态**的卡:ctx 里的 `cache_cards` 只能取 `beat` 事件的快照
## (= 拍**开始**时的缓存), 而结算看的是拍**结束**时的缓存 —— 玩家每拍平均做 1.0 次
## 交换(tau.py 实测), 快照与结算态因此系统性不同。⇒ 这几张的 EV **不出值**。
## 修法不在这里:要么 Tape 在 settle 补记一次缓存, 要么重放侧从 swap 事件推演缓存演化。
const CACHE_DEP := ["chord", "rehearsal", "bench", "boxseats", "harmony"]

var _rows: Array = []


func _initialize() -> void:
	var want := {}
	var env := OS.get_environment("SYNC5_CF_ID")
	if env != "":
		for s in env.split(","):
			want[s.strip_edges()] = true
	var files := _qualified_logs()
	if files.is_empty():
		push_error("[cf] 没有合格的真人 Tape")
		quit(1)
		return
	var beats: Array = []
	for f in files:
		beats.append_array(_beats_of(f))
	if beats.is_empty():
		push_error("[cf] 合格局里没有可重放的拍")
		quit(1)
		return
	print("[cf] 合格局 %d · 可重放拍 %d\n" % [files.size(), beats.size()])

	# ⚑⚑ **两套基准, 因为「边际贡献」有两个口径**(2026-08-28 对账时才发现):
	#   **空构筑** = 这张卡自己值多少 —— 所有卡同一基准, **可比**;
	#   **真实构筑** = 装在玩家当时的牌组上值多少 —— `numbers.md §8.1` 用的就是这个
	#     (原话「拿真人每一拍的实际手牌**与倍率链**」), **定价该看它**。
	# 两者能差几倍:倍率链均值 6.70~10.33, 乘法类卡在真实构筑里会被现有链放大,
	# 空构筑下则没有可放大的东西。**当年 §8.1 读复读 62 而我读 24.6, 差的就是这个,
	# 不是尺子坏了** —— 08-12 及以前那批的拍均分/倍率链与 §8.1 记的 502/6.70 逐位吻合。
	var base: Array = []
	var base_coin: Array = []
	var base_real: Array = []
	for b in beats:
		var o0 := Settle.run(b["res"], [null, null, null, null], b["ctx"])
		base.append(float(o0.get("score", 0)))
		base_coin.append(float(o0.get("coins", 0)))
		base_real.append(float(Settle.run(b["res"], _slots_of(b["held"], ""), b["ctx"]).get("score", 0)))

	# curve 走 DB 原始记录 —— `Joker` 类没有把它暴露成属性(它是定价用的元数据)。
	var curve_of := {}
	var hold_of := {}
	for rec in DB.jokers():
		curve_of[String(rec.get("id", ""))] = String(rec.get("curve", ""))
		if rec.has("hold"):
			hold_of[String(rec.get("id", ""))] = true

	print("%-13s %-8s %-5s %8s %9s %8s %8s %7s  %s" % ["id", "名", "稀有",
		"EV空构筑", "EV真实", "EV早段", "EV晚段", "地板", "备注"])
	for j in Joker.pool():
		if String(j.kind) == "target" or not j.has_effects():
			continue
		var jid := String(j.id)
		if not want.is_empty() and not want.has(jid):
			continue
		var sum := 0.0
		var sum2 := 0.0
		var real_sum := 0.0
		var real_n := 0.0
		var cache_n := 0
		var early_sum := 0.0
		var early_n := 0.0
		var late_sum := 0.0
		var late_n := 0.0
		var coin_sum := 0.0
		var fired := 0
		for i in range(beats.size()):
			var b: Dictionary = beats[i]
			# ⚠ 每拍**重新拿一张干净的卡**:成长牌(黑胶/贝斯线/惯性)的 state 会被
			# 上一拍写脏, 复用同一个实例等于让它跨拍累积 —— 那是另一个量(到达值),
			# 不是「这一拍的边际贡献」。
			var one = Joker.by_id(jid)
			if one == null:
				continue
			if bool(b.get("cache_exact", false)):
				cache_n += 1
			var slots: Array = [null, one, null, null]
			var o := Settle.run(b["res"], slots, b["ctx"])
			var d: float = float(o.get("score", 0)) - float(base[i])
			sum += d
			sum2 += d * d
			coin_sum += float(o.get("coins", 0)) - float(base_coin[i])
			if absf(d) > 0.001:
				fired += 1
			# 真实构筑口径:把这张卡塞进玩家当时的牌组(已持有则跳过这一拍 ——
			# 「再装一张一样的」不是它的边际)。
			if CACHE_DEP.has(jid) and not bool(b.get("cache_exact", false)):
				continue                            # 缓存卡只用拿到精确结算态的那些拍
			if not b["held"].has(jid):
				var rs := _slots_of(b["held"], jid)
				if rs.size() > 0:
					var dr: float = float(Settle.run(b["res"], rs, b["ctx"]).get("score", 0)) \
						- float(base_real[i])
					real_sum += dr
					real_n += 1.0
					# CLAUDE.md:「奖励分在乘法**后**落地 —— 前期是神、后期自然过气」。
					# 这两列就是那句话的检验:兑现的话早段该显著高于晚段。
					if int(b["sec"]) <= 1:
						early_sum += dr
						early_n += 1.0
					else:
						late_sum += dr
						late_n += 1.0
		var n := float(beats.size())
		var ev := sum / n
		# ⚠ **报均值不报离散 = 把噪声当信号**(本项目最贵的一类错)。EV 的标准误
		# 决定了「这张卡偏离地板」是不是真的:偏离 < 2 SE 一律**不动数值**。
		var sd: float = sqrt(maxf(0.0, sum2 / n - ev * ev))
		var se: float = sd / sqrt(n)
		var dc := coin_sum / n
		var ev_real: float = real_sum / maxf(1.0, real_n)
		var ev_early: float = early_sum / maxf(1.0, early_n)
		var ev_late: float = late_sum / maxf(1.0, late_n)
		var floor_ev := _floor_for(String(j.rarity))
		var note := ""
		if NO_CTX.has(jid):
			note = "⚠ctx缺·读数无效"
		elif CACHE_DEP.has(jid) and cache_n < beats.size() * 0.5:
			note = "⚠精确缓存态样本不足(%d/%d)" % [cache_n, beats.size()]
		elif String(curve_of.get(jid, "")) == "growth":
			# 成长牌:这里每拍都拿**干净实例**(不让 state 跨拍脏), 所以它必然读 0。
			# 它的价值是**到达值**(numbers.md §3.3:按拍 18-24 定价), 不是单拍边际。
			note = "成长牌·本尺不适用(看到达值)"
		elif String(curve_of.get(jid, "")) == "decay" or hold_of.has(jid):
			# ⚠⚠ **干净实例这一刀是双刃的**(2026-08-28 差点据此砍错两张卡):
			# 它挡住了成长牌的跨拍累积, 但同样挡住了 **decay 的衰减**与 **hold 的离场** ——
			# 荧光棒的 `pct` 计数器靠 `Fx.on_phrase_end` 每拍减 6%,干净实例下它**永远是
			# 初值 0.6**;客串 `section_life: 1` 一段后该谢幕,干净实例下它**永不离场**。
			# 于是两张卡一度读出 2.36× / 1.97× 的「超模」,而那是**尺子的产物**。
			# ⇒ 三类 state 相关的卡(growth / decay / hold)一律**不出值**,
			# 它们的定价走 §3.3 的时间轴(按到达值 / 前 6 拍积分 / 持有期定价)。
			note = "decay·hold 卡·本尺不适用(state 跨拍, 见 §3.3 时间轴)"
		elif absf(dc) > 0.001:
			note = "金币通道 %+.2f◆/拍" % dc
		elif fired == 0:
			note = "零触发(条件 250 拍里一次没成立)"
		print("%-13s %-8s %-5s %8.1f %9.1f %8.1f %8.1f %7d  %s" % [jid, String(j.cn_name),
			String(j.rarity), ev, ev_real, ev_early, ev_late, floor_ev, note])
		_rows.append({"id": jid, "cn": String(j.cn_name), "rarity": String(j.rarity),
			"chan": _chan_of(jid), "ev": ev, "se": se, "real": ev_real,
			"early": ev_early, "late": ev_late, "floor": floor_ev, "note": note})

	_write_book(beats.size(), files.size())
	quit(0)


## 卡按哪个通道计分 —— 定价必须**族内比**(2026-08-28:奖励分族与改基族差 3.5 倍,
## 跨族比会把「这一族整体偏弱」误读成「这张卡弱」)。
func _chan_of(jid: String) -> String:
	for rec in DB.jokers():
		if String(rec.get("id", "")) != jid:
			continue
		for e in rec.get("effects", []):
			for k in e.get("do", {}):
				if k == "bonus_target_pct" or k == "bonus_pct" or k == "mult_add" or k == "bonus":
					return String(k)
				if String(k).begins_with("additive") or k == "chips_per_card":
					return "additive(改基)"
	return "其它"


## 落盘 —— 与 `docs/design/probbook.md` 同一条纪律:**仪器读数, 手改无效**。
func _write_book(n_beats: int, n_runs: int) -> void:
	var lines: Array = []
	lines.append("# 卡片 EV 账本(仪器读数,手改无效 —— 重刷:`godot --headless --path . --script res://tools/cf.gd`)\n")
	lines.append("反事实重放:同一拍跑两次 `Settle.run` 只差 `joker_slots`,差值 = 这张卡的边际贡献。")
	lines.append("样本:**%d 局 / %d 拍**真人 Tape(筛法与 `tools/probbook.py::_qualified` 同一份)。\n" % [n_runs, n_beats])
	lines.append("**两个口径都要看**:")
	lines.append("- `EV空构筑` —— 卡装在空牌组上。所有卡同一基准,**可比**;")
	lines.append("- `EV真实构筑` —— 装在玩家**当时的牌组**上。`numbers.md §8.1` 用的就是它,**定价看这个**。")
	lines.append("  两者能差几倍(倍率链均值 6.7~10.3,乘法类卡在真实构筑里被放大)。\n")
	lines.append("⚠ **绝对值有系统偏差,只用相对排序** —— 无条件卡「灯牌」按 §3.1 定义就是地板,")
	lines.append("而它读不到 1.00×。⇒ **以灯牌归一后再比**,且**只在族内比**(奖励分族与改基族差 3.5 倍)。\n")
	lines.append("⚠ `EV早段`(S1-2)/`EV晚段`(S3-4)是 CLAUDE.md「奖励分前期是神、后期过气」那句的检验位 ——")
	lines.append("2026-08-28 实测**两头都反**(奖励分晚/早 = 2.50,改基 0.91),那句话只对固定数额成立。\n")
	var chans: Array = []
	for r in _rows:
		if not chans.has(r["chan"]):
			chans.append(r["chan"])
	for ch in chans:
		lines.append("\n## %s 族\n" % ch)
		lines.append("| id | 名 | 稀有 | EV空构筑 | ±SE | EV真实构筑 | EV早段 | EV晚段 | 地板 | 备注 |")
		lines.append("|---|---|---|---:|---:|---:|---:|---:|---:|---|")
		var fam: Array = []
		for r in _rows:
			if r["chan"] == ch:
				fam.append(r)
		fam.sort_custom(func(a, b): return float(a["real"]) > float(b["real"]))
		for r in fam:
			lines.append("| %s | %s | %s | %.1f | ±%.1f | **%.1f** | %.1f | %.1f | %d | %s |" % [
				r["id"], r["cn"], r["rarity"], r["ev"], r["se"], r["real"],
				r["early"], r["late"], r["floor"], r["note"] if r["note"] != "" else "·"])
	var f := FileAccess.open("res://docs/design/evbook.md", FileAccess.WRITE)
	if f == null:
		push_error("[cf] 写不了 docs/design/evbook.md")
		return
	f.store_string("\n".join(lines) + "\n")
	print("\n→ docs/design/evbook.md(%d 张)" % _rows.size())


## 持仓 → 槽位数组。0 号是 Target 专用、1..3 是 Support(`Joker.has_room_for` 同一条规则)。
## `add` 非空 = 再塞一张进去;塞不下返回空数组(调用方跳过这一拍)。
func _slots_of(held: Array, add: String) -> Array:
	var out: Array = [null, null, null, null]
	for id in held:
		var jj = Joker.by_id(String(id))
		if jj == null:
			continue
		if String(jj.kind) == "target":
			if out[0] == null:
				out[0] = jj
		else:
			for k in range(1, 4):
				if out[k] == null:
					out[k] = jj
					break
	if add == "":
		return out
	var extra = Joker.by_id(add)
	if extra == null:
		return []
	if String(extra.kind) == "target":
		if out[0] != null:
			return []
		out[0] = extra
		return out
	for k in range(1, 4):
		if out[k] == null:
			out[k] = extra
			return out
	return []


## 稀有度地板线(numbers.md §8.0:12.5 分/拍·◆ × 购买价)。
func _floor_for(rarity: String) -> int:
	match rarity:
		"common":
			return 50
		"uncommon":
			return 75
		"rare":
			return 110
	return 50


## 与 tools/probbook.py::_qualified **同一份**筛(教学关与探针会话不算真人局)。
func _qualified_logs() -> Array:
	var out: Array = []
	for sub in ["", "/sent"]:
		var dir: String = "user://tape" + String(sub)
		var d: DirAccess = DirAccess.open(dir)
		if d == null:
			continue
		for name in d.get_files():
			if not String(name).ends_with(".jsonl"):
				continue
			var path: String = dir + "/" + String(name)
			if _is_qualified(path):
				out.append(path)
	return out


func _is_qualified(path: String) -> bool:
	var lines := _read_jsonl(path)
	if lines.is_empty() or String(lines[0].get("e", "")) != "run":
		return false
	var head: Dictionary = lines[0]
	if bool(head.get("tutorial", false)):
		return false
	var sess = head.get("sess", {})
	if sess is Dictionary and int(sess.get("id", 0)) == -1:
		return false
	var acts := 0
	var intro := 0
	var last_ms := 0
	for l in lines:
		var e := String(l.get("e", ""))
		if e == "intro":
			intro += 1
		elif e == "pick" or e == "swap" or e == "disc":
			acts += 1
		last_ms = maxi(last_ms, int(l.get("ms", 0)))
	return intro > 0 and last_ms > 60000 and acts >= 5


func _read_jsonl(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var out: Array = []
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		var d = JSON.parse_string(line)
		if d is Dictionary:
			out.append(d)
	return out


## 一局 → 可重放的拍。每拍产出 {res, ctx} —— `res` 由 settle.cards 重建,
## `ctx` 由 beat/settle 记下的**事实**拼回。
func _beats_of(path: String) -> Array:
	var lines := _read_jsonl(path)
	var out: Array = []
	var dur := 8.0
	var coins := 0
	var cache: Array = []
	var phrase_idx := 0
	var swaps := 0
	var last_disc_at := -1.0
	var prev_kind := -99
	var sec_target := 0
	var sec_idx := 0
	var sec_score := 0
	var held := {}                     # 玩家**当时**的持仓(buy 加 / repl 换, 与 probbook 同口径)
	for l in lines:
		var e := String(l.get("e", ""))
		if e == "buy" and l.has("id"):
			held[String(l["id"])] = true
		elif e == "repl":
			held.erase(String(l.get("out", "")))
			if String(l.get("in", "")) != "":
				held[String(l["in"])] = true
		elif e == "sec":
			sec_target = int(l.get("target", 0))
			sec_idx = int(l.get("i", 0))
			sec_score = 0
		elif e == "beat":
			# ⚑ **上一拍结算时的缓存 = 这一拍开局的缓存**(2026-08-28 修):缓存跨拍保留,
			# 而 Tape 只在 `beat` 记快照、`settle` 不记。此前拿**本拍拍首**的快照当结算态,
			# 而玩家每拍平均交换 1.0 次(tau.py)⇒ 和弦/排练/替补/包厢/和声五张读数无效。
			# 用下一拍的快照 = **游戏自己记的事实**,比从 swap 事件推演可靠。
			# ⚠ 只在**同一 section 内**回填:跨段那一拍后面还夹着结算与商店。
			if not out.is_empty() and int(out[-1]["sec"]) == sec_idx:
				out[-1]["ctx"]["cache_cards"] = _cards_of(l.get("cache", []))
				out[-1]["cache_exact"] = true
			dur = float(l.get("dur", 8.0))
			coins = int(l.get("coins", 0))
			cache = _cards_of(l.get("cache", []))
			phrase_idx = int(l.get("p", 0))
			swaps = 0
			last_disc_at = -1.0
		elif e == "swap":
			swaps += 1
		elif e == "disc":
			last_disc_at = maxf(last_disc_at, float(l.get("at", 0.0)))
		elif e == "settle":
			var cards := _cards_of(l.get("cards", []))
			if cards.size() < 5:
				prev_kind = int(l.get("kind", -99))
				continue
			var res := Pattern.evaluate_best(cards)
			res["hidden_scoring"] = 0
			var act := float(l.get("act", 0.0))
			out.append({
				"res": res,
				"held": held.keys(),
				"sec": sec_idx,
				"cache_exact": false,
				"ctx": {
					"prev_kind": prev_kind,
					"prev_target_hit": false,
					"rolled_suit": -1,
					"callout_unsolved": false,
					"luck_rolls": [],
					"odds_mult": 1.0,
					"cache_rank_sum": 0,
					"acted_late": bool(l.get("late", false)),
					"discards": int(l.get("disc", 0)),
					"coins": coins,
					"phrase_idx": phrase_idx,
					"cache_cards": cache,
					# Tape 没记这两项 —— 见文件头 NO_CTX
					"early_finish": false,
					"seconds_left": 0.0,
					"acted_final": act >= dur - 1.0,
					"early_discards": last_disc_at >= 0.0 and last_disc_at < 4.0,
					"section_idx": sec_idx,
					"swaps": swaps,
					"discard_batch_max": int(l.get("disc", 0)),
					"faces_discarded": 0,
					"swapped_scoring": 0,
					"section_score": sec_score,
					"section_target": sec_target,
					"mod": String(l.get("mod", "")),
					"first_kind": -99,
					"request_met": bool(l.get("request_ok", true)),
					"patch_restored": false,
				},
			})
			sec_score += int(l.get("score", 0))
			prev_kind = int(l.get("kind", -99))
	return out


## "6H" / "10D" / "QS" → Card。花色表 = core/card.gd 的 SUITS(C/D/H/S)。
func _cards_of(arr) -> Array:
	var out: Array = []
	if not (arr is Array):
		return out
	for s in arr:
		var t := String(s)
		if t.length() < 2:
			continue
		var su := Card.SUITS.find(t.substr(t.length() - 1, 1))
		if su < 0:
			continue
		var rl := t.substr(0, t.length() - 1)
		var r := 0
		match rl:
			"J":
				r = 11
			"Q":
				r = 12
			"K":
				r = 13
			"A":
				r = 14
			_:
				r = int(rl)
		if r >= 2:
			out.append(Card.new(r, su))
	return out
