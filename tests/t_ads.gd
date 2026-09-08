extends RefCounted

## 激励视频(2026-09-08, 规格 docs/superpowers/specs/2026-09-08-ads-design.md)。
## 这一域锁三层:① 适配层 view/ads.gd 的假后端与模式选择;② 商店 offer(见 t_shop);
## ③ 编排器两条流的**纯判定**(能不能弹 / 三种发奖情形)—— 流本身由 tools/adsprobe.gd 无头驱动。
## ⚠ 测试自己是 `--script` 起的探针:缺省模式必须是 off(探针零广告痕迹), 显式 SYNC5_ADS 才能改。

func run(t) -> void:
	# ---- ① 适配层 ----
	var a := Ads.new()
	# ⚠ runner 在 `_initialize()` 里跑, 那一刻 root 还没 inside_tree ⇒ add_child **不会**触发
	# `_ready`(实测 `get_root().is_inside_tree() == false`), 而测试不许 await 帧 ⇒ 干脆不进树, 手动打一次。
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
	t.eq(Ads.pick_mode_for(true, "", false, true), "off", "探针 + 无环境变量 = off")
	t.eq(Ads.pick_mode_for(true, "fake", false, true), "fake", "显式 SYNC5_ADS=fake 盖过探针(adsprobe 用)")
	t.eq(Ads.pick_mode_for(false, "", false, true), "fake", "debug 桌面缺省 fake")
	t.eq(Ads.pick_mode_for(false, "off", true, true), "off", "显式 off 盖过 android")
	t.eq(Ads.pick_mode_for(false, "", true, true), "admob", "android 且插件在 = admob")
	t.eq(Ads.pick_mode_for(false, "", true, false), "admob", "插件在就走真后端(与 debug 无关)")
	t.eq(Ads.pick_mode_for(false, "banana", false, true), "fake", "未知环境值当没设")
	# ⚑ 导出的正式包没插件 ⇒ 什么都不给。假后端白发奖比不给钱贵得多(2026-09-08 质量审查)。
	t.eq(Ads.pick_mode_for(false, "", false, false), "off", "导出包没插件 = off, 绝不假发奖")
	t.eq(Ads.pick_mode_for(true, "fake", false, false), "fake", "显式环境值盖过一切")
	t.check(not Ads.has_plugin_class("RewardedAdLoader"), "本仓库没装插件 ⇒ 类表里没有")
	a.free()

	# ---- ③ 编排器的纯判定(view/phrase.gd 静态函数, 流本身由 tools/adsprobe.gd 驱动)----
	var PV = load("res://view/phrase.gd")
	t.check(PV.ad_offer_ok(true, false, 0, 0, 0, []), "有货 + 非教学 + 零次 ⇒ 弹")
	t.check(not PV.ad_offer_ok(false, false, 0, 0, 0, []), "没货不弹")
	t.check(not PV.ad_offer_ok(true, true, 0, 0, 0, []), "教学关不弹")
	t.check(not PV.ad_offer_ok(true, false, 0, GameConfig.AD_COINS_PER_SHOP, 0, []), "本店到顶不弹")
	t.check(not PV.ad_offer_ok(true, false, GameConfig.AD_COINS_PER_RUN, 0, 0, []), "本局到顶不弹")
	var capped: Array = [null, Joker.by_id("skint"), null, null]
	t.check(not PV.ad_offer_ok(true, false, 0, 0, Joker.slots_coin_cap(capped), capped),
		"坐在金币上限上不弹(发了也入不了账, Economy.ad_coins_allowed 的护栏)")
	# 发奖三情形:store / late / drop(规格 §4.3 表)
	t.eq(PV.ad_reward_case(true, PV.St.DRAFT), "store", "run 活着且在 DRAFT ⇒ 店内入账")
	t.eq(PV.ad_reward_case(true, PV.St.DECISION), "late", "run 活着但在拍中(DECISION)⇒ 晚到照发")
	t.eq(PV.ad_reward_case(false, PV.St.DRAFT), "drop", "run 没了 ⇒ 丢")
	t.eq(PV.ad_reward_case(true, PV.St.FRONT), "drop", "FRONT ⇒ 丢(首页没有局)")
	t.eq(PV.ad_reward_case(true, PV.St.END), "drop", "END ⇒ 丢(结算屏之后没有店可花)")
	# 体力墙的纯判定:有货 且 存档允许(未满 + 今日未到顶)才把墙变成入口;探针强制开关只给 adsprobe 用
	t.check(PV.energy_wall_ok(true, true), "有货 + 存档允许 ⇒ 墙变入口")
	t.check(not PV.energy_wall_ok(false, true), "没货 ⇒ 今天的行为(明天回满)")
	t.check(not PV.energy_wall_ok(true, false), "存档不许(满值/到顶)⇒ 今天的行为")
	t.check(not DB.lingo()["table"].has("看广告补体力 · 敬请期待"), "「敬请期待」那句已删(表里没有)")

	# ---- ④ 赞助碟取代了 offer 按钮(2026-09-09)——「同一件事只留一套机制」的机械锁 ----
	# ⚠ 反向断言(表里/配置里**没有**)是这条替换唯一守得住的形状:留着旧文案不报错,
	#   下一个人会以为两套并存(t_lingo 的孤儿检查会红, 但它说不出为什么该删)。
	t.check(not DB.lingo()["table"].has("差 %d◆ · 看广告 +%d◆"), "offer 的缺口文案已删")
	t.check(not DB.lingo()["table"].has("看广告 +%d◆"), "offer 的无缺口文案已删")
	var shop_cfg: Dictionary = DB.ui()["shop"]
	t.check(not shop_cfg.has("ad_offer_text"), "ui.json 的 offer 文案键已删")
	t.check(not shop_cfg.has("ad_offer_pos"), "ui.json 的 offer 位置键已删")
	t.check(shop_cfg.has("cons_col_w_3"), "三碟排布的列宽在 ui.json(改布局 = 改 JSON)")
	t.check(shop_cfg.has("sponsor_free_text"), "赞助碟价签的「免费」在 ui.json")
	# 卡面上的数 = 发出去的数(parity 第四层同一条账)
	t.eq(Economy.ad_coins(), int(Consumable.sponsor_entry()["action"]["ad_coins"]),
		"发几◆ 从赞助碟的 action 上读(数住在卡上)")
