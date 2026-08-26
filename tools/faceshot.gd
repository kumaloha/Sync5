extends SceneTree

## Screenshot probe for the 2026-08-07 face batch. Run NON-headless:
##   godot --path . --script res://tools/faceshot.gd
## Renders `_shot_face_sealed.png` — a section under `smallstage`, where the
## cache is short one slot. That slot must read as SEALED BY THE BLIND, not as
## "a card went missing": the whole point of a face that changes the input is
## that the player can see what was taken.
##
## Isolated on purpose (CLAUDE.md: 多 agent 并行时各自建隔离探针) — it stages a
## face through the real `_start_phrase()` path rather than poking the view.

## 哪张脸。`smallstage` 看封槽, `facedown` 看盖牌(牌背朝上)。
## 用环境变量选:`SYNC5_FACE=facedown godot --path . --script res://tools/faceshot.gd`
var FACE: String = Probe.env_str("SYNC5_FACE", "smallstage")

var _scene: Node
var _frames := 0


func _initialize() -> void:
	_scene = Shot.stage(self)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 4:
		_scene.start_run()          # skip the pick screen
	if _frames == 300:
		# ⚠ resolve the face BEFORE _start_phrase(): the cache capacity is
		# applied in Phrase.start(), so staging it afterwards would deal the
		# phrase under the previous section's face (the ordering bug this
		# batch fixed in view/phrase.gd).
		_scene.run.run_faces = {}
		for w in GameConfig.WALL_SECTIONS:
			_scene.run.run_faces[w] = FACE
		_scene.run.section_idx = 1
		_scene.run.phrase_in_section = 0
		_scene._start_phrase()
		# 盖牌那张脸要的是**确定性**画面:随机一手有约 12% 概率一张 J/Q/K 都没有,
		# 那就什么也看不出来。直接注入两张人头牌, 走 Phrase 自己的标记规则。
		if FACE == "facedown":
			_scene.phrase.hand[0] = Card.new(13, 2)      # K♥
			_scene.phrase.hand[2] = Card.new(12, 3)      # Q♠
			_scene.phrase.hidden.clear()
			for c in _scene.phrase.hand:
				if c.rank >= 11 and c.rank <= 13:
					_scene.phrase.hidden[c] = true
			for c in _scene.run.cache:
				if c.rank >= 11 and c.rank <= 13:
					_scene.phrase.hidden[c] = true
			# ⚠ 直捅内部改了 hand 就必须自己触发重绘 —— `_refresh()` 只在状态转移时
			# 被调用, 不是每帧跑。第一版漏了这一句, 截出来的是**注入之前**的画面,
			# 而断言读的是注入之后的状态: 两边看的不是同一个东西, 探针等于没验。
			_scene._refresh()
		var ids := ["twin", "neonsign", "glowstick", "mirror"]
		for i in range(4):
			var j = Joker.by_id(ids[i])
			_scene.run.joker_slots[i] = j
			_scene.joker_views[i].set_joker(j)
	if _frames == 340:
		# 每张脸都有一条**它自己**的非零退出断言 —— 探针只截图不校验, 等于
		# 把「看起来对不对」全交给我肉眼, 而肉眼正是这个项目栽过的地方。
		if FACE == "smallstage":
			var cache_n: int = _scene.run.cache.size()
			print("[faceshot] cache=%d (expect %d)" % [cache_n, GameConfig.CACHE_CAP - 1])
			if cache_n != GameConfig.CACHE_CAP - 1:
				push_error("[faceshot] smallstage did not shrink the cache")
				quit(1)
				return true
		elif FACE == "facedown":
			var hid: int = _scene.phrase.hidden.size()
			var faces_n := 0
			for c in _scene.phrase.hand:
				if c.rank >= 11 and c.rank <= 13:
					faces_n += 1
			for c in _scene.run.cache:
				if c.rank >= 11 and c.rank <= 13:
					faces_n += 1
			print("[faceshot] hidden=%d, J/Q/K on table=%d" % [hid, faces_n])
			var wrong := 0
			for i in range(_scene.phrase.hand.size()):
				var c = _scene.phrase.hand[i]
				if _scene.phrase.hidden.has(c) != _scene.hand.hand_cards[i].show_back:
					wrong += 1
					print("   ✗ hand[%d] %s hidden=%s but show_back=%s"
						% [i, c.glyph(), _scene.phrase.hidden.has(c),
						   _scene.hand.hand_cards[i].show_back])
			if wrong > 0:
				push_error("[faceshot] %d card(s) render face-up while hidden" % wrong)
				quit(1)
				return true
			if hid != faces_n or hid == 0:
				push_error("[faceshot] facedown did not hide exactly the face cards")
				quit(1)
				return true
		var img := get_root().get_texture().get_image()
		img.save_png("res://_shot_face_%s.png" % FACE)
		print("[faceshot] wrote _shot_face_%s.png" % FACE)
		quit(0)
		return true
	return false
