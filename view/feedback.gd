class_name StageFeedback
extends Node

## 对局界面的**视觉反馈** —— 2026-08-09 从 `view/phrase.gd` 搬出来。
## 屏震 / 弹一下 / 飘字, 三样都是纯表现:**不读也不写任何游戏状态**,
## 所以它不认识 run / phrase / joker, 只认识「往哪个节点上画」。
##
## 它是 Node 而不是 RefCounted, 因为屏震要逐帧积分;宿主的 position 由它写。

const SHAKE_TIME := 0.65

var _host: Control
var _shake_t := 0.0
var _shake_amp := 0.0


func _init(host: Control = null) -> void:
	_host = host


func _process(delta: float) -> void:
	if _shake_t <= 0.0:
		return
	_shake_t = maxf(0.0, _shake_t - delta)
	var k: float = _shake_t / SHAKE_TIME
	var a: float = _shake_amp * k * k
	_host.position = Vector2(sin(_shake_t * 58.0) * a, cos(_shake_t * 71.0) * a * 0.7)
	if _shake_t <= 0.0:
		_host.position = Vector2.ZERO


## Screen shake — the dcimpact keyframe in the spec.
func shake(amp: float) -> void:
	_shake_amp = amp
	_shake_t = SHAKE_TIME


func pop(node: Control) -> void:
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2(1.3, 1.3)
	var tw := _host.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector2.ONE, 0.35)


## `at` 是**全局**坐标(调用方都是从 get_global_position() 算出来的), 所以字
## 必须挂在宿主上 —— 挂到本节点(Node 没有坐标)会丢掉参照系。
## `z` 缺省 60 = 局内层序(组件用到 z 20 一带);要盖在首页(HomeScreen z=80)上的
## 浮字传高值(体力闸的回绝浮字 = 90, 截图对账抓过一次「字画在首页底下」)。
func float_text(text: String, at: Vector2, color: Color, z: int = 60) -> void:
	var l := StageTheme.label(text, StageTheme.num("Bold"), 26, color)
	l.position = at
	l.z_index = z
	_host.add_child(l)
	var tw := _host.create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", at.y - 46.0, 0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.chain().tween_callback(l.queue_free)
