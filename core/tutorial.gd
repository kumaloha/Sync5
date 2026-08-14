class_name Tutorial
extends RefCounted

## 教学关的脚本 —— **纯逻辑,引擎无关、不含时钟、不 import view**(CLAUDE.md 架构铁律)。
## 内容全在 `data/tutorial.json`,这里只回答「第 N 拍该多长、该亮什么、该说什么」。
## 规格 = `design/difficulty.md` §4。
##
## ⚑ **教学单开一关**(用户 2026-08-07 拍板:「教学总要时间, 但教学只要一次,
## 不影响整体节奏」)—— 所以它**不受一局 4.9 分钟约束、不判生死、不进 curve.gd**。
## 形状 = 起承転結 的「起」:安全的地方、无惩罚地理解机制。
##
## ⚑ **诊断:新手的敌人不是「不知道按钮在哪」, 是「8 秒内来不及想」。**
## 真人熟练玩家每拍最后一个动作中位已经 5.7s / 8s(12 局 168 拍实测), 新手只会更慢。
## ⇒ **主手段是给时间**, 拍长从 12s 收到 8s;部件按「第一次真正有用」出现只是次手段。
##
## ⚠ 12 秒**没有新手数据支撑** —— 现有合格 Tape 全是熟练玩家(用户本人)。
## 它是待测的假设, 不是标定过的数。


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
	return {"command": String(s[step].get("command", "")),
		"signal": String(s[step].get("signal", ""))}


## 全部合法部件 id —— `data/tutorial.json` 的 `components`,`core/db.gd` 拿它当白名单。
static func components() -> Array:
	var out: Array = []
	for c in DB.tutorial().get("components", []):
		out.append(String(c))
	return out


static func _steps() -> Array:
	return DB.tutorial().get("steps", [])
