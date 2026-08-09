class_name Tape
extends RefCounted

## 游玩打点(telemetry)。一次 run = 一条事件流,落盘成 JSONL(一行一条)。
##
## **为什么要**:sim 打的是机器人,而 SECTION_TARGETS 2026-08-05 起已经换成
## **人锚**——真人这一侧至今没有账本。G/D 对抗校准(`design/history_adversarial.md`/17)的 loss 要拿
## 真人实测跟预测对账,这个模块就是那份实测数据的来源。第二用途是流程 QA:
## flow_probe 只能在 headless 里守不变量,真人手里的异常(连点跳段那类)只能
## 靠事件序列回看。第三是经济/手感调参——弃了几张、什么时候动手、想买没买起。
##
## **边界**(与 core/ 铁律一致):不含时钟(毫秒由 Time 静态取,且可注入)、
## 不 import view、除 Card/Joker 外不认识任何游戏对象。打点**只在编排器**
## (view/phrase.gd)调用,和「金币/装槽等经济动作只发生在编排器」同一条线——
## 组件各打各的必然打重、打漏。
##
## **不打什么**:每帧计时、动画、渲染、指针移动。只打**决策与状态转移**,
## 一局 ≈ 75-200 行 ≈ 11-30KB。密度高一档就再也没人愿意长期开着它。
##
## 与既有规格的对账:事件表覆盖 design/telemetry.md 的 Phrase/Section/Run 三级清单
## (「候选牌去向」不适用——机制已作废;「near miss 类型」没做,那要现算差一张
## 能成什么, 太重, 需要时从 hand + best0 离线补算)。`design/history_parametric.md` §4 表一是 **sim 侧**
## 机器人遥测, 不是这条流;但字段可对上:三桶里的 chips 加法和 = base − chips、
## 奖励分和 = bonus、log-mult 和 = ln(mult), 段级量从 sec_end 直接读。
##
## 用法:
##   Tape.begin({...})          开一条流(会先把上一条冲干净)
##   Tape.on("beat", {...})     打一条
##   Tape.close({...})          收尾 + 落盘
## 半途退出的 run **没有 close 事件**——那本身就是信号(玩家中途弃局)。

# 事件表(e 字段)。每条都自带 n(序号)/ms(run 内相对毫秒)/e(事件名):
#
#   run     开局        char, faces, targets, struct, coins
#   sec     进段        i, target, face, wall, coins
#   sec_end 段末判定    i, score, target, ok, coins, beats
#   beat    起拍        i, p, dur, coins, hand, cache
#   settle  结算        kind, chips, base, mult, bonus, score, coin,
#                       total, disc, late, act, cards, fired
#   intro   公示卡关闭  skip(true=玩家点掉的 / false=等它自己走完)
#   pick    点选        z(hand/cache), i, on(true=选中 false=取消), at
#   disc    弃牌        k(张数), h, c, cost, coins, cards(弃掉的), got(补进来的), at
#   swap    对调        h, c, at
#   sort    理牌        at
#   deny    动作被拒    why, k, at         (钱不够/空选/买不起/刷不起/替换差钱)
#   shop    开店        mid, sec, coins, offer, slots, left, need
#   buy     买入        id, kind, price, coins
#   repl_open 进入替换  id, price, coins, slots
#   repl_off  取消替换  id, coins          (「看了但没换」—— 只记成交会漏掉它)
#   repl    满槽替换    in, out, slot, price, back, coins
#   rerl    刷新        k(第几次), cost, coins
#   focus   切前后台    on, at             (失焦那一拍的时间数据是脏的)
#   leave   继续▸       coins
#   nav     界面跳转    to                 (home/pick/win/lose/retry/back)
#   close   run 终      ok, sec, score, target, beats

## 每条事件的元字段。payload 不许用这三个键(用了会被覆盖, on() 会报错)。
const RESERVED := ["n", "ms", "e"]

static var _cfg: Dictionary = DB.tape()

static var enabled: bool = bool(_cfg["enabled"])
static var to_file: bool = bool(_cfg["to_file"])
static var dir: String = String(_cfg["dir"])
static var max_events: int = int(_cfg["max_events"])
static var _mute: Dictionary = _mute_set()

## 测试注入:>= 0 时 _now() 直接返回它,毫秒就不再依赖真实时钟。
static var clock_ms := -1

static var _buf: Array = []          # 尚未落盘的事件
static var _seq := 0
static var _t0 := 0
static var _path := ""
static var _run_id := ""
static var _nth := 0                 # 本进程内第几局 —— run_id 只到秒, 见 _stamp()


static func _mute_set() -> Dictionary:
	var out := {}
	for k in _cfg["mute"]:
		out[String(k)] = true
	return out


