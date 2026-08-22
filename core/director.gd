class_name Director
extends RefCounted

## B 轴 · 跨局序列 —— **纯逻辑,引擎无关、不含时钟、不 import view**(CLAUDE.md 架构铁律)。
## 内容全在 `data/director.json`,这里只回答三件事:
## **第 r 局走哪个状态 · 脸该怎么挑 · 货架该怎么偏**。规格 = `docs/design/difficulty.md` §3。
##
## ⚠⚠ **「不读 context」的拍板已被推翻**(2026-08-14:「不用读 context」→
## 2026-08-19 用户新需求:「基于 context 生成关卡」的能力)。现在有**两个**输入:
## `run_index` + 可选的 `ctx`(玩家状态向量 m 的切片, generating.md §3 层 2)。
## 推翻不等于放开:**`ctx` 是显式入参、缺省空 = 逐字节退回旧掷法**(min_run 同一条先例,
## 探针零影响);它能拧的两个旋钮各有一道数据开关(data/director.json 的 `context` 节):
## · `novelty`(缺省开)—— 同一档内偏向**见得最少**的脸。这是 N 轴(新鲜感)的实现,
##   generating.md §1 判它是「求解器天然感受不到、必须外部编码」的唯一分量, 不是 DDA;
## · `streak_shift`(**开**, 2026-08-19 晚用户拍板:「开, 就是要千人千面, 但不要被察觉」)
##   —— 连败降档 / 连胜升档(改排布不改数值, L4D 认可的形状)。
##   「不被察觉」的保障就是上一行:它只换**哪张脸上场**, 目标分/规则/数值/UI 全不动。
##
## ⚑ **铁律:Director 不许调目标分。** 它能调的只有 `face_bias` 与 `shelf` 两样。
## 依据是外部调研(`docs/design/research_pacing_retention.md` §1):**约束的本体是「可不可见」**——
## DDA 被察觉就失效,橡皮筋是反面教材。可执行版本 = **同一个玩家在同一个位置永远拿到同一个数**,
## 而「只按 `run_index` 索引一张写死的表」正是这句话的实现。
## ⚠ 目标分/价格/「必定出某张牌」/读 context 四类键由 `core/db.gd::validate_director`
## **显式**挡住 —— 白名单已经够了,那张表是为了让越界的人**知道自己越了哪条界**。
##
## ## ⚠ 这里**没有**脸的难度排序,也不该有
##
## 「温和 / 中位 / 最狠」需要一个「(脸, 轮) → 难度」的排序,而那个数是 `tools/price.gd`
## 的**仪器读数**,不是设计常量:抄进 `data/` 就会过期,而这个项目最贵的一类错正是
## 「同一个口径抄了第二份」。所以排序是**调用方传进来的参数**,不是这里的数据。
## **没有排序时 `roll_run` 逐字节退回 `SectionMod.roll_run`** —— 接不接得上 Director
## 不改变现有掷法,也不改变 RNG 消耗(测试里锁着)。


## 合法的脸的排布倾向。⚠ 与 `core/db.gd::_DIRECTOR_BIASES` 是同一张表的两处读法 ——
## 这里给消费者,那边给校验;两处都不带数值,所以不构成「抄第二份」。
const BIASES := ["mild", "median", "harsh"]


static func _cfg() -> Dictionary:
	return DB.director()


## 序列本体:`sequence[i]` = 第 (i+1) 局的状态名。
static func sequence() -> Array:
	var out: Array = []
	for s in _cfg().get("sequence", []):
		out.append(String(s))
	return out


static func states() -> Dictionary:
	return _cfg().get("states", {})


## 走完序列后从哪一项开始循环(0 起下标)。
static func loop_from() -> int:
	return int(_cfg().get("loop_from", 0))


## 「温和 / 中位 / 最狠」各取池子的多大一段。
static func band_fraction() -> float:
	return float(_cfg().get("band_fraction", 1.0))


## 第 `run_index` 局落在 `sequence` 的哪个下标。−1 = 序列是空的(校验会拦下)。
##
## ⚠ **越界钳到第 1 局,不返回空** —— 用空状态表达「没有这一局」会让调用方
## **静默失去 Director**,和 `Tutorial.seconds` 越界返回 0 会让时钟停摆同一个形状。
static func index_for(run_index: int) -> int:
	var n := sequence().size()
	if n <= 0:
		return -1
	var i := maxi(1, run_index) - 1
	if i < n:
		return i
	var lf := clampi(loop_from(), 0, n - 1)
	var span := n - lf
	return lf + (i - lf) % span


static func state_for(run_index: int) -> String:
	var i := index_for(run_index)
	if i < 0:
		return ""
	return String(sequence()[i])


static func entry_for(run_index: int) -> Dictionary:
	return states().get(state_for(run_index), {})


## 这一局脸该往哪边挑。缺省 "median"(中性)—— 校验要求必填,所以只有在
## 数据坏掉时才走得到这条,而中性是唯一一个「什么都不主张」的答案。
static func face_bias(run_index: int) -> String:
	return String(entry_for(run_index).get("face_bias", "median"))


