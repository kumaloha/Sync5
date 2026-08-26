class_name AlbumScreen
extends Control

## 小丑牌收藏册,自 docs/mockups/小丑牌.dc.html(该屏权威)。
## 结构:页标题栏 → 稀有度筛选 → 60 张全量收藏网格(滚动)→ 页签轨。
## 设计稿顶部还有一块「出战牌组 LOADOUT(5 槽装备)」—— 游戏里**不存在**
## 局外配牌:小丑牌只在局内商店获得,4 槽,run 结束即散。装一个假装备面板
## 等于凭空宣称一套 meta 机制,按「做少比加戏便宜」砍掉;真要做 meta 构筑
## 是内容拍板,归用户。锁定/NEW 角标同理(没有存档系统)不做,
## 未进池的卡按事实标「未实装」。
## 数据全真:assets/jokers/manifest.json(60 张冻结名单)+ data/jokers.json
## (在池 39 张)+ ui.json jokercard(中文说明)+ economy.json(价格)。

signal menu_pressed(idx: int)

const W := 720.0
const H := 1280.0
const GRID := Rect2(44.0, 168.0, 632.0, 955.0)   # 底沿 1123,页签轨 1143 上留 20
const CELL_H := 222.0
const GAP := 14.0
const ACC := StageTheme.VIOLET      # 页面主色:构筑线一贯用紫(稀有同族)

const RARITY_CN := {"common": "普通", "uncommon": "罕见", "rare": "稀有"}
const RARITY_TINT := {"common": Color("8ea3c8"), "uncommon": Color("5fd8ff"),
	"rare": Color("ffd36e")}
const FILTERS := ["全部", "Target", "普通", "罕见", "稀有"]

var filter := 0

var _t := 0.0
var _key: Dictionary = {}       # 静态层上次重画时的状态键(Chrome.dirty)
var _cards: Array = []          # {id,cn,kind,rarity,trigger,amount,price,pooled}
var _pooled := 0
var _scroll := 0.0
var _drag_y := -1.0             # 触点 y,-1 = 空闲
var _drag_moved := 0.0
var _scroll0 := 0.0
var _art: Dictionary = {}       # id → Texture2D / false
var _chip_rects: Array = []
var _grid: Control = null


class GridLayer:
	extends Control
	var album: AlbumScreen = null
	func _draw() -> void:
		if album != null:
			album.draw_grid(self)


## 雨要压在滚动层上面(设计稿雨在 z9),而子节点画在父 _draw 之后 ——
## 所以雨也得是子节点,加在网格层后面。
class RainLayer:
	extends Control
	var album: AlbumScreen = null
	func _draw() -> void:
		if album != null:
			Chrome.rain(self, album._t)


func _ready() -> void:
	position = Vector2.ZERO
	size = Vector2(W, H)
	z_index = 85
	_load_cards()
	_grid = GridLayer.new()
	_grid.album = self
	_grid.position = GRID.position
	_grid.size = GRID.size
	_grid.clip_contents = true
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_grid)
	var rl := RainLayer.new()
	rl.album = self
	rl.size = Vector2(W, H)
	rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rl)
	set_process(true)


