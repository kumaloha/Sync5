extends Probe

## **L2 完备性门**(docs/design/solving.md 第四部分)—— 给定形式化描述 + 一局 Tape,
## 能不能重放出**每一个决策点**?
##   godot --headless --path . --script res://tools/replay.gd
##   SYNC5_REPLAY_INJECT=1   篡改每局第一条弃牌(弃一张不在手上的牌), 断言门恰好多报一条 —— A/B 验门本身没坏
##
## **和 tapeprobe 的分工**:`tapeprobe` 验「日志能不能重放出**局面**」(采集侧完整性);
## 本探针验「文档能不能重放出**决策问题**」(建模侧完整性)。
## 判据:每个决策点必须能唯一确定 `s` / `A(s)` / `o(s)`。
## 漏一个状态维度 → 撞上「这个动作不在 A(s) 里」或「两个不同局面映射到同一个 s」。
##
## ⚠ **非零退出**。一道不会红的门等于没有门。
## ⚠ **这道门自己必须做 A/B** —— 注入假 bug 确认它真的报警。这个项目写过一条**假的**守卫:
## 注入误判照样全绿(测试卡是成长牌、计数器为 0, 根本没走到那条路径)。

var _fail: Array = []
var _checked := 0
## 状态推不出来因而**跳过**的拍数(旧 Tape 的 `rsfl` 没记洗后局面)。
## ⚑ 单独计数而不是当成通过 —— 「一道只验了 3 张却看起来像全量绿的门, 比慢半小时危险得多」。
var _skipped := 0


func _initialize() -> void:
	var dir := "user://tape"
	var files := _newest_logs(dir, 5)
	if files.is_empty():
		push_error("[replay] %s 下没有日志 —— 先跑一次 tools/flow_probe.gd" % dir)
		quit(1)
		return
	var inject := Probe.flag("SYNC5_REPLAY_INJECT")
	for f in files:
		_replay_one(f, inject)
	print("=== L2 决策重放:%d 个决策点,%d 处违规%s ===" % [_checked, _fail.size(),
		("" if _skipped == 0 else ",%d 拍状态不可知已跳过(旧 Tape 的洗牌没记局面)" % _skipped)])
	for m in _fail:
		print("  x ", m)
	quit(1 if _fail.size() > 0 else 0)


## 取最近的 n 个日志。⚠ 只取最近的 —— 老日志的结构参数可能和当前不同
## (`run` 事件里记了 struct 就是为了这个), 拿它们验今天的建模会假红。
func _newest_logs(dir: String, n: int) -> Array:
	var d := DirAccess.open(dir)
	if d == null:
		return []
	var out: Array = []
	# 回传成功的日志在 sent/ 子目录(core/uplink.gd 的记账方式)—— 两处都扫(2026-08-21 审查)
	for sub in ["", "/" + Uplink.SENT_SUBDIR]:
		var dd := DirAccess.open(dir + sub)
		if dd == null:
			continue
		dd.list_dir_begin()
		var fname := dd.get_next()
		while fname != "":
			if fname.ends_with(".jsonl"):
				out.append(dir + sub + "/" + fname)
			fname = dd.get_next()
		dd.list_dir_end()
	out.sort_custom(func(a, b): return a.get_file() < b.get_file())
	# ⚠ 只要**真人局**(2026-08-21 发现:tape/ 里 3000+ 份是 flow_probe 的机器局, 没有任何弃牌/
	# 交换决策, 「最近 5 份」全是它们 ⇒ 重放连着几天在验空集而且全绿)。探针局 sess.id = -1,
	# 教学局 tutorial = true, 两种都跳过。
	var picked: Array = []
	for i in range(out.size() - 1, -1, -1):
		if _is_human_run(out[i]):
			picked.push_front(out[i])
			if picked.size() >= n:
				break
	return picked


func _is_human_run(path: String) -> bool:
	var fh := FileAccess.open(path, FileAccess.READ)
	if fh == null:
		return false
	var head = JSON.parse_string(fh.get_line())
	fh.close()
	if not head is Dictionary or String(head.get("e", "")) != "run":
		return false
	if bool(head.get("tutorial", false)):
		return false
	var sess = head.get("sess", {})
	return not (sess is Dictionary and int(sess.get("id", 0)) == -1)


