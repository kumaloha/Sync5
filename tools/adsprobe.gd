extends SceneTree

## 激励视频两条流的无头回归(2026-09-08)。假后端驱动, 退出码非 0 = 有违规:
##   SYNC5_ADS=fake SYNC5_PROBE_ENERGY_WALL=1 godot --headless --path . --script res://tools/adsprobe.gd
## 流 A(商店):进店 → 把钱清零 → 点刷新(买不起 ⇒ denied ⇒ offer)→ 点 offer → 下一帧发奖
##   ⇒ 金币 +ad_coins、run.ad_used +1、offer 收起;同店再点刷新 ⇒ **不再弹**(每店上限);
##   下一店再来一次 ⇒ ad_used 2;第三店 ⇒ 不弹(每局上限)。
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
				if _scene.shop.ad_offer_visible():
					_bug("第 %d 店刚开就挂着 offer(close 没收起?)" % _shops)
				_broke()
				_coins_before = _scene.phrase.coins
				_scene.shop._on_reroll()      # 买不起 ⇒ denied ⇒ offer
				_stage = 2
			else:
				_drive_beat()
		2:
			var expect_offer: bool = _shops <= GameConfig.AD_COINS_PER_RUN
			if _scene.shop.ad_offer_visible() != expect_offer:
				_bug("第 %d 店 offer 可见=%s, 应为 %s"
					% [_shops, _scene.shop.ad_offer_visible(), expect_offer])
			if expect_offer:
				_scene.shop._on_ad_offer()
				_wait = 2
				_stage = 3
			else:
				_stage = 4
		3:
			if _scene.phrase.coins != _coins_before + Economy.ad_coins():
				_bug("发奖后金币 %d, 应为 %d"
					% [_scene.phrase.coins, _coins_before + Economy.ad_coins()])
			if _scene.run.ad_used != _shops:
				_bug("run.ad_used=%d, 应为 %d" % [_scene.run.ad_used, _shops])
			if _scene.shop.ad_offer_visible():
				_bug("发奖后 offer 没收起")
			_broke()
			_scene.shop._on_reroll()       # 同店第二次:每店上限 ⇒ 不弹
			if _scene.shop.ad_offer_visible():
				_bug("同一店第二次弹了(每店上限失效)")
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
			var pressed := false
			for c in _scene._energy_layer.get_children():
				if c is Button:
					c.pressed.emit()
					pressed = true
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


## 把钱清成 0。⚠ **两处都要清**:`phrase.coins` 是真账, `shop._coins` 是商店进店时拷的那一份 ——
## 只清前者的话 `_on_reroll()` 拿旧余额判、根本不发 `denied`, 整条 offer 路径一步都没走到
## (而探针会因此「绿得像对了」)。走 `refresh_coins` 是因为游戏侧同步余额用的就是它。
func _broke() -> void:
	_scene.phrase.coins = 0
	_scene.shop.refresh_coins(0)


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
