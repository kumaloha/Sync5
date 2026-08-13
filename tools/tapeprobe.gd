extends SceneTree

## 打点契约回归。Run(有违规就非零退出):
##   godot --headless --path . --script res://tools/tapeprobe.gd
##
## 为什么单独一个探针:`flow_probe.gd` 只打拍、**从不弃牌**, 所以 disc/deny
## 整条路径在自动回归里是盲区 —— 而 disc 恰好扛着日志最关键的性质。
##
## 守的不变量(全部是「日志能不能重放出局面」这一件事的分解):
##   1. disc 必须同时记 cards(弃掉的)与 got(补进来的), 长度都 == n。
##      **补牌是随机的, 少了 got 就推不出来** —— 一拍内第一次弃牌之后手牌即断链,
##      而那正是同拍后续动作发生时的局面。行为克隆要的 (s,a) 全卡在这里。
##   2. got ∩ cards = ∅(补的不可能是刚弃掉的那几张)。
##   3. 失败动作也要留痕(deny), 只记成交会把「想弃但弃不起」整个漏掉。
##   4. 流的形状:首事件 run / 末事件 close / 序号连续 / sec 不跳段。
##
## ⚠ 改这个探针要做 A/B 验证(注入假 bug 确认它真报警), 项目铁律。

var _scene: Node
var _f := 0
var _did := false
var _wait := 0
var _bugs := 0


func _bug(msg: String) -> void:
	_bugs += 1
	print("[tape] BUG: ", msg)


func _initialize() -> void:
	get_root().set_content_scale_size(Vector2i(720, 1280))
	_scene = load("res://view/phrase.tscn").instantiate()
	get_root().add_child(_scene)


func _process(_d: float) -> bool:
	_f += 1
	if _f == 4:
		_scene._on_home_start()
		return false
	if _f == 8:
		_scene.choose_character(0)
		return false
	if _f < 12:
		return false
	# 公示卡会推迟 phrase 创建, 先把它点掉
	if _scene.intro != null and is_instance_valid(_scene.intro) and _scene.intro.visible:
		_scene.intro._dismiss()
		return false
	if not _did:
		if _scene.phrase == null or _scene.state != 2:     # 2 = St.DECISION
			return false
		_did = true
		# ⚠⚠ **必须先把脸清掉**(2026-08-13 修的间歇性假红)。
		# 这个探针要做**两次**弃牌动作(跨区多选 + 单张直弃), 而第一轮的脸里
		# 「一口气」`onetake` 是 `discard_action_limit: 1` —— 掷到它时第二次弃牌
		# 被 core **正确地**拒绝, 于是 `expected 2 discards, saw 1` 报一个不存在的 bug。
		# 抽中概率 1/8, 所以它**平均八次跑绿七次** —— 这种门比永远红的门更坏:
		# 红的时候没人知道该信谁(我第一次撞上它时先去查了自己当天的改动)。
		# 探针验的是**打点管线**, 不是打点与脸的交互 —— 让一个无关变量决定门的颜色
		# 是仪器缺陷。清脸即确定化;脸与打点的交互由 `flow_probe` 那边覆盖。
		_scene.run.run_faces = {}
		_scene.phrase.mod = ""
		# 点选:选中 → 取消 → 跨区再选(这三下原本在日志里完全不可见)
		_scene.hand._decide = true
		_scene.hand._on_hand_tap(1)
		_scene.hand._on_hand_tap(1)                        # 同一张再点 = 取消
		_scene.hand._on_cache_card_tap(0)
		_scene._on_hand_discard([0, 2], [1])               # 跨区多选:手牌 2 + 缓存 1
		_scene._on_hand_single_discard("hand", 4)          # 单张直弃
		_scene._on_hand_discard([], [])                    # 空选 -> deny
		_scene._on_hand_swap(0, 0)
		_scene._on_hand_sort()
		_replace_flow()
		return false
	_wait += 1
	if _wait <= 3:
		return false
	var n := Tape.events().size()
	_audit()
	# 先落盘再退出 —— quit() 不会等 PREDELETE, 不 flush 这一局就只活在内存里,
	# 「日志真的写得出来」这件事就没被验证过(踩过:以为验过了, 文件其实是空的)
	Tape.flush()
	print("[tape] %d events, %d bugs" % [n, _bugs])
	quit(1 if _bugs > 0 else 0)
	return true