## 重放一局。核心状态只需要三样就能验完 L2:hand / cache / 这一拍是否已锁定。
## 其余状态维度(k_prev / k_first / joker.state)由 settle 事件的 mod+kind 间接覆盖。
func _replay_one(path: String, inject: bool) -> void:
	var fh := FileAccess.open(path, FileAccess.READ)
	if fh == null:
		_fail.append("%s 打不开" % path)
		return
	var hand: Array = []
	var cache: Array = []
	var spot := ""
	var have_beat := false
	var n_line := 0
	var injected := false      # A/B:每局只篡改一次
	# ⚑ **装备中的小丑牌**(2026-09-01 加)。此前状态模型完全不读它, 而**有的卡会改
	# 「哪些牌参与计分」** —— 合奏 `hold.cache_scoring` 让缓存一起进池子(八选五)。
	# 真人 Tape run_20260831T203232_01 的 3 处违规就是它:n=128 换上合奏, 130/135/140
	# 三拍的计分牌里各有 1~2 张来自缓存, 而重放坚持「必须等于手牌那 5 张」。
	# ⚠ 打点没缺 —— `buy` 有 `id`, `repl` 有 `in`/`out`/`slot`, **是这边没读**。
	# (与 2026-08-10 聚光那次同形:「打点一直带着 spotlight 字段, 是状态模型没读它」。)
	var held: Dictionary = {}   # slot -> joker id;槽位不明的 buy 用负数占位
	while not fh.eof_reached():
		var line := fh.get_line()
		if line.strip_edges() == "":
			continue
		var d = JSON.parse_string(line)
		n_line += 1
		if typeof(d) != TYPE_DICTIONARY:
			_fail.append("%s:%d 不是合法 JSON" % [path, n_line])
			continue
		var e := String(d.get("e", ""))
		match e:
			"beat":
				# 锚点:一拍开始时的真实局面。
				hand = _arr(d.get("hand", []))
				cache = _arr(d.get("cache", []))
				# S4 聚光 boon 的第六张(2026-08-10 抓到的重放缺口:打点没漏 ——
				# beat 事件一直带着 spotlight 字段 —— 是这边的状态模型没读它)。
				spot = String(d.get("spotlight", ""))
				have_beat = true
				# A(s) 的规模在这里就该是确定的 —— 手牌 5 + 缓存 cap。
				# 缓存容量随脸变(smallstage 3→2), 所以只断言"非空且 <= cap"。
				if hand.size() != GameConfig.HAND_SIZE:
					_fail.append("%s beat#%d 手牌 %d 张, 形式化说恒 %d"
						% [path, int(d.get("i", -1)), hand.size(), GameConfig.HAND_SIZE])
				if cache.is_empty() or cache.size() > GameConfig.CACHE_CAP:
					_fail.append("%s beat#%d 缓存 %d 张, 越界"
						% [path, int(d.get("i", -1)), cache.size()])
			"rsfl":
				# 洗牌 = **整手重掷 + 弃牌堆洗回**(2026-08-26 随超级百搭加)。它把手牌和
				# 缓存全换掉, 是状态模型必须认识的一条转移 —— 而重放此前完全不认识它
				# (与合奏那次同族:规则在游戏里, 不在模型里, 第 N 次)。
				# ⚠ **旧 Tape 没记新局面**(那时 `rsfl` 只有 cost/at), 重放**推不出来**。
				# 那种情况下**不许假装还知道状态** —— 把 `have_beat` 落下, 让这一拍剩下的
				# 检查全部跳过, 并计一笔 `_skipped`(no silent caps:跳过多少要印出来)。
				if not have_beat:
					continue
				if d.has("hand"):
					hand = _arr(d.get("hand", []))
					cache = _arr(d.get("cache", []))
					_checked += 1
				else:
					have_beat = false
					_skipped += 1
			"buy":
				# 槽位不明(买入事件不记装到哪个槽), 用递减的负键占位 —— 我们只需要
				# 「持有集合」这一个事实, 不需要知道它在第几格。
				held[-held.size() - 1] = String(d.get("id", ""))
			"repl":
				var sl := int(d.get("slot", -1))
				# 换下来的那张要真的走掉:先按 id 删一个占位键, 再把新卡写进槽位。
				var gone := String(d.get("out", ""))
				for k2 in held.keys():
					if String(held[k2]) == gone:
						held.erase(k2)
						break
				held[sl] = String(d.get("in", ""))
			"disc":
				if not have_beat:
					continue
				var cards := _arr(d.get("cards", []))
				var got := _arr(d.get("got", []))
				_checked += 1
				# A/B(2026-08-21 评审:旧版只 append 一条假失败, 检查逻辑一行没走到 ——
				# 「注入误判照样全绿的假守卫」同形):**真的篡改**这条弃牌, 让它弃一张不在
				# A(s) 里的牌, 然后断言 ① **恰好**多报一条;推进状态用的仍是原始 cards。
				var checked_cards := cards
				var fails_before := _fail.size()
				var inject_now := inject and not injected and not cards.is_empty()
				if inject_now:
					injected = true
					checked_cards = cards.duplicate()
					checked_cards[0] = "??"
				# ① 动作必须在 A(s) 里:弃掉的每张都得当时真的在手上或缓存里。
				# ⚠ 循环内计数, 循环外断言一次 —— 逐条 append 会把违规列表灌水。
				var not_available := 0
				for c in checked_cards:
					if not (hand.has(c) or cache.has(c)):
						not_available += 1
				if not_available > 0:
					_fail.append("%s disc 弃了 %d 张不在 A(s) 里的牌 (cards=%s hand=%s cache=%s)"
						% [path, not_available, str(checked_cards), str(hand), str(cache)])
				if inject_now:
					if _fail.size() != fails_before + 1:
						_fail.append("%s [INJECTED] 门是死的:篡改了弃牌却没有恰好多报一条" % path)
					else:
						_fail[_fail.size() - 1] = "%s [INJECTED] 人为违规被抓到 —— 门是活的" % path
				# ② 补牌张数必须等于弃牌张数 —— 手牌恒 5、缓存恒满是形式化的硬约束。
				if got.size() != cards.size():
					_fail.append("%s disc 弃 %d 补 %d, 破坏「手牌恒 5 缓存恒满」"
						% [path, cards.size(), got.size()])
				# ③ 原位替换:推进状态。
				var gi := 0
				for c in cards:
					var at := hand.find(c)
					if at >= 0:
						hand[at] = got[gi] if gi < got.size() else ""
					else:
						at = cache.find(c)
						if at >= 0:
							cache[at] = got[gi] if gi < got.size() else ""
					gi += 1
			"swap":
				if not have_beat:
					continue
				_checked += 1
				var h := int(d.get("h", -1))
				var c2 := int(d.get("c", -1))
				if h < 0 or h >= hand.size() or c2 < 0 or c2 >= cache.size():
					_fail.append("%s swap(%d,%d) 下标越界(hand=%d cache=%d)"
						% [path, h, c2, hand.size(), cache.size()])
				else:
					var t = hand[h]
					hand[h] = cache[c2]
					cache[c2] = t
			"sort":
				# ⚠⚠ **必须真的排**(2026-09-01 修)。这里原本什么都不做, 注释写着
				# 「理牌不改集合, 所以只计一个决策点」—— **那句话对集合成立, 对下标不成立**:
				# `swap` 事件记的是 `hand[h] ↔ cache[c]` 的**下标**, 理牌一重排,
				# 之后每一次对调在重放里都换错了牌 ⇒ 手牌集合当场分叉。
				# 真人 Tape run_20260831T203232_01 的 3 处违规全是这个形状(那一局有 2 次
				# 理牌、36 次对调)。⇑ 比较器走 `Card.sort_desc`, 与 `Phrase.sort_hand` 同一份。
				if not have_beat:
					continue
				_checked += 1
				var cs: Array = []
				for lb in hand:
					cs.append(Card.from_label(String(lb)))
				cs.sort_custom(Card.sort_desc)
				hand.clear()
				for c3 in cs:
					hand.append(c3.label() if c3.rank >= 0 else "")
			"settle":
				if not have_beat:
					continue
				_checked += 1
				# ⚑ **这是 L2 最硬的一条**:若状态模型完备, 我们推导出的 hand
				# 必须和实际计分的 5 张**逐张相同**(集合意义)。
				# 对不上 = 形式化漏了一条会改手牌的转移。
				var played := _arr(d.get("cards", []))
				# 合奏在场 ⇒ 计分池扩到 hand ∪ cache(卡面:best five of eight)。
				# 与聚光那支同一条纪律:**重放不重推「最佳」**(那依赖规则牌), 只断言
				# 打出的五张是池子的合法子多重集 —— L2 管转移合法, 选得对不对归单测。
				var pool_extra: Array = []
				for jd in DB.jokers():
					if not held.values().has(String(jd.get("id", ""))):
						continue
					if int((jd.get("hold", {}) as Dictionary).get("cache_scoring", 0)) > 0:
						pool_extra = cache.duplicate()
						break
				if spot == "" and not pool_extra.is_empty():
					var pool3: Array = hand.duplicate()
					pool3.append_array(pool_extra)
					var miss3 := 0
					for c4 in played:
						var at4: int = pool3.find(c4)
						if at4 >= 0:
							pool3.remove_at(at4)
						else:
							miss3 += 1
					if played.size() != GameConfig.HAND_SIZE or miss3 > 0:
						_fail.append("%s settle(合奏) 打的 %s 不是 hand+cache(%s + %s) 的合法五张"
							% [path, str(played), str(hand), str(cache)])
				elif spot == "":
					if not _same_multiset(played, hand):
						_fail.append("%s settle 打的是 %s, 而重放推出的手牌是 %s —— 状态模型漏了一条转移"
							% [path, str(played), str(hand)])
				else:
					# 聚光拍:结算 = 手牌 5 + 聚光牌里取最佳 5。重放不追踪 deck.rules
					# (「最佳」依赖规则牌), 所以不重推最佳, 只断言**合法性**:
					# 打出的 5 张必须是 hand ∪ {spotlight} 的子多重集 —— L2 管的是
					# 转移合法, 「选得对不对」由 t_boon 的单元契约守。
					var pool: Array = hand.duplicate()
					pool.append(spot)
					var missing := 0
					for c in played:
						var at2: int = pool.find(c)
						if at2 >= 0:
							pool.remove_at(at2)
						else:
							missing += 1
					if played.size() != GameConfig.HAND_SIZE or missing > 0:
						_fail.append("%s settle(聚光) 打的 %s 不是 hand+spotlight(%s + %s) 的合法五张"
							% [path, str(played), str(hand), spot])
				have_beat = false
	fh.close()
	if inject and not injected:
		# 这局没有任何弃牌可篡改 —— 明说, 别让 A/B 静默变成「没注入也绿」
		_fail.append("%s [INJECTED] 无弃牌事件可篡改, 本局 A/B 未执行" % path)


