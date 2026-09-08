extends SceneTree

## 激励视频两条流的无头回归(2026-09-08)。假后端驱动, 退出码非 0 = 有违规:
##   SYNC5_ADS=fake SYNC5_PROBE_ENERGY_WALL=1 godot --headless --path . --script res://tools/adsprobe.gd
## 流 A(商店, 2026-09-09 赞助商版):进店 ⇒ 货架第三位是赞助碟 → 点它 → 下一帧发奖
##   ⇒ 金币 +ad_coins、run.ad_used +1、**碟离架**(_coffer 回到 2);同店再点第三位 ⇒ **无操作**
##   (每店上限 1);下一店再来一次 ⇒ ad_used 2;第三店 ⇒ **不上架**(每局上限 2)。
## ⚠ 钱不再是这条流的变量 —— 碟是免费的。断言只看「在不在架上」与「发没发钱」。
## 流 B(体力墙):局中直接调 _deny_no_energy()(它自己先 _open_home() —— 首页是底,
##   与真人「开始 → 体力不够」同序;探针恒满, 靠 SYNC5_PROBE_ENERGY_WALL 开层)
##   ⇒ 层在 ⇒ **先点空白处**(真输入路径 push_input)⇒ 层关、意图清空、还在首页
##   ⇒ 再撞一次墙重开层 ⇒ 点键 ⇒ 发奖 ⇒ 层没了 ⇒ **run 开了**(state 离开 FRONT = _pending_start 兑现了)。
## ⚠ 空白点击这条断言锁的是暗幕的 `mouse_filter` —— 缺省 STOP 会把点击吞掉,
##   `layer.gui_input` 永远收不到(2026-09-08 spec 审查抓到)。
## ⚠ 靠 SYNC5_ADS=fake 显式盖过探针的 off(view/ads.gd::pick_mode_for)—— 不设就全是 no-op, 探针会红。
## ⚠ 改这个探针要做 A/B 验证(注入假 bug 确认它真报警), 项目铁律。
##
## 状态用裸数字(与 flow_probe / tapeprobe 同款):St 是被测脚本的枚举, 探针这侧只有 Node 静态类型。
const ST_FRONT := 0
const ST_INTRO := 1
const ST_DECISION := 2
const ST_RESOLVE := 3
const ST_DRAFT := 4
const ST_END := 5

var _scene: Node
var _frames := 0
var _bugs := 0
var _stage := 0
var _shops := 0
var _coins_before := 0
var _wait := 0


func _initialize() -> void:
	get_root().set_content_scale_size(Vector2i(720, 1280))
	if OS.get_environment("SYNC5_ADS") != "fake":
		print("!!! 需要 SYNC5_ADS=fake(探针缺省 off)")
		quit(2)
		return
	_scene = load("res://view/phrase.tscn").instantiate()
	get_root().add_child(_scene)


