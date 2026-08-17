extends SceneTree

## Screenshot probe for the home screen (docs/mockups/home.html). Run NON-headless:
##   godot --path . --script res://tools/home_sheet.gd
## Captures _shot_home.png (小盲) and _shot_home_wall.png (BOSS 墙 card).

var _scene: Node
var _frames := 0

func _initialize() -> void:
	_scene = Shot.stage(self)

func _process(_delta: float) -> bool:
	_frames += 1
	# ⚠ 全部截图挤在启动后 1 秒内:离屏窗口约 1 秒后被 macOS 节流,
	# 之后的 Shot.save 抓到的是**陈旧后备缓冲**(2026-08-12 实测:第 60 与
	# 第 120 帧存出来字节级相同,连均衡器波形都没动)。
	if _frames == 30:
		Shot.save(self, "home")
		_scene._home.section_idx = 2      # 换一档看档位色(现在四段全是墙)
	elif _frames == 56:
		Shot.save(self, "home_wall")
		quit(0)
	return false
