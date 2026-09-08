# 赞助商 · 商业化提示二版(取代 09-08 的「denied 弹 offer」)· 设计 2026-09-09

> **用户拍板(2026-09-09)**:「我说不出来具体方案,但觉得还有更自然一些的」→ 赞助商方向;
> 「商业化提示的时候 UI 也要好好做,claude design 来做」→ 画布 https://claude.ai/code/artifact/713aeaa4-234a-4ba2-a155-96fbd6dce37e;
> 「画布和续玩的提示很像,整体就是质感不如我们的玻璃板」→ 体力墙改成首页大卡同款玻璃卡;
> 「好了很多,目前我没什么问题了,等你做出来」。广告时长:「15S 或者 30S 都可以」(时长归广告网络,代码不假设秒数)。
> 09-08 规格 [`2026-09-08-ads-design.md`](2026-09-08-ads-design.md) 的 §1(两个判断)、§2 上限、§3 core、§4.1 适配层、§5 Tape、§6 仪器、§8 SDK **全部沿用**;本篇只写换掉的部分。

---

## 0. 一页纸

- **诊断**:09-08 的两个入口都是「墙加钥匙」—— 先撞缺口,再弹一个系统按钮「看广告」。广告在这个世界里没有身份。
- **原则:广告是世界里的一个角色,赞助商。** 这个游戏里凡是能拿的只有卡和碟,赞助商就是一张碟。
- **商店**:货架第三张碟「赞助插播」—— 一条 `price: 0`、`fire: "buy"`、`action: {"ad_coins": 3}` 的消耗牌,**不进随机池**,只在有广告可放、两级上限未到、非教学关时上架为第三位;拿它 = 播一段插播,播完场馆付 3◆;**不占 5 选 1 的名额**。买不起时弹 offer 的那套整块删除(同一件事只留一套机制)。
- **体力墙**:同一个角色。首页大卡同款玻璃卡:眉行「SPONSOR」+ 招牌小图标 · 「今天的场次演完了」· 「明天回满 · ⚡ 0/5」· 金色均衡器带 · 首页「开始游戏」同款霓虹主键「赞助商加一场」+ 小字「看一段广告 · +1⚡」· 一行字「不看了」。机制一行不动。
- **数的家**:3◆ 从 `economy.json ad_coins` 搬进消耗牌的 `action.ad_coins`(卡面上的数就该住在卡上;parity 第四层 card_face 查得到);两级上限仍在 `economy.json`。
- **红线不变**:离线 = 今天的商店(两张碟居中,一像素不差);目标分零广告标定;只有 `reward` 计数;探针缺省无广告。

---

## 1. 数据

| 文件 | 改动 |
|---|---|
| `data/consumables.json` | 新条目 `{"id":"sponsor","cn":"赞助插播","name":"Sponsor Break","price":0,"fire":"buy","fx":"Watch an ad, venue pays 3◆","action":{"ad_coins":3},"shelf":"sponsor","proof":"shop"}` + `_comment_sponsor` 说明「不进池、第三位、不占名额、数住在这里」 |
| `data/economy.json` | 删 `ad_coins`(数搬家);留 `ad_coins_per_shop` / `ad_coins_per_run`,`_comment_ads` 改写 |
| `data/ui.json` | `shop` 节:删 `ad_offer_text` / `ad_offer_text_plain` / `ad_offer_pos` / `_comment_ad_offer`;加 `cons_col_w_3: 150`(三碟时的列宽,间距仍用 `cons_gap`)与 `sponsor_free_text: "免费"`;`consumablecard.sponsor.trigger: "播一段广告,场馆付你 3◆"` |
| `data/lingo.json` | 加:「免费」「插播中…」「今天的场次演完了」「明天回满 · ⚡ %d/%d」「赞助商加一场」「看一段广告 · +%d⚡」「播一段广告,场馆付你 3◆」;删:「差 %d◆ · 看广告 +%d◆」「看广告 +%d◆」「体力不足」「看广告 +%d⚡ · 马上开局」(「不看了」「体力不足,明天回满」「广告暂时没有,稍后再试」保留) |
| `data/sim.json` | 不动(ads 臂仍按需临时加 cohort) |

