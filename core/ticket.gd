class_name Ticket
extends RefCounted

## 消耗品层(券)—— **纯逻辑, 引擎无关、不含时钟、不 import view**(CLAUDE.md 架构铁律)。
## 内容全在 `data/tickets.json`, 这里只回答:**有哪些券 · 它是什么 scope · 今天是第几天**。
##
## ⚑ **判据:适合每日清零的是「消耗品」不是「拥有物」。**
## 角色是**身份**, 到点没收像被抢;券用掉就没了本来就是它的定义, 清零天经地义。
##
## ⚠⚠ **本文件不读时钟** —— `day_index()` 的时间戳**由调用方传入**。
## 与 `core/tape.gd` 同一条纪律:自己去取当前时间会让这段逻辑**测不了**
## (测试没法造「明天」), 而每日清零这种东西不测就等于没写。


## 券系统的总开关(1.0 = false, 用户 2026-08-18 拍板「第一版去掉券」;1.1 商业化时翻 true)。
## ⚠ 闸在 SaveState 的入口层, 不在这里的纯函数 —— 纯函数要继续被 t_ticket 背书。
static func enabled() -> bool:
	return bool(DB.tickets().get("enabled", false))


static func roster() -> Array:
	return DB.tickets().get("tickets", [])


static func ids() -> Array:
	var out: Array = []
	for t in roster():
		out.append(String(t["id"]))
	return out


static func by_id(tid: String) -> Dictionary:
	for t in roster():
		if String(t["id"]) == tid:
			return t
	return {}


## 这张券作用在哪一层:`phrase` 一拍 / `shop` 一次商店 / `run` 一整局。
## ⚠ 空串 = 未知 id。调用方**必须**当错误处理, 别当默认值 —— 一个 scope 写错的券
## 会静默地在错误的时机可用, 而那不会报错。
static func scope(tid: String) -> String:
	return String(by_id(tid).get("scope", ""))


static func param(tid: String, key: String, fallback: float = 0.0) -> float:
	return float(by_id(tid).get("params", {}).get(key, fallback))


static func max_held() -> int:
	return int(DB.tickets().get("max_held", 5))


static func reset_hour() -> int:
	return int(DB.tickets().get("reset_hour", 0))


## 「第几天」—— 每日清零的判据。`unix` 由调用方给(见文件头:这里不读时钟)。
##
## ⚑ 做法 = **把清零点当成一天的起点**:先把时间往回推 `reset_hour` 小时, 再整除一天。
## 于是「今天」的定义随 `reset_hour` 一起移动, 不用在调用方写第二套减法。
## ⚠ 用**本地**时区:玩家理解的「午夜」是他自己的午夜, 不是 UTC 的。
static func day_index(unix: int) -> int:
	var local: int = unix + _tz_offset_seconds()
	@warning_ignore("integer_division")
	return int((local - reset_hour() * 3600) / 86400)


## ⚠ 时区偏移是**环境**不是时钟 —— 它不随时间流逝而变, 所以取它不违反「不含时钟」:
## 同一次运行里它是常量, 测试也能预期。真正不许做的是「自己去问现在几点」。
static func _tz_offset_seconds() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


## ---- 存储逻辑(纯函数)· 2026-08-16 ----
##
## ⚑⚑ **为什么抽出来**:这三段逻辑本来长在 `SaveState` 里, 而那边有一道
## 「探针一律 no-op」的闸 ⇒ **测试里它们全是空转, 逻辑一行都没被验过**。
## 我当时只验到了**闸**, 没验到**逻辑** —— 而闸是对的、逻辑可能是错的。
## ⇒ 抽成接字典的纯函数, `SaveState` 只负责读写盘。**和「时钟由调用方注入」同一个手法**:
## 把不可测的部分(盘、时钟、探针闸)推到边界上, 中间留下可测的纯逻辑。


## 跨天就清空券。**只动 `tickets` / `tickets_day` 两个键** —— 返回是否清过。
##
## ⚠⚠ **绝不 `clear()` 整个字典**:`runs_total` 是 `min_run`(禁回第 10 局解锁)的依据,
## 教学关标记也在同一份数据里。顺手清掉会把解锁进度一起抹了,
## **而那种 bug 只有玩了十局的人才发现得了**。
static func reset_if_new_day(data: Dictionary, today: int) -> bool:
	if int(data.get("tickets_day", -1)) == today:
		return false
	data["tickets_day"] = today
	data["tickets"] = {}
	data["ticket_rolls"] = {}    # 掷值跟着券走:券清了值还留着, 下一张同名券会继承旧值
	return true


## 发券。返回**实际**发到几张(可能被 `max_held` 截断)。
## ⚠ 未知 id 一律 0 —— 拼错的券 id 会静默地什么都不做, 所以挡在这里。
static func grant_into(held: Dictionary, tid: String, n: int) -> int:
	if n <= 0 or scope(tid) == "":
		return 0
	var cur := int(held.get(tid, 0))
	var got := mini(n, maxi(0, max_held() - cur))
	if got > 0:
		held[tid] = cur + got
	return got


## 用一张。返回**是否真的用掉了** —— 调用方必须看返回值:
## 没券却当成用掉了就是白送一次效果, 而那不会报错。
## ⚠ 用完就把键删掉, 不留 `{"overtime": 0}` —— 零值残留会让「持有几种券」这类
## 统计多数出一种, 而它同样不报错。
static func consume_from(held: Dictionary, tid: String) -> bool:
	var cur := int(held.get(tid, 0))
	if cur <= 0:
		return false
	if cur - 1 <= 0:
		held.erase(tid)
	else:
		held[tid] = cur - 1
	return true


