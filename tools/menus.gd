extends SceneTree

## 图鉴页截图(2026-08-11 实装验收;2026-08-24 局外删除后只剩小丑牌一页):
##   _shot_album / _shot_albumend(滚到底看未实装卡)
##   godot --path . --script res://tools/menus.gd

var _n := 0
var _cur: Control = null


func _initialize() -> void:
	Shot.canvas(self, 720, 1280, Color(0, 0, 0))
	_show(AlbumScreen.new())


func _show(c: Control) -> void:
	if _cur != null:
		_cur.queue_free()
	_cur = c
	get_root().add_child(c)


func _process(_d: float) -> bool:
	_n += 1
	if _n == 10:
		Shot.save(self, "album")
		_cur._scroll = _cur._max_scroll()
	elif _n >= 16:
		Shot.save(self, "albumend")
		quit(0)
		return true
	return false