`core/db.gd` 校验:
- `validate_consumables`:允许键加 `shelf`(值只能是 `"sponsor"`);`price` 允许为 0 **仅当** `shelf == "sponsor"`;`_CONSUMABLE_ACTIONS` 加 `ad_coins`(值 ≥ 1);全表**恰好一条** `shelf: sponsor`,且它必须 `fire: "buy"`、`action` 只含 `ad_coins`。
- `validate_economy`:`_ECO_KEYS` 去 `ad_coins`;上限两键 ≥ 0 且 `per_shop ≤ per_run` 照旧。
- `validate_sim` 不动(消耗牌本就不进 `ev.cards` 那条检查)。

## 2. core

- `core/consumable.gd`:`is_sponsor() -> bool`(`_raw.shelf == "sponsor"`);`roll_shelf` 跳过 `shelf == "sponsor"` 的条目(它不是随机货);`static func sponsor_entry() -> Dictionary`(找那一条,找不到返回 `{}`)。
- `core/economy.gd`:`ad_coins()` 改读 `Consumable.sponsor_entry().action.ad_coins`(缺 = 0);`ad_coins_allowed(run_used, shop_used, coins, slots)` 不变。
- `core/config.gd`:删 `AD_COINS`(保留 `AD_COINS_PER_SHOP` / `AD_COINS_PER_RUN`)。
- Lua 孪生同步(consumable.lua / economy.lua / config.lua);`tools/golden.gd` 重生成金样(消耗牌族含 `roll_shelf`),`lua lua/check.lua` 绿。

## 3. view · 商店

- `Widgets.ConsumableSlot`:`sponsor := false`、`playing := false`。`_draw`:sponsor ⇒ accent 用 `StageTheme.CYAN`,中心不画插画,画霓虹招牌(60×42 圆角 7 描边 2 + 两根吊线 + 播放三角),右下刻印圆里写 `AD`;playing ⇒ 整体压到 0.34 + 一段 270° 亮弧(2.5px)+ 中心画暂停双杠(不转,静态)。
- `view/shop.gd`:碟位建 **3** 个;`set_consumables(offer, coins, effective)` 按 `offer.size()`(2 或 3)排列:2 张走今天的 `cons_col_w`/起点 239,3 张走 `cons_col_w_3`/起点 `lx + ((rx−lx) − (3·cw3 + 2·cg))/2 = 192`;第三位若为 sponsor:`accent = CYAN`、`sponsor = true`、价签 `"%s ◆ +%d" % [Lingo.t(ui.shop.sponsor_free_text), Economy.ad_coins()]`、`armed = true`(价格 0 与金币无关);名字/描述照常走 `display_name()` 与 `consumablecard`。新入口 `set_sponsor_playing(on: bool)`。**删掉** `_ad_btn` / `show_ad_offer` / `hide_ad_offer` / `ad_offer_visible` / `ad_requested`;`denied` 回到 `denied(why: String)`(缺口参数随 offer 一起退役)。
- `view/phrase.gd`:
  - `_coffer` = `_roll_consumables()`(2 张)+ 第三位:`ad_offer_ok(ads.has_ad("coins"), run.tutorial, run.ad_used, _shop_ads, phrase.coins, run.joker_slots) and not _shop_ad_failed` ⇒ `Consumable.new(Consumable.sponsor_entry())`,否则不append(offer 长度 2)。进店算一次,`_refresh_shop_consumables()` 时重算第三位(Android 的 `has_ad` 是异步变真的)。
  - `_on_consumable_bought(c, price)`:`c.is_sponsor()` ⇒ 不扣钱、不 `take`、不计 `_shop_buys`;若 `_coins_ad_showing` 直接返回;`Tape.on("ad", {"k":"coins","ev":"show"})`;`shop.set_sponsor_playing(true)`;`_coins_ad_showing = true`;`ads.show_ad("coins")`;返回。
  - `_apply_shop_action` 加一支:`if act.has("ad_coins"): phrase.coins = Economy.grant(phrase.coins, int(act["ad_coins"]), run.joker_slots); run.coins = phrase.coins`。
  - `_on_ad_rewarded("coins")`:`store` ⇒ 发钱那一刻再守一次 `ad_coins_allowed`(不许 ⇒ Tape drop)⇒ `_apply_consumable({"id":"sponsor","action":{"ad_coins":N}}, "ad")`(走共用口,Tape 会记 `consumable why=ad`)⇒ `_shop_ads += 1; run.ad_used += 1` ⇒ 第三位置 null(碟像卖出的商品离架)⇒ `_refresh_shop_consumables(); shop.refresh_coins(phrase.coins)` ⇒ `Tape.on("ad", reward)`;`late` ⇒ 只发钱 + Tape late;`drop` 照旧。
  - `_on_ad_failed("coins")`:`shop.set_sponsor_playing(false)`;`_shop_ad_failed = true`;第三位置 null + 刷新;浮字「广告暂时没有,稍后再试」。
  - `_on_ad_closed("coins")`:`_coins_ad_showing = false`;若这次没发奖 ⇒ `shop.set_sponsor_playing(false)`(碟回到在场)。
  - **删掉** `_on_shop_denied` 里的 offer 判定(只留 `Tape.on("deny")`)、`_on_shop_ad_requested`;`ad_offer_ok` / `ad_reward_case` 保留。
