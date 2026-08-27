class_name Tutorial
extends RefCounted

## 教学关的脚本 —— **纯逻辑,引擎无关、不含时钟、不 import view**(CLAUDE.md 架构铁律)。
## 内容全在 `data/tutorial.json`,这里只回答「第 N 拍该多长、该亮什么、该说什么」。
## 规格 = `docs/design/difficulty.md` §4。
##
## ⚑ **教学单开一关**(用户 2026-08-07 拍板:「教学总要时间, 但教学只要一次,
## 不影响整体节奏」)—— 所以它**不受一局 4.9 分钟约束、不判生死、不进 curve.gd**。
## 形状 = 起承転結 的「起」:安全的地方、无惩罚地理解机制。
##
## ⚑⚑ **诊断(2026-08-16 第三版, 前两版都押错了主手段)**:
##   · v1「主手段是给时间」(拍长 12→8)—— **错**。时间只解决「来不及」, 解决不了「不知道这是什么」;
##   · v2「主手段是指出区域」(focus 描边)—— **不够**。它解决「这是什么」, 解决不了「我学会了没有」;
##   · **v3 = 做中学 + 动作门**。玩家**把这个动作做出来**才推进, 没做就停在这一步。
##
## 依据是外部调研的三条共识(2026-08-16, 见 docs/design/difficulty.md §4):
##   ① 玩家学会靠**做**不靠读 —— 纯文字步骤会被直接跳过;
##   ② 步进该由**动作**驱动, 不该由时间驱动("teach one idea, ask for one action, deliver one response");
##   ③ 每个机制要有**练习位** —— 讲下一个之前先让他把这个做一遍。
##
## ⚑ **而本作最大的资产是「玩家已经会扑克」**(Balatro 的 Shared Mental Model):
## **扑克不用教**, 教学关只教本作特有的三件 —— **8 秒 · 缓存区 · 弃牌免费且立刻补**。
##
## ⚠ 拍长放宽(12s)**保留但降级成副手段**。它**没有新手数据支撑** ——
## 现有合格 Tape 全是熟练玩家(用户本人), 所以它是待测假设, 不是标定过的数。


## 这一步要求玩家做出的动作 —— 做到了才推进(`Run.tutorial_try_advance`)。
## 空串 = 不设门, 这一拍过完就走。
##
## ⚑ **软门, 不是硬门**:门只挡**推进**, 不挡玩。玩家照样能出牌、这一拍照常结算,
## 只是提示留在原地再说一次。硬门(不做就不许出牌)会与「8 秒是唯一闸门」正面冲突,
## 而且 docs/design/difficulty.md §4 已把「强制引导」列进明确不做。
static func require(step: int) -> String:
	var s := _steps()
	if step < 0 or step >= s.size():
		return ""
	return String(s[step].get("require", ""))


## 全部合法的动作 id。⚠ `core/db.gd` 拿它当白名单 —— 写错一个动作名,
## 那一步就**永远推进不了**, 而且不报错(玩家会卡死在教学关里)。
const ACTIONS := ["play", "discard", "swap", "multiselect", "buy"]


## 价签活取键的白名单(v6, 经济 v2)。`command` 里的 %d 由这里的现值填 ——
## **数字不再抄进文案**:经济一调价, 教学价签自动跟, t_tutorial 的同步锁
## 从「抄对了没」升级成「根本不抄」。`core/db.gd` 校验 args ⊆ 这张表且
## 个数与 %d 一致(不一致 = 运行时格式化炸, 必须测试期就红)。
const ARG_KEYS := ["discard_cost", "joker_price"]


static func _arg_value(name: String) -> int:
	match name:
		"discard_cost":
			return GameConfig.DISCARD_COST
		"joker_price":
			return int(GameConfig.JOKER_PRICES.get("common", 0))
	return 0


## %d 价签代入。args 空 = 原样返回(绝大多数句子没有价签)。
static func _fmt(text: String, args: Array) -> String:
	if args.is_empty():
		return text
	var vals: Array = []
	for a in args:
		vals.append(_arg_value(String(a)))
	return text % vals


## 一共几拍。
static func steps() -> int:
	return _steps().size()


## 这一拍多长(秒)。⚠ 越界返回正式局的拍长 —— 教学关走完就该回到正常节奏,
## 用 0 或负数表达「没有这一拍」会让调用方的时钟静默停摆。
static func seconds(step: int) -> float:
	var s := _steps()
	if step < 0 or step >= s.size():
		return GameConfig.phrase_duration(0)
	return float(s[step].get("seconds", GameConfig.phrase_duration(0)))


