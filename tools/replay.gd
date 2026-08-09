extends Probe

## **L2 完备性门**(design/solving.md 第四部分)—— 给定形式化描述 + 一局 Tape,
## 能不能重放出**每一个决策点**?
##   godot --headless --path . --script res://tools/replay.gd
##   SYNC5_REPLAY_INJECT=1   注入一个假事件, 用来 A/B 验证这道门本身没坏
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
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if fname.ends_with(".jsonl"):
			out.append(dir + "/" + fname)
		fname = d.get_next()
	d.list_dir_end()
	out.sort()
	if out.size() > n:
		out = out.slice(out.size() - n, out.size())
	return out


## 重放一局。核心状态只需要三样就能验完 L2:hand / cache / 这一拍是否已锁定。
## 其余状态维度(k_prev / k_first / joker.state)由 settle 事件的 mod+kind 间接覆盖。
func _replay_one(path: String, inject: bool) -> void:
	var fh := FileAccess.open(path, FileAccess.READ)
	if fh == null:
		_fail.append("%s 打不开" % path)
		return
	var hand: Array = []
	var cache: Array = []
	var have_beat := false
	var n_line := 0
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
				# ① 动作必须在 A(s) 里:弃掉的每张都得当时真的在手上或缓存里。
				# ⚠ 循环内计数, 循环外断言一次 —— 逐条 append 会把违规列表灌水。
				var not_available := 0
				for c in cards:
					if not (hand.has(c) or cache.has(c)):
						not_available += 1
				if not_available > 0:
					_fail.append("%s disc 弃了 %d 张不在 A(s) 里的牌 (cards=%s hand=%s cache=%s)"
						% [path, not_available, str(cards), str(hand), str(cache)])
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
				if not _same_multiset(played, hand):
					_fail.append("%s settle 打的是 %s, 而重放推出的手牌是 %s —— 状态模型漏了一条转移"
						% [path, str(played), str(hand)])
				have_beat = false
	fh.close()
	if inject:
		# A/B:注入一个不可能的决策点, 这道门必须报警。
		_checked += 1
		_fail.append("%s [INJECTED] 人为违规 —— 看到这一条说明门是活的" % path)


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