- 探针:`tools/adsprobe.gd` 流 A 改成点第三张碟(`shop._on_cshelf_pressed(2)`),断言:发奖后金币 +3、`run.ad_used` 计数、第三位离架、同店不再上架、第三店不上架;流 B 不变。

## 4. view · 体力墙(玻璃卡)

`_open_energy_wall()` 重画,尺寸照画布:卡 480×384 @ (120, 430),暗幕 `rgba(0,0,5,.74)` 不变。
- 卡体:`Widgets.StageCard.draw_card(ci, rect, StageTheme.GOLD, 18.0, 34.0, true)`(玻璃壳素材整图拉伸 + 烘焙倒影,与首页大卡同一分支);卡外 `drop-shadow` 用 `StageTheme.box` 的辉光参数 26px 金。
- 内容(自上而下,与画布同尺寸):眉行 = `Widgets.SponsorSign`(新小件,22px,描边 1.4 金)+「S P O N S O R」(Rajdhani 13 金 .85)· 标题「今天的场次演完了」zh 26 · 副行「明天回满 · ⚡ %d/%d」14 dim(读 `SaveState.energy()/energy_max()`)· 均衡器带 `Widgets.StageCard.eq_band(ci, Rect2(…380×44), GOLD, t, 0, 34)`(动效层,与首页同一支笔)· 主键 = 首页开始键同款(`StageTheme.box` 暗金底 + 金边 2 + 辉光 18 + 顶白线 + `Chrome.neon(zh, "赞助商加一场", 26, 白, GOLD)` + 小字「看一段广告 · +%d⚡」14)· 「不看了」一行字(14,dim,可点,不做框)。
- 主键与「不看了」仍是 `Button`(探针按第一枚)。行为(墙的开关、`_pending_start`、看门狗、点空白关闭)**一行不动**。
- `Widgets.SponsorSign`:同一枚招牌给碟中心与眉行共用(碟里由 `ConsumableSlot._draw` 直接画同款几何,不挂子节点)。

## 5. 仪器与门

- `tools/bot.gd`:ads 上界臂不变(语义 = 每店都拿赞助碟);`_apply_bot_action` 加 `ad_coins` 分支(`_pending_borrow += int(act["ad_coins"])`,与 loan 同一形状,注释写明:正常路径不经这里,只为 parity 第二层与 kit 钉卡)。
- `tools/parity.py`:ENTRIES 的 `ad_coins` 保留;第二层 `action_keys` 自动把 `ad_coins` 纳入两侧检查;第四层 `card_face` 读 `consumablecard.sponsor.trigger` 里的 3 与 `action.ad_coins` 对上。
- 秒级六门 + `t_db/t_consumable/t_economy/t_shop/t_ads/t_lingo` + adsprobe;收尾跑一次全量单测。

## 6. 不做 / 认下

- 不做:赞助碟进图鉴(图鉴无消耗牌页)· 赞助碟被帕奇欧复制(它买下即结束,不进队列,自然不会)· 赞助碟被联票名额影响(不占名额)· 广告时长假设。
- 认下:赞助碟每店可见,免费 3◆ 会被多数人每次都拿 ⇒ 实际经济向 +6◆/局漂;上限锁两次,数在 JSON;`income_ad` 与真人 Tape 的拿取率盯着。
