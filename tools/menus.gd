extends SceneTree

## 三个图鉴页截图(2026-08-11 实装验收):
##   _shot_heroes / _shot_album / _shot_albumend(滚到底看未实装卡)
##   / _shot_honors(成就) / _shot_ranks(排行)
##   godot --path . --script res://tools/menus.gd

var _n := 0
var _cur: Control = null


func _initialize() -> void:
	Shot.canvas(self, 720, 1280, Color(0, 0, 0))
	_show(HeroesScreen.new())


func _show(c: Control) -> void:
	if _cur != null:
		_cur.queue_free()
	_cur = c
	get_root().add_child(c)


func _process(_d: float) -> bool:
	_n += 1
	if _n == 10:
		Shot.save(self, "heroes")
		_show(AlbumScreen.new())
	elif _n == 20:
		Shot.save(self, "album")
		_cur._scroll = _cur._max_scroll()
	elif _n == 26:
		Shot.save(self, "albumend")
		_show(HonorsScreen.new())
	elif _n == 36:
		Shot.save(self, "honors")
		_cur.sub = 1
	elif _n >= 44:
		Shot.save(self, "ranks")
		quit(0)
		return true
	return false
