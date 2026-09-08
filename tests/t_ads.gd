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
	# ⚑ **到货信号**(2026-09-09 审查):`has_ad` 只回答「此刻有没有」, 而 Android 上它是异步变真的
	# ⇒ 只在进店那一刻问一次的界面永远等不到货。假后端也发它, 好让桌面走一遍编排器的补上架那条路。
	t.check(a.has_signal("loaded"), "适配层有到货信号 loaded")
	var loads: Array = []
	a.loaded.connect(func(k: String) -> void: loads.append(k))
	a._mode = "fake"
	a.load_ad("coins")          # 排的是 call_deferred, 测试不等帧 ⇒ 紧接着直打一次
	a._fake_loaded("coins")
	t.eq(loads, ["coins"], "假后端 load_ad 也发 loaded(桌面照样走补上架那条路)")
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
	# ⚠ `Script.has_method()` 问的是 Script **这个 Resource 自己**的方法(实测恒 false),
	#   脚本里定义的要走 `get_script_method_list()` —— 4.6 也没有 `has_script_method`。
	var pv_methods := {}
	for m in PV.get_script_method_list():
		pv_methods[String(m["name"])] = true
	t.check(pv_methods.has("_on_ad_loaded"), "编排器接到货那一刻的补上架口(ads.loaded → 赞助碟)")
	# 赞助碟在不在架 = **按末位判**(2026-09-09 终审):`_coffer.size() >= 3` 只在底座恰好两张时
	# 才等价, 而底座是掷出来的(池抽干就会短)⇒ 那一刻长度口径会把随机碟错认成赞助碟, 不报错。
	t.check(pv_methods.has("_has_sponsor_slot"), "第三位按末位判的那个口(不拿长度当身份)")
	# 「发钱那一刻上限变假」得有话说 —— 那一刻不是「没广告」, 拿失败那句糊过去等于骗玩家再看一次
	t.check(DB.lingo()["table"].has("这次没法入账,金币已到上限"), "入不了账时的那句在表里")
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
	# 「免费」只有一家:赞助碟价签与刷新键共用 `free_text`(同一个词两个键 = 改一处漏一处)
	t.check(not shop_cfg.has("sponsor_free_text"), "赞助专用的第二个「免费」键已删")
	t.check(shop_cfg.has("free_text"), "……价签与刷新键共用 free_text 这一家")
	# 卡面上的数 = 发出去的数(parity 第四层同一条账)
	t.eq(Economy.ad_coins(), int(Consumable.sponsor_entry()["action"]["ad_coins"]),
		"发几◆ 从赞助碟的 action 上读(数住在卡上)")

	# ---- ⑤ 体力墙 = 赞助商的玻璃卡(2026-09-09)----
	# 招牌是**一枚几何两处用**(碟中心 + 墙的眉行)。锁的是这条共用, 不是像素:
	# 抄成两份不会报错, 但下一次改招牌只会改到一处 —— 那正是这个项目最贵的形状。
	t.check(Callable(Widgets.SponsorSign, "draw").is_valid(), "招牌小件有静态画法(碟与眉行共用)")
	var sign_box: Rect2 = Widgets.SponsorSign.box_rect(Vector2(100.0, 100.0), 20.0)
	t.eq(sign_box.size, Vector2(18.8, 13.2), "招牌牌面 = 0.94r × 0.66r(画布剖面)")
	t.eq(sign_box.get_center(), Vector2(100.0, 100.0), "……居中在给的圆心上")
	# 墙的文案换成赞助商口径:旧的两句必须**从表里消失**(留着不报错, 但下一个人会以为两套并存)
	t.check(not DB.lingo()["table"].has("体力不足"), "旧墙标题「体力不足」已删")
	t.check(not DB.lingo()["table"].has("看广告 +%d⚡ · 马上开局"), "旧墙主键文案已删")
	t.check(DB.lingo()["table"].has("今天的场次演完了"), "新墙标题在表里")
	t.check(DB.lingo()["table"].has("明天回满 · ⚡ %d/%d"), "新墙副行在表里")
	t.check(DB.lingo()["table"].has("赞助商加一场"), "新墙主键在表里")
	t.check(DB.lingo()["table"].has("看一段广告 · +%d⚡"), "新墙主键小字在表里")