static func shelf(run_index: int) -> Dictionary:
	return entry_for(run_index).get("shelf", {})


## ---- context(2026-08-19, 玩家状态 m 的消费端)----

static func ctx_cfg() -> Dictionary:
	return _cfg().get("context", {})


static func novelty_on() -> bool:
	return bool(ctx_cfg().get("novelty", false))


static func streak_shift_on() -> bool:
	return bool(ctx_cfg().get("streak_shift", false))


## 回归局(context.md §2):隔了很久回来的第一局 = 温和档 + 熟脸(重建手感, 不给新东西)。
static func returning_on() -> bool:
	return bool(ctx_cfg().get("returning", false))


## 探索型货架(context.md §3 岔 #1 批「探索型 ≤1.5×」):没玩过的 Target 权重上浮。
## 消费端在 view/shop.gd —— Director 只当开关的家, 让四个 context 旋钮住同一个屋檐。
static func explore_on() -> bool:
	return bool(ctx_cfg().get("explore_shelf", false))


## context 的阈值(data/director.json `context_tuning`;缺省 = 08-19 的设计值)。
static func tuning() -> Dictionary:
	return _cfg().get("context_tuning", {})


static func explore_mult() -> float:
	return float(tuning().get("explore_mult", 1.5))


static func return_gap_s() -> int:
	return int(tuning().get("return_gap_days", 3)) * 86400


## 探索型货架的 boost 字典:候选里「没用过」的 Target → explore_mult。
## ⚑ **纯函数**:`used` 由编排器从存档读了传进来(探针 / 零历史 ⇒ 空 ⇒ 返回空 = 掷法逐字节不变),
## shop 自己不碰存档(2026-08-21 评审:此前 shop 直接读 SaveState, 破了它自己的注入制)。
static func explore_boost(candidates: Array, used: Dictionary) -> Dictionary:
	var boost := {}
	if used.is_empty() or not explore_on():
		return boost
	for j in candidates:
		if j.kind == "target" and not used.has(String(j.id)):
			boost[String(j.id)] = explore_mult()
	return boost


## 连败降一档 / 连胜升一档 —— **纯函数**(不读 DB), 开关由 `bias_with_ctx` 把门。
## 阈值不对称是有意的:连败 2 局就该松手(挫败流失快), 连胜要 3 局才收紧
## (研究篇:紧的代价大于松的代价, 玩家对「变难」远比「变简单」敏感)。
static func shift_bias(bias: String, streak: int, lose := 2, win := 3) -> String:
	var i := BIASES.find(bias)
	if i < 0:
		return bias
	if streak <= -lose:
		i = maxi(0, i - 1)
	elif streak >= win:
		i = mini(BIASES.size() - 1, i + 1)
	return BIASES[i]


static func bias_with_ctx(bias: String, ctx: Dictionary) -> String:
	if ctx.is_empty() or not streak_shift_on():
		return bias
	var tn := tuning()
	return shift_bias(bias, int(ctx.get("streak", 0)),
		int(tn.get("lose_streak", 2)), int(tn.get("win_streak", 3)))


## 这一局的稀有度权重**乘数**,按 `data/economy.json` 的稀有度补齐(缺省 1.0)。
static func shelf_rarity_mult(run_index: int) -> Dictionary:
	var m: Dictionary = shelf(run_index).get("rarity_weight_mult", {})
	var out := {}
	for k in _base_weights():
		out[String(k)] = float(m.get(k, 1.0))
	return out


## 直接可用的货架权重 = 基础权重 × 本局乘数。
## **不写 `shelf` 时逐字节等于基础权重** —— 「接上 Director 不改变现状」的机器可读版。
static func shelf_weights(run_index: int) -> Dictionary:
	var base := _base_weights()
	var mult := shelf_rarity_mult(run_index)
	var out := {}
	for k in base:
		out[String(k)] = float(base[k]) * float(mult[String(k)])
	return out


static func _base_weights() -> Dictionary:
	return DB.economy().get("draft_rarity_weights", {})


## 一档有几张。向上取整并至少 1 张 —— 空档会让 `pick_face` 无解,
## 而「这一轮池子小」不该表达成「这一局没有脸」。
static func band_size(n: int) -> int:
	if n <= 0:
		return 0
	return clampi(int(ceil(float(n) * band_fraction())), 1, n)


## 从**由易到难**排好的池子里切出一档。
## ⚠ 排序方向是契约的一半:`ranked[0]` 必须是最温和的那张。传反了不会报错,
## 只会让「温和」这一档变成最狠的一档 —— 调用方(`tools/price.gd` 的消费者)负责这个方向。
## 不认识的倾向退回中位(中性),不是空档:同上一条,空档是个静默死锁。
static func band(ranked: Array, bias: String) -> Array:
	var n := ranked.size()
	if n == 0:
		return []
	var k := band_size(n)
	if bias == "mild":
		return ranked.slice(0, k)
	if bias == "harsh":
		return ranked.slice(n - k, n)
	var start := int(floor(float(n - k) / 2.0))
	return ranked.slice(start, start + k)