func _bug(msg: String) -> void:
	print("!!! BUG: " + msg)
	_bugs += 1


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames > 20000:
		_bug("超时:探针没跑完(stage=%d)" % _stage)
		return _finish()
	if _wait > 0:
		_wait -= 1
		return false
	match _stage:
		0:
			if _frames == 4:
				_scene._on_home_start()      # 首页 → 开局(它自己调 start_run)
				_stage = 1
		1:
			# 等一家店开
			if _scene.state == ST_DRAFT:
				_shops += 1
				var want: bool = _shops <= GameConfig.AD_COINS_PER_RUN
				if _sponsor_on_shelf() != want:
					_bug("第 %d 店赞助碟在架=%s, 应为 %s(每局上限 %d)"
						% [_shops, _sponsor_on_shelf(), want, GameConfig.AD_COINS_PER_RUN])
				if not want:
					_stage = 4
				else:
					_coins_before = _scene.phrase.coins
					_scene.shop._on_cshelf_pressed(2)     # 点第三张碟 = 放一段插播
					_wait = 2
					_stage = 3
			else:
				_drive_beat()
		3:
			if _scene.phrase.coins != _coins_before + Economy.ad_coins():
				_bug("发奖后金币 %d, 应为 %d"
					% [_scene.phrase.coins, _coins_before + Economy.ad_coins()])
			if _scene.run.ad_used != _shops:
				_bug("run.ad_used=%d, 应为 %d" % [_scene.run.ad_used, _shops])
			if _scene._coffer.size() != 2:
				_bug("发奖后碟没离架(_coffer=%d, 应为 2)" % _scene._coffer.size())
			if _sponsor_on_shelf():
				_bug("发奖后赞助碟还在架上(每店上限失效?)")
			# 同店第二次点第三位:碟已离架 ⇒ 必须是**无操作**(不再发一次奖)
			var coins_now: int = _scene.phrase.coins
			var used_now: int = _scene.run.ad_used
			_scene.shop._on_cshelf_pressed(2)
			if _scene.phrase.coins != coins_now or _scene.run.ad_used != used_now:
				_bug("同一店第二次点第三位又发了一次(金币 %d→%d, ad_used %d→%d)"
					% [coins_now, _scene.phrase.coins, used_now, _scene.run.ad_used])
			_stage = 4
		4:
			_scene._on_shop_skipped()      # 「继续 ▸」离店
			if _shops >= GameConfig.AD_COINS_PER_RUN + 1:
				_stage = 5
			else:
				_stage = 1
		5:
			# 流 B:撞墙。`_deny_no_energy` 自己先开首页(首页是底), 与真人同序。
			if not _wall_up():
				return _finish()
			# 出口一:点空白处(面板在 150..570 × 500..710, 取左上角一定在外面)。
			# ⚠ 走真输入路径 —— 直接调 _close_energy_wall 会**空绿**(暗幕吞点击这个 bug 照样过)。
			_tap(Vector2(30, 30))
			_wait = 2
			_stage = 6
		6:
			if _scene._energy_layer != null:
				_bug("点空白处没关层(暗幕 mouse_filter 吞了点击?)")
			if _scene.state != ST_FRONT:
				_bug("点空白关层后不该开局(state=%d)" % _scene.state)
			if _scene._pending_start.is_valid():
				_bug("点空白关层后 _pending_start 没清")
			if _bugs == 0:
				print("adsprobe: blank-tap closed wall")
			# 出口二:重开层 → 点键 → 发奖
			if not _wall_up():
				return _finish()
			# ⚠ 只按**第一枚**(「看广告」)—— 层里的第二枚是「不看了」, 按下去会当场关层,
			#   发奖那一支就再也走不到了(而断言会红得看不出理由)。
			var pressed := false
			for c in _scene._energy_layer.get_children():
				if c is Button:
					c.pressed.emit()
					pressed = true
					break
			if not pressed:
				_bug("体力墙层里没有按钮")
				return _finish()
			_wait = 3
			_stage = 7
		7:
			if _scene._energy_layer != null:
				_bug("发奖后层没关")
			if _scene.state == ST_FRONT:
				_bug("发奖后没开局(_pending_start 没兑现)")
			return _finish()
	return false


## 撞一次墙并确认层开了。返回 false = 已经报过 bug, 调用方该收工。
func _wall_up() -> bool:
	_scene._deny_no_energy()
	if _scene.state != ST_FRONT:
		_bug("撞墙后没回首页(state=%d)" % _scene.state)
	if _scene._energy_layer == null:
		_bug("体力墙没开层(SYNC5_PROBE_ENERGY_WALL 没生效?)")
		return false
	return true


## 一次真点击(按下 + 抬起)喂给根视口 —— 让 GUI 自己去做命中测试, 探针不认识那一层的回调。
## ⚠ **必须 in_local_coords = true**:无头窗口只有 64×64, 而 stretch=canvas_items 会把窗口
## 坐标按 0.05 的比例映射回 720×1280 —— (30,30) 传进去落在 (320,600), 正好在面板里,
## 于是「点空白」变成了「点面板」, 断言恒红且理由完全看不出来(踩过, 2026-09-08)。
func _tap(at: Vector2) -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = at
		ev.global_position = at
		get_root().push_input(ev, true)


## 赞助碟此刻在不在货架第三位。⚠ 查的是**编排器的 `_coffer`**(货架的真相), 不是屏幕上那个按钮 ——
## 视图的碟位恒建 3 个, 只是藏起来, 问它「有没有」会恒真。
func _sponsor_on_shelf() -> bool:
	return _scene._coffer.size() == 3 and _scene._coffer[2] != null and _scene._coffer[2].is_sponsor()


## 推进一拍(与 flow_probe 同款:强行过关 + 把钟拨到锁定, 让被测代码自己走结算)。
## ⚠ 不调 `_settle()` —— 它只在 DECISION 且钟到点时才该发生, 手捅会绕过 `_process` 的那一段。
func _drive_beat() -> void:
	match _scene.state:
		ST_FRONT:
			_scene._on_home_start()
		ST_INTRO:
			if _scene.intro != null and is_instance_valid(_scene.intro):
				_scene.intro._dismiss()
		ST_DECISION:
			_scene.run.section_score = 999999   # 保证过关:探针要的是商店, 不是难度
			_scene.elapsed = 999.0
		ST_RESOLVE:
			_scene.elapsed = 999.0
		ST_END:
			_scene._on_end_retry()


func _finish() -> bool:
	print("adsprobe: shops=%d bugs=%d frames=%d" % [_shops, _bugs, _frames])
	quit(1 if _bugs > 0 else 0)
	return true
