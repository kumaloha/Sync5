extends SceneTree
## 消耗牌的反事实定价 —— **一张消耗牌值多少分**。
##   godot --headless --path . --script res://tools/ccf.gd
##
## ⚑ 为什么不能用 `cf.gd`:那把尺量的是「**装着一整局**的卡」(每拍都跑两次 Settle
## 取差), 而消耗牌**一局只生效一次**。直接套会把一次性效果按 24 拍摊开, 高估 24 倍。
##
## 做法 = 从 Tape 取真人拍的 ctx, 对每张消耗牌算**单次**收益:
##   拍内加成类 → `Settle.run(res, slots, ctx + boost) − Settle.run(res, slots, ctx)`
##   牌堆/商店类 → 本尺**量不到**(它们不改这一拍的分, 改的是后续的牌流/货架),
##                 显式标注不出值 —— 与 cf.gd 对成长牌的处理同款。
##
## ⚠⚠ **定价要除以「一局能吃几张」**(numbers.md §2.52):永久卡受 4 槽硬限,
## 消耗牌用完即空、总量只受钱限制。本尺给的是**单张**价值, 换算成价格时
## 必须再除以实测的「买入张数/局」(sim 报表的「消耗牌:买 N 张/局」)。
const SCALE_FLOOR := 40.0     # 拍均分低于此的 Tape 不用(早期版本的分数尺度不同)

var _cf

func _initialize() -> void:
	_cf = load("res://tools/cf.gd").new()
	var beats: Array = []
	for path in _cf._qualified_logs():
		beats += _cf._beats_of(path)
	print("可用 Tape 拍:%d" % beats.size())
	var rows: Array = []
	for e in DB.consumables():
		var c := Consumable.new(e)
		if c.boost.is_empty():
			rows.append({"id": c.id, "cn": c.cn_name, "price": c.price,
				"ev": -1.0, "note": "本尺量不到(牌堆/商店类 —— 不改这一拍的分)"})
			continue
		rows.append(_score_one(c, beats))
	print("=== 消耗牌的单次价值(反事实,真人 Tape) ===")
	print("%-12s %-8s %6s %10s %10s" % ["id", "cn", "价格", "单次Δ分", "分/◆"])
	for r in rows:
		if float(r["ev"]) < 0.0:
			print("%-12s %-8s %5s◆ %10s   %s" % [r["id"], r["cn"], r["price"], "—", r["note"]])
		else:
			print("%-12s %-8s %5s◆ %10.1f %10.1f" % [r["id"], r["cn"], r["price"],
				r["ev"], float(r["ev"]) / maxf(1.0, float(r["price"]))])
	print("\n⚠ 「分/◆」不能直接跟小丑牌比 —— 见 numbers.md §2.52:")
	print("   永久卡受 4 槽硬限, 消耗牌总量只受钱限制, 要再除以「买入张数/局」。")
	quit(0)


## ⚠ 复用 `cf.gd` 的 Tape 读取与构筑还原 —— **不许各写一份**
## (「同一件事两份实现」是本项目最贵的形状之一)。
func _score_one(c: Consumable, beats: Array) -> Dictionary:
	var tot := 0.0
	var n := 0
	for b in beats:
		var res: Dictionary = b.get("res", {})
		if res.is_empty():
			continue
		var ctx: Dictionary = b.get("ctx", {})
		var slots: Array = _cf._slots_of(b.get("held", []), "")
		var a := int(Settle.run(res, slots, ctx).get("score", 0))
		if float(a) < SCALE_FLOOR:
			continue
		var ctx2 := ctx.duplicate()
		ctx2["phrase_boosts"] = [c.boost]
		var d := int(Settle.run(res, slots, ctx2).get("score", 0))
		tot += float(d - a)
		n += 1
	return {"id": c.id, "cn": c.cn_name, "price": c.price,
		"ev": (tot / float(n)) if n > 0 else -1.0,
		"note": "没有可用的 Tape 拍" if n == 0 else ""}
