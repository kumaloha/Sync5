class_name Director
extends RefCounted

## B 轴 · 跨局序列 —— **纯逻辑,引擎无关、不含时钟、不 import view**(CLAUDE.md 架构铁律)。
## 内容全在 `data/director.json`,这里只回答三件事:
## **第 r 局走哪个状态 · 脸该怎么挑 · 货架该怎么偏**。规格 = `docs/design/difficulty.md` §3。
##
## ⚑⚑ **它不读任何玩家行为**(2026-08-14 用户拍板:「这里不是千人千面的不用读 context。
## 真正千人千面的只有随机出来的小丑牌(控制难度的)」)。所以这个文件里**只有一个输入**:
## `run_index`(第几局,1 起)。多一个参数就是多一条 DDA 的口子。
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
static func pick_face(ranked: Array, bias: String, rng: RandomNumberGenerator,
		exclude: Array = []) -> String:
	var b := band(ranked, bias)
	if b.is_empty():
		return ""
	var fresh: Array = []
	for id in b:
		if not exclude.has(id):
			fresh.append(id)
	if fresh.is_empty():
		fresh = b
	return String(fresh[rng.randi_range(0, fresh.size() - 1)])


## 这一局四张脸 —— `SectionMod.roll_run` 的 Director 版。
##
## `ranking` = `{section_idx(0 起): [face_id, ...(由易到难)]}`,来源是 `tools/price.gd`
## 的「(脸, 轮)」定价。**给不出排序的段逐字节退回 `SectionMod.roll`**,所以
## `ranking = {}` 时整个函数与现有掷法完全等价(输出与 RNG 消耗都一样)。
##
## ⚠ 排序表必须与池子取交:它是仪器输出,可能带着一张这一轮不出现的脸
## (同一张脸在别的轮里也排过价)。不取交就会掷出一张不属于这一段的脸,而且不报错。
static func roll_run(run_index: int, rng: RandomNumberGenerator,
		ranking: Dictionary = {}) -> Dictionary:
	var bias := face_bias(run_index)
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
			f = pick_face(ranked, bias, rng, drawn)
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
