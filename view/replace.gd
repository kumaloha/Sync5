class_name ReplaceFlow
extends RefCounted

## 满槽「买新替旧」的**替换态** —— 2026-08-09 从 `view/phrase.gd` 搬出来。
##
## 它原本是 **4 个散落的成员变量**(待装入的卡 / 提示条 / 预览卡 + 三个槽位标志位)
## 由 **3 个函数**分头维护(进入 / 取消 / 成交), 没有一个人对「现在到底是不是
## 替换态」负责 —— 而 4 个槽在前 4 次商店就填满, **后 3 次商店 100% 走这条路**,
## 它是主线交互不是边角(design/levels.md)。现在编排器只说 enter() / exit()。
##
## ⚠ 边界:这里只管 **UI 摆放与状态复位**。钱(`phrase.coins`)与 `Tape.on()`
## 一律留在编排器 —— CLAUDE.md 的两条铁律:「打点只在编排器打」、
## 「金币/装槽等经济动作只发生在编排器」。

## Joker awaiting a slot choice; null = 不在替换态(编排器就是靠它判的)
var pick = null

var _views: Array               # 四个槽的视图, 0 号是 Target 槽 = 取消位
var _cfg: Dictionary
var _prompt: Label
var _preview: JokerSlotView     # the incoming card, pinned + draggable


func _init(host: Control = null, views: Array = []) -> void:
	_views = views
	_cfg = DB.ui()["shop"]

	# full-slot replace prompt lives OUTSIDE the shop layer: the joker row
	# must stay visible while a slot is being chosen
	_prompt = StageTheme.label("",
		StageTheme.zh(), 18, StageTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt.position = _v2(_cfg["replace_prompt_pos"])
	# not full-width: the blind card sits at the left of the wave layer and the
	# record at the right — a 720-wide centred line runs straight through both
	_prompt.size = Vector2(float(_cfg["replace_prompt_w"]), 30)
	_prompt.visible = false
	host.add_child(_prompt)

	# 待装入的新卡(2026-08-06): 选槽时商店被关掉, 玩家原本**看不到自己要买的那张**
	# —— 而替换决策的本质就是新旧对比, 只能靠记忆选是错的。这里把它钉成
	# 「第 5 个槽位」摆在小丑牌行正下方, 上下对照, 视线不用跳; 它同时是拖拽源。
	_preview = JokerSlotView.new()
	_preview.slot_kind = "support"
	_preview.size = _v2(_cfg["replace_preview_size"])
	_preview.position = _v2(_cfg["replace_preview_pos"])
	_preview.visible = false
	host.add_child(_preview)


## 进入替换态:提示条带上买入价(商店一关, 玩家就看不到价了), 新卡钉出来,
## 四个槽开始接点击/拖放。
func enter(j) -> void:
	pick = j
	_prompt.text = String(_cfg["replace_prompt"]) % Economy.joker_price(j)
	_prompt.visible = true
	_preview.set_joker(j)
	_preview.drag_joker = j
	_preview.visible = true
	for k in range(_views.size()):
		_views[k].tappable = true
		# 0 号是 Target 槽 = 取消; 1..3 是可替换的 Support
		_views[k].pick_mode = "cancel" if k == 0 else "replace"
		# 只有 Support 槽接拖放 —— 拖到 Target 槽应该被拒绝, 而不是悄悄取消
		_views[k].accept_joker_drop = k != 0


## 退出替换态(取消与成交共用):**所有**痕迹一次复位, 没有第二个出口。
func exit() -> void:
	pick = null
	_prompt.visible = false
	_preview.visible = false
	_preview.drag_joker = null
	_preview.set_joker(null)
	for v in _views:
		v.tappable = false
		v.pick_mode = ""
		v.accept_joker_drop = false


## data/ui.json stores positions as [x, y] pairs (design/tech.md)
func _v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))
