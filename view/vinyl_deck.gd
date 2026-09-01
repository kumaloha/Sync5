class_name VinylDeck
extends Control

## 唱片位 —— **待播队列**(2026-09-01 用户拍板还原成光碟, 并接了新职责)。
##
## ## 它经历过什么(别再往回加)
## 2026-08-13 它是「牌堆 + 提前收工键 + 转盘」三合一;08-31 三个职责被用户逐条取消
## (「不要提前结束的机制了」·「牌堆剩余干脆不显示」), 位置让给了消耗品栏, 整个文件删掉。
## 09-01 消耗牌改成**全部自动触发**, 栏位这个概念没了, 位置空出来 ——
## 用户:「光碟的位置还原成光碟」+「币变成碟就可以了, 最多应该是 3 个」。
## ⚠ **金色角标(牌堆剩余)与金环(提前收工)不还原** —— 那两个机制真的退役了,
## 画回来等于把删掉的东西又画上。
##
## ## 现在它说两件事
## ① 空着 = 一张转着的唱片(青绿标签), 承担排版铁律里「左中右」的右段配重;
## ② 有排队的消耗牌 = 它们以**碟**的样子并排在这儿(红标签 + 刻着自己的拍号),
##    **左→右就是播放顺序**。第 4 张叠成 `+1`(上限 4 是算出来的, 见 `Run.consumables`)。
## ⚑ 「币」与「碟」是同一样东西:商店里你买的是一张碟, 买完它排进歌单, 到点它播。

const MAX_SHOWN := 3
## ⚠ 几何是**解出来的, 不是拍的**:三碟并排的总宽必须正好等于唱片位的 132 ——
## `DISC_D + PITCH × (MAX_SHOWN − 1) = 52 + 40 × 2 = 132`。
## 首版取 56/46 得 148, 比框宽 16px, 会往左压到音浪(渲出来才看见)。
const DISC_D := 52.0
const PITCH := 40.0

var queue: Array = []      # [{id, beat, name}] —— 先打的在前
var _angle := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # 它不可点:自动触发之后没有「点」这一步


func set_queue(q: Array) -> void:
	queue = q
	queue_redraw()


func _process(delta: float) -> void:
	_angle += 0.5 * delta
	queue_redraw()


func _draw() -> void:
	if queue.is_empty():
		_draw_disc(size * 0.5, minf(size.x, size.y) * 0.5 - 4.0, "", true, 1.0)
		return
	var n: int = mini(queue.size(), MAX_SHOWN)
	var span := DISC_D + PITCH * float(n - 1)
	var x0 := (size.x - span) * 0.5
	var cy := size.y * 0.5
	# ⚠ **倒着画** —— 先画右边的, 让左边(先打的那张)压在最上层。
	for i in range(n - 1, -1, -1):
		var front := i == 0
		_draw_disc(Vector2(x0 + DISC_D * 0.5 + PITCH * float(i), cy), DISC_D * 0.5,
			String(queue[i].get("beat", "")), false, 1.0 if front else 0.62)
	if queue.size() > MAX_SHOWN:
		_badge(Vector2(x0 + span + 4.0, cy - DISC_D * 0.5), "+%d" % (queue.size() - MAX_SHOWN))


## 一张唱片。`teal` = 空态的青绿标签(唱机本身);否则红标签 + 拍号(消耗牌)。
func _draw_disc(c: Vector2, r: float, stamp: String, teal: bool, bright: float) -> void:
	var edge := Color(0.63, 0.71, 1.0, 0.35) if teal \
		else Color(StageTheme.SUIT_RED.r, StageTheme.SUIT_RED.g, StageTheme.SUIT_RED.b, 0.62 * bright)
	var halo := Color(StageTheme.CYAN.r, StageTheme.CYAN.g, StageTheme.CYAN.b, 0.20) if teal \
		else Color(StageTheme.SUIT_RED.r, StageTheme.SUIT_RED.g, StageTheme.SUIT_RED.b, 0.24 * bright)
	draw_circle(c, r + 4.0, halo)
	draw_circle(c, r, Color(0.043, 0.055, 0.125, bright))
	draw_arc(c, r, 0, TAU, 64, edge, 2.0)
	# 纹槽 —— 4.5px 一圈, 与退役前逐字一致
	var gr := r * 0.44
	while gr < r - 2.5:
		draw_arc(c, gr, 0, TAU, 48, Color(0.63, 0.71, 1.0, 0.10 * bright), 1.0)
		gr += 4.5
	# 旋转高光:「它在转」这件事只靠这两道弧说
	draw_arc(c, r * 0.72, _angle, _angle + 0.9, 18, Color(1, 1, 1, 0.14 * bright), maxf(2.0, r * 0.08))
	draw_arc(c, r * 0.60, _angle + PI, _angle + PI + 0.7, 14, Color(1, 1, 1, 0.09 * bright), maxf(1.6, r * 0.06))
	if teal:
		draw_circle(c, r * 0.34, Color("2ab5aa"))
		draw_circle(c, r * 0.30, Color("7cf3e8"))
		draw_circle(c, 2.5, Color("0b0e20"))
		draw_circle(c + Vector2(cos(_angle), sin(_angle)) * r * 0.32, 2.0, Color("0b0e20"))
		return
	# 消耗牌的碟:红标签, 上面刻着它的拍号(或 ▸ = 下一拍)
	draw_circle(c, r * 0.40, Color(StageTheme.SUIT_RED.r * 0.62, StageTheme.SUIT_RED.g * 0.22,
		StageTheme.SUIT_RED.b * 0.36, bright))
	draw_arc(c, r * 0.40, 0, TAU, 32,
		Color(StageTheme.SUIT_RED.r, StageTheme.SUIT_RED.g, StageTheme.SUIT_RED.b, 0.85 * bright), 1.5)
	if stamp != "":
		var f: Font = StageTheme.num("Bold")
		var fs := int(r * 0.48)
		var w := f.get_string_size(stamp, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, c + Vector2(-w * 0.5, fs * 0.36), stamp,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, bright))


func _badge(at: Vector2, txt: String) -> void:
	var f: Font = StageTheme.num("Bold")
	var r := Rect2(at, Vector2(26, 20))
	draw_style_box(StageTheme.box(Color(0.02, 0.02, 0.05, 0.95),
		Color(StageTheme.SUIT_RED.r, StageTheme.SUIT_RED.g, StageTheme.SUIT_RED.b, 0.75), 1, 10), r)
	draw_string(f, Vector2(r.position.x, r.position.y + 15), txt,
		HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 12, Color.WHITE)
