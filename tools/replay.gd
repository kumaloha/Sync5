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
	print("=== L2 决策重放:%d 个决策点,%d 处违规 ===" % [_checked, _fail.size()])
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
				# 理牌 = 确定性重排, 不改集合。重放不跟踪顺序, 但它必须不改变**集合**,
				# 所以这里只计一个决策点 —— 真正的检查在下一条 settle 上。
				_checked += 1
			"settle":
				if not have_beat:
					continue
				_checked += 1
				# ⚑ **这是 L2 最硬的一条**:若状态模型完备, 我们推导出的 hand
				# 必须和实际计分的 5 张**逐张相同**(集合意义)。
				# 对不上 = 形式化漏了一条会改手牌的转移。
				var played := _arr(d.get("cards", []))
				if spot == "":
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
	var x := a.duplicate()
	var y := b.duplicate()
	x.sort()
	y.sort()
	return x == y