## 满槽替换:进入 → 取消。**后 3 次商店 100% 是这个场景**, 而它原本零打点。
## 直捅内部把四个槽填满(探针惯例), 否则要打三段才够得着。
func _replace_flow() -> void:
	var pool: Array = Joker.pool()
	var sup: Array = []
	for j in pool:
		if j.kind == "support":
			sup.append(j)
	if sup.size() < 5:
		_bug("not enough support jokers to exercise the replace flow")
		return
	_scene.run.joker_slots[0] = null
	for k in range(1, 4):
		_scene.run.joker_slots[k] = sup[k - 1]
	_scene.state = 4                       # 4 = St.DRAFT
	_scene._on_shop_replace(sup[4])        # 点了满槽的第 5 张 -> 进入替换态
	_scene._on_slot_tapped(0)              # 点 Target 槽 = 取消
	_scene.state = 2                       # 还原, 别影响后面的帧


func _audit() -> void:
	var ev: Array = Tape.events()
	if ev.is_empty():
		_bug("no events at all")
		return
	if String(ev[0]["e"]) != "run":
		_bug("stream does not open with `run` (got %s)" % ev[0]["e"])
	for i in range(ev.size()):
		if int(ev[i]["n"]) != i:
			_bug("sequence broken at %d (n=%s)" % [i, ev[i]["n"]])
			break
	var secs: Array = []
	var discs: Array = []
	var picks: Array = []
	var denies := 0
	var swaps := 0
	var sorts := 0
	var intros := 0
	var ropen := 0
	var roff := 0
	for e in ev:
		match String(e["e"]):
			"sec": secs.append(int(e["i"]))
			"disc": discs.append(e)
			"pick": picks.append(e)
			"deny": denies += 1
			"swap": swaps += 1
			"sort": sorts += 1
			"intro": intros += 1
			"repl_open": ropen += 1
			"repl_off": roff += 1
	for i in range(secs.size()):
		if secs[i] != i:
			_bug("sec index jumped: %s" % str(secs))
			break

	# --- 核心:重放链 ---
	if discs.size() != 2:
		_bug("expected 2 discards, saw %d" % discs.size())
	for d in discs:
		# 用 get 带哨兵值:字段整个消失时也要报警, 而不是让探针自己炸掉或静默放过
		var k := int(d.get("k", -1))
		var gone: Array = d.get("cards", [])
		var got: Array = d.get("got", [])
		if gone.size() != k:
			_bug("disc records %d discarded labels, k=%d" % [gone.size(), k])
		if got.size() != k:
			_bug("disc records %d refilled labels, k=%d — 少了 got 就重放不出局面" % [got.size(), k])
		for lbl in got:
			if gone.has(lbl):
				_bug("refill %s is a card that was just discarded" % lbl)
	if denies == 0:
		_bug("an empty-selection discard left no `deny` trace")
	if swaps == 0:
		_bug("swap left no trace")
	if sorts == 0:
		_bug("sort left no trace")
	if intros == 0:
		_bug("the intro card closing left no trace (skip vs timeout is a real signal)")
	# 「看了但没换」—— 只记成交就分不出「换不起」和「不值得换」
	if ropen == 0:
		_bug("entering the replace flow left no trace")
	if roff == 0:
		_bug("cancelling the replace flow left no trace")

	# --- 点选:选中/取消必须分得出来, 否则「选了又改主意」等于没记 ---
	if picks.size() != 3:
		_bug("expected 3 picks (select / deselect / cross-zone), saw %d" % picks.size())
	var want := [{"z": "hand", "i": 1, "on": true},
		{"z": "hand", "i": 1, "on": false},
		{"z": "cache", "i": 0, "on": true}]
	for i in range(mini(picks.size(), want.size())):
		var p: Dictionary = picks[i]
		var w: Dictionary = want[i]
		if String(p.get("z", "")) != w["z"] or int(p.get("i", -1)) != w["i"] \
				or bool(p.get("on", not w["on"])) != w["on"]:
			_bug("pick %d = %s, expected %s" % [i, JSON.stringify(p), JSON.stringify(w)])