## ---- 获得时掷值(boost)· 2026-08-17 ----
##
## ⚑ **随机放在「获得时」而不是「使用时」**(用户 2026-08-16 拍板, 写在 tickets.json):
## 拿到手就知道是 ×1.2 还是 ×2.5 ⇒ 随机产生的是**决策**(留到哪一拍), 不是结果。
## ⇒ 存储必须**每张一个值**:`data["ticket_rolls"] = {tid: [先领先用的值...]}`。
## 不变量 = **rolls 的长度 == 持有张数**(只对可掷值的券), `t_ticket` 锁着它。
## ⚠ 消耗是 FIFO —— UI 展示的「下一张」就是队首, 用掉的必须正是看到的那张。


## 这张券获得时要不要掷值。判据 = params 带 `mult_min`/`mult_max` 一对。
static func rollable(tid: String) -> bool:
	var p: Dictionary = by_id(tid).get("params", {})
	return p.has("mult_min") and p.has("mult_max")


## 掷一个值(0.1 粒度 —— 卡面要念得出「×1.7」, 三位小数念不出来)。不可掷值的券返回 0。
static func roll_for(tid: String, rng: RandomNumberGenerator) -> float:
	if not rollable(tid):
		return 0.0
	return snappedf(rng.randf_range(param(tid, "mult_min"), param(tid, "mult_max")), 0.1)


## 发券 + 掷值, **一个入口**(两条发放路径 —— 每日/手动 —— 都必须走这里)。
## 拆开走 `grant_into` 再自己补掷值, 迟早有一条路径忘补 ⇒ 不变量静默破掉。
static func grant_with_roll(data: Dictionary, tid: String, n: int, rng: RandomNumberGenerator) -> int:
	var held: Dictionary = data.get("tickets", {})
	var got := grant_into(held, tid, n)
	data["tickets"] = held
	if got > 0 and rollable(tid):
		var rolls: Dictionary = data.get("ticket_rolls", {})
		var lst: Array = rolls.get(tid, [])
		for _i in range(got):          # 只给**实际发到**的张数掷 —— 满仓截断的不掷
			lst.append(roll_for(tid, rng))
		rolls[tid] = lst
		data["ticket_rolls"] = rolls
	return got


## 队首的掷值(下一张会用到的那张)。没有 = 0.0。
static func peek_roll(data: Dictionary, tid: String) -> float:
	var lst: Array = data.get("ticket_rolls", {}).get(tid, [])
	return float(lst[0]) if not lst.is_empty() else 0.0


## 弹出队首掷值(与 `consume_from` 配对调用, 维持「长度 == 张数」)。
static func pop_roll(data: Dictionary, tid: String) -> float:
	var rolls: Dictionary = data.get("ticket_rolls", {})
	var lst: Array = rolls.get(tid, [])
	if lst.is_empty():
		return 0.0
	var v := float(lst.pop_front())
	if lst.is_empty():
		rolls.erase(tid)               # 同 consume_from:不留空列表, 统计才数得对
	else:
		rolls[tid] = lst
	data["ticket_rolls"] = rolls
	return v


## ---- 每日发放 · 2026-08-17 ----
##
## ⚑ **每天第一次打开就发一张**, 不用广告也不用领取按钮 —— 广告位是**加发**的出口,
## 不该是**唯一**的出口。理由:券是「今天多一点选择」, 不是「看广告才能玩得好」。
##
## ⚠ **发哪一张是掷点的, 而这不违反「随机不许决定有没有玩点」** ——
## 那条讲的是**局内**的随机(它决定你这一把有没有解), 而券是**局外的纯加分**:
## 关卡按「没有券」设计, 抽到什么都只是今天顺不顺(用户 2026-08-16 亲自澄清过这一点)。
##
## ⚠ 掷点用**传进来的 rng**, 不自己 `randomize()` —— 同 `core/` 其余部分:
## 自己去摇会让这段逻辑测不了, 而「今天发了什么」是要能重放的。


## 今天该发的券。已发过(`grant_day` == today)就返回空串。
## ⚠ 返回空串 = 今天已领, **不是出错** —— 调用方别把它当异常。
static func daily_pick(data: Dictionary, today: int, rng: RandomNumberGenerator) -> String:
	if int(data.get("grant_day", -1)) == today:
		return ""
	var pool := ids()
	if pool.is_empty():
		return ""
	return String(pool[rng.randi_range(0, pool.size() - 1)])


## 结算今日发放:掷一张、记账、盖上「今天发过了」。返回发到的券 id(空串 = 今天已领)。
## ⚑ 与 `reset_if_new_day` 分开两个键(`tickets_day` / `grant_day`)是有意的:
## **清零和发放是两件事** —— 将来若加「跨天保留未用券」, 只需拆掉前者, 后者不受影响。
static func settle_daily_grant(data: Dictionary, today: int, rng: RandomNumberGenerator) -> String:
	var pick := daily_pick(data, today, rng)
	if pick == "":
		return ""
	var got := grant_with_roll(data, pick, 1, rng)    # 发放一律走这一个入口(掷值不变量)
	data["grant_day"] = today          # ⚠ 满仓也要记账, 否则同一天会反复掷点
	return pick if got > 0 else ""