func _arr(v) -> Array:
	var out: Array = []
	if typeof(v) == TYPE_ARRAY:
		for x in v:
			out.append(String(x))
	return out


## 多重集相等 —— 顺序无关, 因为理牌会重排而那不改变决策问题。
func _same_multiset(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	# ⚠⚠ **万能牌是替身, 不能逐张比**(2026-09-01 修)。超级百搭往牌堆注 4 张万能牌
	# (★/☆), 而 Tape 的 `settle.cards` 记的是**计分的五张** —— 万能牌在那里已经被顶成
	# 了具体的牌(实测 ☆H → AC 凑一对 A, ☆S → 9C 凑三条 9)。重放拿原始手牌逐张比,
	# 于是每次万能牌进计分五张都报一次假违规。
	# ⇒ 先消掉能精确对上的, 剩下的由手里的万能牌一张顶一张 —— 这仍然是 L2 的判据
	# 「**转移合法**」, 「顶成哪张才最优」由 Pattern 的单测守(重放不重推最佳)。
	var pool := b.duplicate()
	var wilds := 0
	for i in range(pool.size() - 1, -1, -1):
		var lb := String(pool[i])
		if lb.begins_with("★") or lb.begins_with("☆"):
			wilds += 1
			pool.remove_at(i)
	var unmatched := 0
	for c in a:
		var at: int = pool.find(c)
		if at >= 0:
			pool.remove_at(at)
		else:
			unmatched += 1
	# 剩下没对上的必须正好由万能牌顶掉, 且不许有手牌落单。
	return unmatched == wilds and pool.is_empty()