func _load_cards() -> void:
	var pool := {}
	for j in DB.jokers():
		pool[String(j["id"])] = j
	var trig: Dictionary = DB.ui().get("jokercard", {})
	var econ := DB.economy()
	var prices: Dictionary = econ.get("joker_prices", {})
	var overrides: Dictionary = econ.get("joker_price_overrides", {})
	var f := FileAccess.open("res://assets/jokers/manifest.json", FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if not (d is Dictionary):
		return
	for e in d.get("cards", []):
		var id := String(e.get("id", ""))
		var pooled: bool = pool.has(id)
		# 在池的卡以 data/jokers.json 为准(游戏真相),没进池的用美术 manifest
		var rarity := String(pool[id].get("rarity", "common")) if pooled \
			else String(e.get("rarity", "common"))
		var kind := String(pool[id].get("kind", "support")) if pooled \
			else String(e.get("kind", "support"))
		var show := Lingo.pick(e)   # en 挑数据里的 name 字段(1.1 英文化)
		_cards.append({
			"id": id,
			"cn": show if show != "" else id,
			"kind": kind,
			"rarity": rarity,
			"amount": String(e.get("amount", "")),
			"trigger": String(trig.get(id, {}).get("trigger", e.get("trigger_zh", ""))),
			"price": int(overrides.get(id, prices.get(rarity, 4))),
			"pooled": pooled,
		})
		if pooled:
			_pooled += 1


func _process(delta: float) -> void:
	_t += delta
	# 只有雨在动;本体与网格只在状态键变了才重画(2026-08-21 评审:此前三层每帧全画)
	for ch in get_children():
		if ch is RainLayer:
			ch.queue_redraw()
	if Chrome.dirty(_key, [filter, snappedf(_scroll, 0.5), _cards.size()]):
		queue_redraw()
		if _grid != null:
			_grid.queue_redraw()


func _visible_cards() -> Array:
	var out: Array = []
	for c in _cards:
		var ok: bool = filter == 0 \
			or (filter == 1 and c["kind"] == "target") \
			or (filter == 2 and c["kind"] != "target" and c["rarity"] == "common") \
			or (filter == 3 and c["kind"] != "target" and c["rarity"] == "uncommon") \
			or (filter == 4 and c["kind"] != "target" and c["rarity"] == "rare")
		if ok:
			out.append(c)
	return out


func _max_scroll() -> float:
	var rows := int(ceil(float(_visible_cards().size()) / 4.0))
	return maxf(0.0, float(rows) * (CELL_H + GAP) - GAP - GRID.size.y)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll = clampf(_scroll - 90.0, 0.0, _max_scroll())
			return
		if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll = clampf(_scroll + 90.0, 0.0, _max_scroll())
			return
		if ev.button_index != MOUSE_BUTTON_LEFT:
			return
		if ev.pressed:
			if GRID.has_point(ev.position):
				_drag_y = ev.position.y
				_scroll0 = _scroll
				_drag_moved = 0.0
			return
		var was_drag := _drag_y >= 0.0 and _drag_moved > 12.0
		_drag_y = -1.0
		if was_drag:
			return
		var p: Vector2 = ev.position
		for i in range(_chip_rects.size()):
			if (_chip_rects[i] as Rect2).grow(4.0).has_point(p):
				filter = i
				_scroll = 0.0
				return
		var tabs := Chrome.tab_rects()
		for i in range(tabs.size()):
			if (tabs[i] as Rect2).has_point(p) and i != 2:
				menu_pressed.emit(i)
				return
	elif ev is InputEventMouseMotion and _drag_y >= 0.0:
		_drag_moved = maxf(_drag_moved, absf(ev.position.y - _drag_y))
		_scroll = clampf(_scroll0 - (ev.position.y - _drag_y), 0.0, _max_scroll())


func _draw() -> void:
	draw_rect(Rect2(0, 0, W, H), Color("000000"), true)
	Chrome.page_bar(self, Lingo.t("小 丑 牌"), Lingo.t("已实装 %d / %d · Target %d 面旗") %
		[_pooled, _cards.size(), _count_targets()], ACC)
	_draw_filter()
	Chrome.draw_tabs(self, 1, ACC)


func _count_targets() -> int:
	var n := 0
	for c in _cards:
		if c["kind"] == "target":
			n += 1
	return n


func _draw_filter() -> void:
	_chip_rects = []
	var zh := StageTheme.zh()
	var y := 124.0
	draw_string(zh, Vector2(44.0, y + 20.0), Lingo.t("收 藏"), HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
		Color("8ea3c8"))
	var x := 676.0
	for i in range(FILTERS.size() - 1, -1, -1):
		var tw := zh.get_string_size(Lingo.t(FILTERS[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var r := Rect2(x - tw - 26.0, y, tw + 26.0, 28.0)
		x = r.position.x - 10.0
		var on := i == filter
		if on:
			draw_style_box(StageTheme.box(Color(ACC.r, ACC.g, ACC.b, 0.14),
				Color(ACC.r, ACC.g, ACC.b, 0.6), 1, 12), r)
		else:
			draw_style_box(StageTheme.box(Color(0, 0, 0, 0),
				Color(0.67, 0.76, 1.0, 0.16), 1, 12), r)
		draw_string(zh, Vector2(r.position.x, r.position.y + 19.0), Lingo.t(FILTERS[i]),
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 14,
			Color("ffffff") if on else Color("8ea3c8"))
		_chip_rects.append(r)
	_chip_rects.reverse()
	var lx := 44.0 + zh.get_string_size(Lingo.t("收 藏"), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 14.0
	draw_line(Vector2(lx, y + 14.0), Vector2(x - 4.0, y + 14.0),
		Color(ACC.r, ACC.g, ACC.b, 0.35), 1.0)


## 卡画用 source/ 原画(1024²,无文字)而不是 previews/ ——
## previews 是 GPT 烘焙的迷你卡面,**数额烘死在像素里**,平衡一调就变陈数
## (2026-08-12 Target 重锚当场撞上:格角新章 ×10、图里旧章 ×7 并排打架)。
## 原画 + 运行时排字才是单源;alpha bbox 裁掉大边距(同 joker_slot 的做法)。
func _tex(id: String) -> Array:      # [Texture2D, Rect2 bbox] 或空数组
	if _art.has(id):
		return _art[id] if _art[id] is Array else []
	var p := "res://assets/jokers/art512/joker_%s.png" % id
	if not ResourceLoader.exists(p):
		p = "res://assets/jokers/source/joker_%s.png" % id
	if not ResourceLoader.exists(p):
		_art[id] = false
		return []
	var t: Texture2D = load(p)
	var img := t.get_image()
	var bb := img.get_used_rect()
	bb = bb.grow(int(maxf(float(bb.size.x), float(bb.size.y)) * 0.04))
	bb = bb.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	_art[id] = [t, Rect2(bb)]
	return _art[id]


## 网格层的内容(局部坐标,clip_contents 裁掉视口外)。
func draw_grid(ci: CanvasItem) -> void:
	var cards := _visible_cards()
	var cell_w := (GRID.size.x - GAP * 3.0) / 4.0
	var zh := StageTheme.zh()
	var num := StageTheme.num("Bold")
	for i in range(cards.size()):
		var y := float(i / 4) * (CELL_H + GAP) - _scroll
		if y + CELL_H < 0.0 or y > GRID.size.y:
			continue
		var c: Dictionary = cards[i]
		var r := Rect2(float(i % 4) * (cell_w + GAP), y, cell_w, CELL_H)
		var pooled: bool = c["pooled"]
		var dim := 1.0 if pooled else 0.38
		var is_target: bool = c["kind"] == "target"
		var tint: Color = StageTheme.PINK if is_target else RARITY_TINT[c["rarity"]]
		ci.draw_style_box(StageTheme.box(Color(0.07, 0.08, 0.16, 0.5),
			Color(tint.r, tint.g, tint.b, 0.30 if pooled else 0.12), 1, 14), r)
		ci.draw_line(r.position + Vector2(12.0, 0.5), Vector2(r.end.x - 12.0, r.position.y + 0.5),
			Color(0.86, 0.91, 1.0, 0.30 * dim), 1.2)
		# 顶行:稀有度 / 数额
		var tag := "TARGET" if is_target else Lingo.t(String(RARITY_CN[c["rarity"]]))
		ci.draw_string(zh, Vector2(r.position.x + 9.0, r.position.y + 19.0), tag,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(tint.r, tint.g, tint.b, dim))
		if String(c["amount"]) != "":
			ci.draw_string(num, Vector2(r.position.x, r.position.y + 19.0), c["amount"],
				HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 9.0, 12,
				Color(1.0, 1.0, 1.0, 0.9 * dim))
		# 卡画(source 原画按 alpha bbox 装进框)
		var art := _tex(c["id"])
		if not art.is_empty():
			var tex: Texture2D = art[0]
			var src: Rect2 = art[1]
			var box := Rect2(r.position.x + 8.0, r.position.y + 26.0, r.size.x - 16.0, 112.0)
			var sc := minf(box.size.x / src.size.x, box.size.y / src.size.y)
			var dsz := src.size * sc
			ci.draw_texture_rect_region(tex,
				Rect2(box.position + (box.size - dsz) * 0.5, dsz), src,
				Color(1, 1, 1, dim))
		# 名字 + 说明
		ci.draw_string(zh, Vector2(r.position.x, r.position.y + 160.0), c["cn"],
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 16,
			Color(1, 1, 1, 1.0 if pooled else 0.45))
		ci.draw_multiline_string(zh, Vector2(r.position.x + 7.0, r.position.y + 179.0),
			c["trigger"], HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 14.0, 11, 2,
			Color(0.58, 0.65, 0.81, dim))
		# 底行:价格,未实装标事实
		if pooled:
			ci.draw_string(zh, Vector2(r.position.x, r.end.y - 9.0), "◆ %d" % int(c["price"]),
				HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 13, Color("ffd9a0"))
		else:
			ci.draw_string(zh, Vector2(r.position.x, r.end.y - 9.0), Lingo.t("未实装"),
				HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 12, Color("7387a8"))