## 在一档里均匀掷一张。**恰好消耗一次 `randi_range`** —— 与 `SectionMod.roll` 一致,
## 所以接上 Director 不会让任何探针的复现性漂(测试里锁着)。
##
## ⚑ `exclude` 与 `SectionMod.roll` 同一条守卫:**重复必须是有意的,不能是偶然的**。
## ⚠ 一档被 `exclude` 排空时**退回整档**而不是返回 ""(同 `SectionMod.roll` 排空退回全池):
## 「排布挤不下了」用「漏一堵墙」来表达会静默改变游戏,宁可重复。
## `seen` = {face_id: 见过几次}(玩家状态 m 的新鲜感切片)。非空且 novelty 开着时,
## 候选收缩到**见得最少**的那批 —— N 轴的实现:没见过的脸优先登场。
## `familiar = true`(回归局)时**反向**:收缩到见得**最多**的那批 —— 重建手感用熟脸。
## ⚠ 无论收不收缩, **恰好消耗一次 `randi_range`** 的不变量不动(探针复现性靠它)。
static func pick_face(ranked: Array, bias: String, rng: RandomNumberGenerator,
		exclude: Array = [], seen: Dictionary = {}, familiar: bool = false) -> String:
	var b := band(ranked, bias)
	if b.is_empty():
		return ""
	var fresh: Array = []
	for id in b:
		if not exclude.has(id):
			fresh.append(id)
	if fresh.is_empty():
		fresh = b
	# familiar(回归局)不受 novelty 开关管 —— 它是 returning 开关的事(评审:关 novelty 会吞掉熟脸)
	if not seen.is_empty() and (novelty_on() or familiar):
		var kept: Array = []
		var best := -1
		for id in fresh:
			var c := int(seen.get(String(id), 0))
			var wins: bool = (c > best) if familiar else (best < 0 or c < best)
			if wins:
				best = c
				kept = [id]
			elif c == best:
				kept.append(id)
		fresh = kept
	return String(fresh[rng.randi_range(0, fresh.size() - 1)])


## 这一局四张脸 —— `SectionMod.roll_run` 的 Director 版。
##
## `ranking` = `{section_idx(0 起): [face_id, ...(由易到难)]}`,来源是 `tools/price.gd`
## 的「(脸, 轮)」定价。**给不出排序的段逐字节退回 `SectionMod.roll`**,所以
## `ranking = {}` 时整个函数与现有掷法完全等价(输出与 RNG 消耗都一样)。
##
## ⚠ 排序表必须与池子取交:它是仪器输出,可能带着一张这一轮不出现的脸
## (同一张脸在别的轮里也排过价)。不取交就会掷出一张不属于这一段的脸,而且不报错。
## `ctx` = 玩家状态 m 的切片:{"streak": int(连胜正/连败负), "seen": {face: 次数}}。
## **缺省 {} 时与旧签名逐字节等价**(输出与 RNG 消耗都一样)—— 探针/hundred 验证不漂。
static func roll_run(run_index: int, rng: RandomNumberGenerator,
		ranking: Dictionary = {}, ctx: Dictionary = {}) -> Dictionary:
	# 回归局压过 streak:隔了很久回来, 上次的连败/连胜早不是这次的状态了
	var returning := returning_on() and bool(ctx.get("returning", false))
	var bias := "mild" if returning else bias_with_ctx(face_bias(run_index), ctx)
	var seen: Dictionary = ctx.get("seen", {})
	var out := {}
	var drawn: Array = []
	for w in GameConfig.WALL_SECTIONS:
		var idx := int(w)
		var ranked := ranked_pool(idx, ranking, run_index)
		var f := ""
		if ranked.is_empty():
			# ⚠⚠ **必须把 `run_index` 传下去** —— 不传就绕过 `min_run` 的按局数解锁门
			# (禁回会在第 1 局重新冒出来, 而且不报错)。2026-08-16 接线时当场抓到。
			f = SectionMod.roll(idx, rng, drawn, run_index)
		else:
			f = pick_face(ranked, bias, rng, drawn, seen, returning)
		out[idx] = f
		if f != "":
			drawn.append(f)
	return out


## 排序表里属于这一段池子的部分,保持排序表给的先后。
## ⚠ `run_index` 用于 `min_run` 解锁过滤 —— 排序表是仪器输出, 它不知道谁解锁了。
static func ranked_pool(section_idx: int, ranking: Dictionary, run_index: int = -1) -> Array:
	if not ranking.has(section_idx):
		return []
	var pool := SectionMod.pool_for(section_idx)
	var out: Array = []
	for id in ranking[section_idx]:
		var s := String(id)
		if pool.has(s) and not out.has(s) and SectionMod.unlocked_at(s, run_index):
			out.append(s)
	return out
