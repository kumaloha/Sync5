extends SceneTree

## Screenshot probe for the draft shop. Run NON-headless:
##   godot --path . --script res://tools/draft_sheet.gd
## Captures _shot_draft.png (section-end board, one card unaffordable at 5 ◆),
## _shot_draft_mid.png (**mid-section** board: 还差 N 分 · 还剩 N 拍 —— the
## 2026-08-06 decoupled shop), _shot_draft_replace.png (full slots ->
## the incoming card pinned, drag-or-tap onto a slot) and _shot_draft_four.png
## (刚买下联票: 4 张窄版货架 + 「还能再选 2 张」的续买态 —— 2026-09-02 起走
## 真实成交口, 见那一步的注释).

var _scene: Node
var _frames := 0

func _initialize() -> void:
	_scene = Shot.stage(self)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 4:
		_scene.start_run()
	elif _frames == 8:
		# the blind-intro card holds the clock (and phrase creation) until it
		# dismisses — skip it so the mid-run staging below has a phrase
		_scene.intro._dismiss()
	elif _frames == 30:
		# mid-run state: target + one support owned, 5 ◆ — uncommon/rare dim
		# out. Last section so the pivot window is open (a Target may appear);
		# must stay inside the table — Run.next_section() clamps, probes do not.
		_scene.run.section_idx = GameConfig.SECTIONS_PER_RUN - 1
		_set_slot(0, "mono")
		_set_slot(1, "turnover")
		_scene.phrase.coins = 5
		_scene.run.phrase_in_section = 0        # section-end board: 下一场 preview
		_scene._open_draft()
	elif _frames == 60:
		Shot.save(self, "draft")
	elif _frames == 63:
		# the decoupled mid-section shop: same shelf, but the board now reports
		# THIS blind's deficit and beats left instead of previewing the next
		_scene.shop.close()
		_scene.run.phrase_in_section = GameConfig.PHRASES_PER_SHOP
		_scene.run.section_score = 5200
		_scene._open_draft()
	elif _frames == 64:
		Shot.save(self, "draft_mid")
	elif _frames == 66:
		# full board, 7 ◆ -> tapping a candidate enters replace mode
		_scene.shop.close()
		# ⚠⚠ **这三个槽此前也是空的**(2026-09-02 与下面那步同一个病根):写的是
		# `shortcut` / `blacktone` / `fourfingers` —— 规则牌 2026-08-30 全部转生为
		# 消耗牌, `Joker.by_id()` 拿回 null ⇒ **槽根本没满**, `_on_pick(0)` 直接买入装槽、
		# 关店 ⇒ 这张「满槽换卡」的验收图拍到的是**局内画面**, 而它绿着。
		# ⇒ 换成真的 support 小丑牌(id 从 data/jokers.json 来)。
		_set_slot(1, "tipjar")
		_set_slot(2, "chord")
		_set_slot(3, "neonsign")
		_scene.phrase.coins = 7
		_scene.run.phrase_in_section = 0
		_scene._open_draft()
	elif _frames == 72:
		_scene.shop._on_pick(0)
	elif _frames == 100:
		Shot.save(self, "draft_replace")
	elif _frames == 104:
		# 联票态:货架 4 位窄版(card_w_4)+ 续买态副标题。
		#
		# ⚠⚠ **这一步此前是死的**(2026-09-02 发现):它写的是
		# `_set_slot(1, "doublebill")` / `_set_slot(2, "sponsor")` —— 而这两张
		# **2026-08-30 已经转生为消耗牌**, `Joker.by_id()` 拿回 null ⇒ 货架一直是 3 张,
		# 这张「四位货架验收图」验的是**三位货架**, 而且它绿着。
		# (「规则搬了家, 探针还站在旧地址」——本项目第 N 次, 见 LESSONS 假绿那一节。)
		# ⇒ 改成走**真实成交口** `_on_consumable_bought`:它会执行 grant_shelf(4, 2)、
		#   记一次成交、算配额、喂副标题 —— 一张图同时验四件事。
		_scene.replace.exit()
		_scene.shop.close()
		_set_slot(1, "")     # by_id("") = null, 空出一格让「买入装槽」路径可走
		_set_slot(2, "")
		_scene.phrase.coins = 12
		_scene.run.phrase_in_section = 0
		_scene._open_draft()
	elif _frames == 112:
		# 买下联票(与玩家点货架上那张碟走同一条路)
		for e in DB.consumables():
			if String(e["id"]) == "doublebill":
				var c := Consumable.new(e)
				if not _scene._coffer.is_empty():
					_scene._coffer[0] = c
				_scene._on_consumable_bought(c, c.price)
				break
	elif _frames == 130:
		Shot.save(self, "draft_four")
		quit()
	return false

func _set_slot(i: int, id: String) -> void:
	var j = Joker.by_id(id)
	_scene.run.joker_slots[i] = j
	_scene.joker_views[i].set_joker(j)