## 走到第 `step` 拍(含)时,已经亮出来的全部部件。
## ⚠ **累积**:`unlock` 只写「这一拍**首次**出现的」,亮过就一直亮 ——
## 让脚本作者不必在后面每一步重抄一遍清单(抄了就会漏)。
static func unlocked(step: int) -> Array:
	var out: Array = []
	var s := _steps()
	for i in range(mini(step + 1, s.size())):
		for c in s[i].get("unlock", []):
			var id := String(c)
			if not out.has(id):
				out.append(id)
	# 走完教学关 = 全部解锁, 否则「教学关之后某个部件还是灰的」会是一个静默的死锁。
	if step >= s.size():
		return components()
	return out


## 这个部件在第 `step` 拍是否可用。
static func is_unlocked(component: String, step: int) -> bool:
	return unlocked(step).has(component)


## 这一拍的提示行 —— `{"command": 中文一句, "signal": 英文短标}`。
## 照 `data/ui.json` 的 `blindcard` 口径,越界返回空串而不是 null(调用方直接贴)。
static func hint(step: int) -> Dictionary:
	var s := _steps()
	if step < 0 or step >= s.size():
		return {"command": "", "signal": ""}
	return {"command": _fmt(String(s[step].get("command", "")), s[step].get("args", [])),
		"signal": String(s[step].get("signal", ""))}


## 这一步属于哪个分镜(v6)。分镜 = 高光构图 + 文字条锚位:同 shot 的步共用 focus
## (db 校验锁), 条锚由**编排器**按 shot 翻译成 y —— core 不认识像素(坐标归 view)。
static func shot(step: int) -> String:
	var s := _steps()
	if step < 0 or step >= s.size():
		return ""
	return String(s[step].get("shot", ""))


## 这一步的次级强调(光斑)指向的区域名, "" = 无。位置随步切换, 不动条与 focus。
static func spot(step: int) -> String:
	var s := _steps()
	if step < 0 or step >= s.size():
		return ""
	return String(s[step].get("spot", ""))


## 商店分镜(shot D)= **最后一步**:它的展示面是商店层, 编排器推进到这一步时
## 弹真商店、关店即消费(`Run.tutorial_shop_seen`)。「最后一步 = 商店」是 v6 的
## 结构约定 —— 商店是教学主线的收尾, 后面只剩无提示自由拍。
static func shop_step() -> int:
	return _steps().size() - 1


## 特写(插播)脚本, key ∈ alpha/beta/gamma。α/β = RESOLVE 滚分后的冻钟插播,
## γ = 转正式局的开局公示卡(消费面不同, 由编排器分流)。缺失返回 {}(调用方跳过)。
static func cutin(key: String) -> Dictionary:
	var c = DB.tutorial().get("cutins", {}).get(key, {})
	if not (c is Dictionary) or c.is_empty():
		return {}
	var focus: Array = []
	for r in c.get("focus", []):
		focus.append(String(r))
	return {"after_step": int(c.get("after_step", -1)),
		"seconds": float(c.get("seconds", 2.5)),
		"focus": focus,
		"command": _fmt(String(c.get("command", "")), c.get("args", []))}


## 这一步指向哪几块区域 —— 名字取自 `data/ui.json` 的 `tutor_focus`。
##
## ⚑ 用户 2026-08-15:「教学关不在于秒数,在于**页面不同区域干嘛**」——
## 第一版只改了文案, 于是第 6 步写着「顶栏是分数和拍数」而提示条在屏幕中间:**光说不指**。
## ⚠ 返回**区域名**而不是矩形 —— 坐标属于 `ui.json`(改布局 = 改 JSON 那条铁律),
## `core/` 不该认识像素。
static func focus(step: int) -> Array:
	var s := _steps()
	if step < 0 or step >= s.size():
		return []
	var out: Array = []
	for r in s[step].get("focus", []):
		out.append(String(r))
	return out


## 全部合法区域 id —— `data/ui.json` 的 `tutor_focus`(去掉 `_` 注释键)。
## `core/db.gd` 拿它当白名单:指向一块不存在的区域 = 画不出来且不报错。
static func regions() -> Array:
	var out: Array = []
	for k in DB.ui().get("tutor_focus", {}):
		if not String(k).begins_with("_"):
			out.append(String(k))
	return out


## 全部合法部件 id —— `data/tutorial.json` 的 `components`,`core/db.gd` 拿它当白名单。
static func components() -> Array:
	var out: Array = []
	for c in DB.tutorial().get("components", []):
		out.append(String(c))
	return out


static func _steps() -> Array:
	return DB.tutorial().get("steps", [])
