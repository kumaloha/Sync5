extends RefCounted

## 激励视频(2026-09-08, 规格 docs/superpowers/specs/2026-09-08-ads-design.md)。
## 这一域锁三层:① 适配层 view/ads.gd 的假后端与模式选择;② 商店 offer(见 t_shop);
## ③ 编排器两条流的**纯判定**(能不能弹 / 三种发奖情形)—— 流本身由 tools/adsprobe.gd 无头驱动。
## ⚠ 测试自己是 `--script` 起的探针:缺省模式必须是 off(探针零广告痕迹), 显式 SYNC5_ADS 才能改。

func run(t) -> void:
	# ---- ① 适配层 ----
	var a := Ads.new()
	t.get_root().add_child(a)
	# ⚠ runner 在 `_initialize()` 里跑, 那一刻 root 还没 inside_tree ⇒ add_child **不会**触发
	# `_ready`(实测 `get_root().is_inside_tree() == false`), 而测试不许 await 帧 ⇒ 手动打一次。
	a._ready()
	t.eq(a.mode(), "off", "探针缺省 off(截图与日志零广告痕迹)")
	t.check(not a.has_ad("coins"), "off 时没货")
	t.check(not a.has_ad("energy"), "off 时没货(energy)")
	t.check(not a.has_ad("banana"), "未知 kind 永远没货")
	var fails: Array = []
	var rewards: Array = []
	var closes: Array = []
	a.failed.connect(func(k: String, why: String) -> void: fails.append([k, why]))
	a.rewarded.connect(func(k: String) -> void: rewards.append(k))
	a.closed.connect(func(k: String) -> void: closes.append(k))
	a.show_ad("coins")
	t.eq(fails.size(), 1, "没货时 show 立刻 failed")
	t.eq(fails[0][1], "not_ready", "……理由 not_ready")
	# 假后端的三条路径(直接打 _fake_finish, 不等帧)
	a._mode = "fake"
	t.check(a.has_ad("coins"), "fake 有货")
	a._fake_finish("coins")
	t.eq(rewards, ["coins"], "fake 看完发奖")
	t.eq(closes, ["coins"], "……然后关(先奖后关, 与真 SDK 同序)")
	a._mode = "fail"
	a._fake_finish("energy")
	t.eq(fails.size(), 2, "fail 模式发 failed")
	t.eq(fails[1][0], "energy", "……带 kind")
	t.eq(rewards.size(), 1, "fail 模式不发奖")
	a._mode = "dismiss"
	a._fake_finish("coins")
	t.eq(rewards.size(), 1, "dismiss 模式不发奖")
	t.eq(closes.size(), 3, "dismiss 模式只关")
	t.eq(Ads.pick_mode_for(true, "", false), "off", "探针 + 无环境变量 = off")
	t.eq(Ads.pick_mode_for(true, "fake", false), "fake", "显式 SYNC5_ADS=fake 盖过探针(adsprobe 用)")
	t.eq(Ads.pick_mode_for(false, "", false), "fake", "桌面缺省 fake")
	t.eq(Ads.pick_mode_for(false, "off", true), "off", "显式 off 盖过 android")
	t.eq(Ads.pick_mode_for(false, "", true), "admob", "android 且插件在 = admob")
	t.eq(Ads.pick_mode_for(false, "banana", false), "fake", "未知环境值当没设")
	a.queue_free()
