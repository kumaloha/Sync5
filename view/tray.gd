class_name TicketTray
extends Control

## 局内券托盘(2026-08-17 券的使用入口)—— 拍内 scope 的券在这里点着用。
##
## 设计三条:
## · **数据全由编排器注入**(`show_tickets`), 本组件不碰 SaveState —— 组件对外只发
##   意图信号(铁律), 而且注入让截图探针不受「探针拿不到券」那道闸的影响。
## · **chips 用 Button**(商店 `_button` 同款)—— 这批刚修过两条「全屏 PASS / 默认 STOP
##   盖住别人」的命中 bug, 自定义命中测试不值得再冒一次险。
## · **托盘只占自己那几个 chip 的矩形**(右对齐، 动态收缩), 不铺全宽 ——
##   铺全宽就算 PASS 也会把事件从 EQ 条带手里抢走(PASS ≠ 透明, LESSONS)。
##
## 摆位:EQ 条带那一行的右端(y 由 data/ui.json 的 tickets 节给)。
## 教学关不显示 —— 券是局外系统, 混进教学会多一个要解释的东西。

signal use(tid: String)

const ORDER := ["overtime", "redeal", "boost"]   # 拍内券的固定顺序(时间→牌→分)

var _cfg: Dictionary = {}
var _buttons: Array = []


func _ready() -> void:
	_cfg = DB.ui().get("tickets", {})
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # 容器自己永远不拦事件, 只有 chip 拦


## 重建 chips。`held` = {tid: 张数}(编排器从 SaveState 读来), `boost_next` = boost
## 队首的掷值(0 = 没有)。空托盘自动隐藏。`armed_text` != "" 时在队尾亮一个
## 不可点的「已上」标牌 —— 用了 boost 之后这一拍必须看得见它还在生效
## (「冻结是看不见的」同一课:看不见的增益和没生效长得一样)。
func show_tickets(held: Dictionary, boost_next: float, armed_text: String = "") -> void:
	for b in _buttons:
		b.queue_free()
	_buttons.clear()
	var chip_w := float(_cfg.get("chip_w", 116))
	var chip_h := float(_cfg.get("chip_h", 42))
	var gap := float(_cfg.get("gap", 8))
	var entries: Array = []
	for tid in ORDER:
		var n := int(held.get(tid, 0))
		if n <= 0:
			continue
		entries.append({"tid": tid, "label": _label_for(String(tid), n, boost_next)})
	if armed_text != "":
		entries.append({"tid": "", "label": armed_text})
	if entries.is_empty():
		visible = false
		return
	var w := entries.size() * chip_w + (entries.size() - 1) * gap
	size = Vector2(w, chip_h)
	position = Vector2(float(_cfg.get("right_x", 694)) - w, float(_cfg.get("y", 628)))
	for i in range(entries.size()):
		var e: Dictionary = entries[i]
		var armed := String(e["tid"]) == ""
		var b := Button.new()
		b.text = String(e["label"])
		b.add_theme_font_override("font", StageTheme.zh())
		b.add_theme_font_size_override("font_size", 17)
		b.custom_minimum_size = Vector2(chip_w, chip_h)
		b.position = Vector2(i * (chip_w + gap), 0)
		b.focus_mode = Control.FOCUS_NONE
		# 券 = 金(货币语义家族:金币金、宝石紫);armed 态亮金实心, 可点态暗玻璃金边
		var sb := StageTheme.box(Color(0.32, 0.2, 0.05, 0.92), Color("ff9b2b"), 1, 12) if armed \
			else StageTheme.box(Color(0.09, 0.07, 0.03, 0.82), Color(1.0, 0.61, 0.17, 0.55), 1, 12)
		for st in ["normal", "hover", "pressed", "disabled"]:
			b.add_theme_stylebox_override(st, sb)
		b.add_theme_color_override("font_color", Color("ffd9a0"))
		if armed:
			b.disabled = true    # armed 标牌也用 Button 画(省一套 Label 排版), 只是不可点
		else:
			var tid := String(e["tid"])
			b.pressed.connect(func() -> void: use.emit(tid))
		add_child(b)
		_buttons.append(b)
	visible = true


func _label_for(tid: String, n: int, boost_next: float) -> String:
	var cn := Lingo.pick(Ticket.by_id(tid))
	var tail := ""
	if tid == "boost" and boost_next > 0.0:
		tail = " ×%.1f" % boost_next
	if n > 1:
		tail += " ·%d" % n
	return cn + tail
