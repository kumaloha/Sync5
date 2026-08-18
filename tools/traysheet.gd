extends SceneTree

## 券托盘 + 商店点唱券的目视对账探针(2026-08-17 券使用入口)。NON-headless 跑:
##   godot --path . --script res://tools/traysheet.gd
## 产物:`_shot_tray.png`(三 chip)· `_shot_tray_armed.png`(boost 已上标牌)·
##       `_shot_tray_shop.png`(刷新按钮念点唱券)。
##
## ⚑ 托盘数据是**注入**的(`show_tickets`)—— 探针拿不到真券(`_is_probe` 闸),
## 这正是当初把组件做成注入制的理由:闸挡的是存档, 挡不了目视。
## ⚠ 商店那张要**先 `_open_draft()` 再 `set_free_rerolls`** —— 编排器开店时会按
## SaveState(探针里恒 0)重新注入, 顺序反了免费态会被盖掉。

var _frames := 0
var _scene: Node


func _initialize() -> void:
	_scene = Shot.stage(self)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 4:
		_scene.choose_character(1)
		return false
	if _frames < 120:
		return false
	match _frames:
		120:
			_scene.tray.show_tickets({"overtime": 1, "redeal": 2, "boost": 1}, 1.7)
		124:
			Shot.save(self, "tray")
			print("tray: 3 chips (overtime / redeal x2 / boost x1.7)")
		128:
			_scene.tray.show_tickets({"overtime": 1}, 0.0,
				String(DB.ui()["tickets"]["armed_text"]) % 2.0)
		132:
			Shot.save(self, "tray_armed")
			print("tray_armed: overtime chip + armed badge")
		136:
			_scene._open_draft()
			_scene.shop.set_free_rerolls(2)
		148:
			Shot.save(self, "tray_shop")
			print("tray_shop: reroll button reads the juke ticket")
		152:
			# 替换态 + 放弃按钮(2026-08-18 用户:「第五张想弃掉, 好像没有操作办法」)
			_scene.replace.enter(Joker.pool()[10], 6)
		164:
			Shot.save(self, "replace_cancel")
			print("replace_cancel: 预览卡 + 提示行 + ✕ 不换了按钮")
			return true
	return false
