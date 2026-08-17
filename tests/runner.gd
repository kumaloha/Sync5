extends SceneTree

## Headless test runner. Run with:
##   godot --headless --path . --script res://tests/runner.gd
## Exit code 0 = all green, 1 = at least one failure.
##
## 用例本体按**契约归属**切在 tests/t_<域>.gd 里(一个域 = 一份契约)。
## 这里只剩:域清单 + 断言工具 + 计数 + 退出码。
## ⚠ 域清单是**显式数组**, 不扫目录 —— 目录扫描会让「漏登记了一个域」在 diff 里
## 看不见, 而少跑 30 条用例的套件**照样是绿的**。
## ⚠ **顺序即契约**:小丑牌是共享实例(vinyl/glowstick/bassline 的成长计数器跨用例
## 累积), 调换域的先后会静默改分。这个数组的顺序 = 拆分前的调用顺序。
## ⚠ 域文件**不带 class_name** —— 每加一个域就得先跑一次 `--import` 是白付的摩擦。
const DOMAINS := [
	# t_stat 放最前:纯数学, 不碰任何共享状态(自带 RNG 实例), 对下面的顺序零影响。
	"t_stat",
	"t_card", "t_deck", "t_economy", "t_pattern", "t_phrase", "t_rules",
	"t_db", "t_run", "t_shop", "t_hand", "t_face", "t_wild", "t_settle",
	"t_boon", "t_joker", "t_character", "t_solver", "t_draft", "t_tape",
	# ⚠ 新域一律**追加在末尾** —— 上面那条「顺序即契约」说的是小丑牌的成长计数器跨用例
	# 累积, 插在中间会静默改分。t_tutorial 自己不碰任何共享状态, 追加是安全的。
	"t_tutorial", "t_director", "t_ticket",
]

var _pass := 0
var _fail := 0

func _initialize() -> void:
	for d in DOMAINS:
		load("res://tests/%s.gd" % d).new().run(self)
	print("\n=== RESULT: %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  x FAIL: ", msg)

func eq(a, b, msg: String) -> void:
	check(a == b, "%s (got %s, expected %s)" % [msg, str(a), str(b)])

## 跨域共用的小工具 —— 只有真的被多个域用到的才留在这里。
## 各域自己的私有工具(_w / _face_param / _draft_snap)跟着它的域走。
func _c(rank: int, suit: int) -> Card:
	return Card.new(rank, suit)

## Target 对某牌型的倍率 —— **从 data/jokers.json 推导, 测试里不许手抄数值**。
## 2026-08-06 的实证:按实测频率把 mono ×6 / stair ×8 拉平成各 ×7 时,
## **手抄那批一次红了 10 条, 而牌型倍率那批(早就改成从 BASE_MULT 推导)一条没红**。
## 平衡数值是要反复调的, 手抄的断言等于给每次调参加一道无意义的返工。
func _tmult(joker_id: String, kind_name: String) -> float:
	for e in DB.jokers():
		if String(e["id"]) != joker_id:
			continue
		for fx in e.get("effects", []):
			var w: Dictionary = fx.get("when", {})
			if String(w.get("kind", "")) == kind_name:
				return float(fx["do"]["mult"])
			for kn in w.get("kind_in", []):
				if String(kn) == kind_name:
					return float(fx["do"]["mult"])
	return 1.0


## support 的 bonus 数额 —— 同 `_tmult` 的理由(2026-08-12 bonus 族重定价
## 一次红了 9 条手抄断言, 全部改推导)。
## ⚠⚠ **两个通道都要认**(2026-08-16 加分族 A 案之后)。
## 12 张卡从固定数额 `bonus` 换成了跟随尺度的 `bonus_target_pct`, 而这个助手只读前者
## ⇒ 一次红 12 条。**这正是当初写这个助手的理由**(别抄死数额), 只是它自己也要跟着
## 通道走 —— 断言从数据推导, 那「数据长什么样」变了它就得跟。
## ⚠ 换算基准必须与 `core/fx.gd` 缺 `section_target` 时的退路**一致**:
## 一局的平均每拍目标。测试调 `Settle.run(..., {})` 不带 section_target, 走的就是那条退路。
func _bonus(joker_id: String) -> int:
	for e in DB.jokers():
		if String(e["id"]) != joker_id:
			continue
		for fx in e.get("effects", []):
			var do: Dictionary = fx.get("do", {})
			if do.has("bonus"):
				return int(do["bonus"])
			if do.has("bonus_target_pct"):
				return int(round(float(do["bonus_target_pct"]) * _avg_beat_target()))
	return 0


## `per` 类卡的**总额**(n 份)—— ⚠⚠ **必须一次取整, 不能逐份取整再乘**。
## `core/fx.gd` 的算法是 `round(每拍目标 × pct × 份数)`;测试若写成
## `份数 × round(每拍目标 × pct)` 就会**逐份累积舍入误差**(串场 3 份差 1 分, 实测 455 vs 454)。
## ⚑ 差 1 分不是小事:它说明**测试和实现用了不同的算法**, 而那正是这类断言要防的。
## 实现那边是对的 —— 逐份取整会累积误差, 所以**测试跟实现走**。
func _bonus_n(joker_id: String, n: int) -> int:
	for e in DB.jokers():
		if String(e["id"]) != joker_id:
			continue
		for fx in e.get("effects", []):
			var do: Dictionary = fx.get("do", {})
			if do.has("bonus"):
				return int(do["bonus"]) * n
			if do.has("bonus_target_pct"):
				return int(round(float(do["bonus_target_pct"]) * _avg_beat_target() * float(n)))
	return 0


## 一局的平均每拍目标 —— `bonus_target_pct` 的换算基准。
## ⚑ 与 `core/fx.gd` 的退路、`tools/bot.gd::_avg_beat_target()` **三处同源**,
## 都从 `SECTION_TARGETS` 推导 ⇒ 目标分一改三处一起动, 不会漂开。
func _avg_beat_target() -> float:
	var t := 0.0
	for v in GameConfig.SECTION_TARGETS:
		t += float(v)
	var n := float(GameConfig.SECTION_TARGETS.size())
	if n <= 0.0:
		return 0.0
	return t / n / float(GameConfig.PHRASES_PER_SECTION)


## 任意 do 通道的数额(additive / additive_face_value / chips_per_card …)——
## 同上理由(2026-08-12 v3 改基牌重定价又红了 3 条手抄断言, 补这个通用口)。
func _do_amount(joker_id: String, key: String) -> float:
	for e in DB.jokers():
		if String(e["id"]) != joker_id:
			continue
		for fx in e.get("effects", []):
			if fx.get("do", {}).has(key):
				return float(fx["do"][key])
	return 0.0