static func _now() -> int:
	if clock_ms >= 0:
		return clock_ms
	return Time.get_ticks_msec() - _t0


## 开一条新流。返回 run_id("" = 打点关着)。
## 缓冲会清空 —— 开局前那几条 nav(首页/选角)不属于任何一局, 有意丢掉,
## 这样一个 run 文件永远以 `run` 事件开头。
static func begin(meta: Dictionary = {}) -> String:
	if not enabled:
		return ""
	flush()                     # 上一局的尾巴不许跟着走
	_buf.clear()
	_seq = 0
	_t0 = Time.get_ticks_msec()
	_run_id = _stamp()
	_path = "%s/run_%s.jsonl" % [dir, _run_id]
	on("run", meta)
	return _run_id


static func run_id() -> String:
	return _run_id


static func path() -> String:
	return _path


## 打一条事件。关掉打点或该事件被 mute 时是一次 dict 查表,别的什么都不做。
static func on(kind: String, payload: Dictionary = {}) -> void:
	if not enabled or _mute.has(kind):
		return
	var e: Dictionary = payload.duplicate()
	# 元字段最后写 —— payload 撞名也盖不掉序号和时间。
	# ⚠ 但「盖不掉」是**静默**的:disc 事件曾用 `n` 装弃牌张数, 被序号吃掉了整整一轮,
	# 而 cost 恰好等于张数, 输出看上去还是对的。所以撞名必须当场喊出来。
	for k in RESERVED:
		if payload.has(k):
			push_error("[Tape] `%s` 事件的 payload 用了保留字 `%s` —— 它会被元字段覆盖, 换个键名" % [kind, k])
	e["n"] = _seq
	e["ms"] = _now()
	e["e"] = kind
	_seq += 1
	_buf.append(e)
	if _buf.size() >= max_events:
		if to_file:
			flush()
		else:
			_buf.pop_front()    # 纯内存模式退化成环形缓冲,长会话不吃内存


## run 收尾。半途退出**不会**走到这里,这是有意的。
## 收尾后关掉落盘口:结算屏之后玩家还会点「返回主页」之类,那些 nav 不属于
## 这一局 —— 不关的话它们会继续追加进已经收尾的文件,末行就不是 close 了。
static func close(payload: Dictionary = {}) -> void:
	on("close", payload)
	flush()
	_path = ""


## 落盘(追加)。to_file 关着时是空操作,缓冲原样留着给测试/工具读。
static func flush() -> void:
	if not to_file or _buf.is_empty() or _path == "":
		return
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(_path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		push_error("[Tape] cannot open %s" % _path)
		return
	f.seek_end()
	for e in _buf:
		f.store_line(JSON.stringify(e))
	f.close()
	_buf.clear()


## 当前缓冲(测试与工具的读口)。
static func events() -> Array:
	return _buf


## 运行时改 mute(测试与临时调试用;正式口径改 data/tape.json)。
static func set_mute(kinds: Array) -> void:
	_mute = {}
	for k in kinds:
		_mute[String(k)] = true


## 把打点恢复到出厂状态 —— 测试之间互不串味。
static func reset() -> void:
	_buf.clear()
	_seq = 0
	_t0 = 0
	_path = ""
	_run_id = ""
	clock_ms = -1


# ---- 序列化助手:日志里只放标签和 id,不放对象 ----

## [Card] -> ["AS", "10H", ...]
static func cards(arr: Array) -> Array:
	var out: Array = []
	for c in arr:
		if c != null:
			out.append(c.label())
	return out


## joker 槽 -> ["mono", "", "vinyl", ""],空槽保留占位所以槽序读得出来
static func slots(arr: Array) -> Array:
	var out: Array = []
	for j in arr:
		out.append("" if j == null else String(j.id))
	return out


## 结算 popup(slot 制)-> 触发者 id;slot -1 = 主角
static func fired(popups: Array, slot_arr: Array) -> Array:
	var out: Array = []
	for p in popups:
		var s := int(p.get("slot", -99))
		if s < 0:
			out.append("@character")
		elif s < slot_arr.size() and slot_arr[s] != null:
			out.append(String(slot_arr[s].id))
	return out


## run_id = 秒级时间戳 + 进程内序号。序号不是装饰:时间戳只到秒, 而工具
## (flow_probe / 截图探针)一秒能开好几局 —— 少了它两局会**追加进同一个文件**,
## 一个文件里出现两条 `run` 事件, 下游按「一文件一局」读就全错。
static func _stamp() -> String:
	var s := Time.get_datetime_string_from_system(true)
	_nth += 1
	return "%s_%02d" % [s.replace("-", "").replace(":", ""), _nth]
