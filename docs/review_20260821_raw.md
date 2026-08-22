# 全面评审 · 八份原始报告(2026-08-21,只读评审员交付原文,汇总见 review_20260821.md)

---

# 切片:core-a

## 评审结果 · core/ 骨架切片(配置/存档/导演/经济/打点)

评审标准 = CLAUDE.md 铁律 + LESSONS.md 判据。只读、未改任何文件、未运行任何探针。

---

### 🔴 1. `core/run.gd:45-68` · 「再来一次」整条路径绕过 `min_run` 解锁门、Director 永远是第 1 局状态、且用上一局的 ctx · 置信度 **高**

```gdscript
func reset(face_seed: int = -1) -> void:
    ...
    roll_faces(face_seed)   # run_index 缺省 -1, face_ranking / director_ctx 是没清的实例字段
```
`view/phrase.gd:888` 重试路径只调 `_reset_run(true)` → `run.reset()`,之后**不再** `_feed_director()` + `roll_faces(-1, idx)`。后果:`run_index=-1` ⇒ `unlocked_at` 恒 true ⇒ 禁回(`min_run: 10`)第 2 局重试就能出现(正是 `director.gd:256` 注释点名的形状);`Director.index_for(-1)` → 下标 0 ⇒ 重试永远 `establish`;`face_ranking`/`director_ctx` 实例字段不清 ⇒ 用上一局开局时的 streak/seen/returning(`run.gd:76-78` 注释「不是实例字段…而不是静默用上一局的值」对 ctx 不成立);不走 `note_run_started()` ⇒ `runs_total` 与 `history` 长度分叉。
**修法**:`reset()` 清空两个字段并透传 `run_index`;view 重试路径补 `_feed_director()` + `note_run_started()`。

### 🟠 2. `core/db.gd:883-953` · 小丑牌 `rarity` 值不校验 · 置信度 **高**

只把 `rarity` 当合法键名;消费端 `economy.gd:27` `.get(j.rarity, 4)`、`:88` `.get(j.rarity, 1)` 吞默认值。拼错 = 普通价 + 权重 1 + Director 乘数退 1.0,三处全静默。`validate_director:733` 对 `rarity_weight_mult` 键已做交叉校验,卡本身没做;`t_run.gd:64` 只断言非空。
**修法**:断言 `rarity ∈ economy().draft_rarity_weights.keys()`,并断言 `joker_prices` 与 `draft_rarity_weights` 键集相等。

### 🟠 3. `core/db.gd:956-966` · 主角 `effects` DSL 完全不过白名单 · 置信度 **高**

`validate_characters` 只查顶层键;8 个主角的 `effects` 用同一套 `when`/`do`,但 `_PREDICATES`/`_DO_KEYS`/`_PER_SOURCES` 只在 `validate_jokers` 查。`Fx._when_ok` 未知谓词 = `push_error` + `return false`(`fx.gd:153-155`),运行期才响、测试期 `load_error()` 仍为空。
**修法**:抽 `_validate_effects(e, id)`,jokers/characters 共用。

### 🟠 4. `core/director.gd:218` · 回归局「熟脸」被无关开关 `novelty` 静默吞掉 · 置信度 **高**

`if not seen.is_empty() and novelty_on():` 包住了 `familiar` 分支。关 `novelty` 后 `returning` 仍 true,但只剩 mild、熟脸消失。
**修法**:`and (novelty_on() or familiar)`。

### 🟠 5. `core/db.gd:254,269` · `validate_ranking` 段数手写 `["0","1","2","3"]` · 置信度 **高**

`validate_run` 从 `sections_per_gig × gigs_per_run` 推 n,这里写死 4 —— 「按段索引的表」用字面量定长,08-18 新加、不在 CLAUDE.md 那条清单上。
**修法**:从 `run()` 推 n 后 `range(n)`。

### 🟠 6. `core/save.gd:295` · `core/director.gd:135-137` · `core/save.gd:351` · 三个平衡旋钮写死在 core · 置信度 **高**

`RETURN_GAP_S := 3 * 86400`(注释自认口味值)、`streak <= -2`/`>= 3`(`director.json` 的 `_context` 注释把它们当事实描述,数却在 .gd)、战绩环长 `20`。铁律「数值全部在 data/*.json」,用户习惯手改 JSON 调参。
**修法**:进 `director.json` `context` 节,白名单放开为带类型表。

### 🟠 7. `core/asset.gd:88-91` + `view/honors.gd:80,347` · `can_buy` 不查 `on_shelf`,view 矩形与 roster 下标错位 · 置信度 **高**(跨切片)

`honors.gd:347` 下架资产 `continue` 在 `_asset_rects.append` 之前,点击却 `Asset.roster()[i]` 按矩形下标取 id ⇒ 任一资产设 `season` 后**点 A 买到 B**;`can_buy` 是唯一读取点守卫而它放过下架品。目前 `season` 全空,埋雷。
**修法**:`can_buy` 加 `on_shelf(id)`;view 侧 rect 与 id 成对存。

### 🟠 8. `core/db.gd:190` · `FileAccess.file_exists("res://…wav")` 导出包假红 · 置信度 **中**

Godot 导出不打包被导入资源的源文件,APK 里返回 false(文档建议 `ResourceLoader.exists`)。真机每次启动 `validate_assets` 失败 → `[DB]` ERROR,`load_error()` 永远非空,门的信号被污染。
**修法**:`ResourceLoader.exists(path)`。

### 🟡 9. `core/beat.gd:43` · `begin()` 是状态机唯一没 `_expect` 的转移 · 置信度 **中**

连调两次发两次牌、`phrase_index += 2`、第一拍无声蒸发;文件头「漏步直接拒绝执行」对它不成立。建议 `_expect(run, ENDED 或首拍)`。

### 🟡 10. `core/config.gd:8,20,22` · 本地化后的 `run.json` 被静态快照,切语言不跟 · 置信度 **高**

`_run = DB.run()` 类加载时拿 en 深拷贝;`set_lang()` 的 `Lingo.force("")` 清不到 `GIG_NAMES`/`BLIND_NAMES`。设置页一接就显。建议 `gig_name()` 每次走 `DB.run()`。

### 🟡 11. 过期注释(「注释承诺了不存在的机制」族)· 置信度 **高**

`save.gd:4`「只存一件事」(现 ~15 键)· `economy.gd:4-6` 弃牌收费/skip reward(均已推翻)· `run.gd:86`「必须先设 tutorial」(同文件 104-108 已作废)· `db.gd:604-609`「不用读 context」与 `:668`「恰好两个布尔开关」(现四个)· `db.gd:194` 文案缺 `homejuke` · `tape.gd:32-55` 事件表缺 `lock`/`ticket`/`tutorial_done`/`upgrade`,`uplink.gd:5`「21 类」同样过期(probbook.py 的读表契约)· `economy.gd:68` reroll doc 挂错函数。

### 🟡 12. `core/db.gd:40,378` · `upload` 是必备键,`if d.has("upload")` 死分支 · 置信度 **高**

`_keys_ok` 把 allowed 同时当 required(`:315-317`);注释说「可选节」与实际不符。先 erase 再对白名单,或删 `has`。

### 🟡 13. `core/db.gd:115-137` · 券 `params` 不校验 `mult_min`/`mult_max` 成对 · 置信度 **高**

只写一个 = 静默变成不掷值的券;顺带 `assets.ticket` 出口依赖 `tickets.enabled`,无交叉校验,关总闸后券类资产静默变纯装饰(`:195` 自己禁的那种)。

---

### 总结

架构纪律本身守得很好:core 无时钟、不 import view、判生死/一拍转移/货架抽卡各只一份,探针闸在 SaveState 二十余入口逐个挡住。真正会咬人的只有 **#1 重试路径让 `reset()` 用缺省 `run_index` 和没清的 ctx 重掷**,一条击穿 min_run、Director 序列、ctx 且不报错;**#2/#3 是 validator 两个真空洞**,都是「拼错就静默退默认值」的形状。
最该先修:#1(`reset()` 清字段 + view 补喂 + `note_run_started`),然后 #2+#3 收成共用 `_validate_effects` + rarity 交叉校验 —— 改动都小,且各能在 `t_db`/`t_director` 锁一条反向断言。
---

# 切片:core-b

## Sync5 core/ 规则与计分切片评审

评审依据:CLAUDE.md(架构铁律 / 结算公式 / 三条契约 / Target 两层原则)+ LESSONS.md(「注释承诺不存在的机制」「规则在游戏里不在模型里」「守卫自己要 A/B」)+ jokers.md 设计原则 A1–D3 + cards.md 结算节。全部条目都读到代码确认,未跑任何探针。

---

**1. `core/fx.gd:193-258` · 🔴 · 置信度高 · 六个逃生口操作码全部无视 `scale`,8 张卡的「升级」是纯扣钱**
`_do()` 里 `mult_from_target_factor` / `additive_face_value` / `additive_low_value` / `coins_factor` / `additive_cache_top` / `chips_per_card` 全在 `return` 之后才到 278 行的 `if scale != 1.0` 放大段。而 `Joker.can_upgrade()`(`joker.gd:48-49`)只排除规则牌,所以 **vip / mirror / bassclef / warmtone / cooltone / undertone / bench / royalty** 在商店里都挂升级报价(`view/shop.gd:260-278`),`view/phrase.gd:1039-1040` 照扣 4/7/11/16◆ 并 `level += 1`,结算时一分不涨;`tools/bot.gd:532` 也会去升它们(模型与游戏一致地错)。这正是 `joker.gd:249-252`「放大只发生在 apply 一处,谁调 apply 谁自动拿到」那句**注释承诺了不存在的机制**(LESSONS 第 4 次的形状),且升级是「金币主出口」的设计根基。
修法:加分类操作码把 `boost *= scale`(取整),`mult_from_target_factor` 走 `1 + (mf−1)×scale`,`coins_factor` 与 `coins` 同理不放大并让 `can_upgrade()` 对「没有可放大通道」的卡返回 false;补一条 A/B 测试:遍历所有 `can_upgrade()` 为真的卡,断言满级 `apply` 的 ctx 与 Lv1 **不同**。

**2. `core/joker.gd:277-283` · 🟠 · 置信度高 · `clone()` 不拷 `level`**
`clone()` 只深拷 `state`,`level` 回到 1。`tools/runloop.gd:218` 的 `RunLoop.fork` 和 `tools/draft.gd:91` 全走它,于是求解器/bot 的「买不买 / 换不换」推演把已升级的在役卡当 Lv1 算:替换一张满级卡看起来比实际便宜,前推总分系统性偏低。与 `joker.gd:32-34`「漏了它就是第 7 次规则在游戏里不在模型里」的自述直接矛盾。
修法:`j.level = level`;测试:Lv3 卡 `clone()` 后对同一 ctx 的 `apply` 结果逐字节相同。

**3. `core/phrase.gd:142-159, 319-323` · 🟠 · 置信度中 · doubleseal 的「最旧缓存锁」只锁换、不锁弃,一次免费弃牌就解锁**
`swap_with_cache` 245 行挡 `sealed_cache_card`,但 `can_discard_selected` 对 cache 索引只比 `sealed_hand_card`(157 行),`discard_blocked_cache()` 同样不含它。弃牌免费 ⇒ 玩家点一下就把封印牌弃掉换新,此后整拍封印对象已不在缓存,约束归零。`blinds.md:106` 写的是「禁换」,但卡面 `"Lowest hand and oldest cache lock"` 用的是 lock,违反「规则要自解释」;`t_phrase.gd:277-280` 只锁了换。
修法:拍板二选一 —— 要么 `can_discard_selected`/`discard_blocked_cache` 一并加 `sealed_cache_card`(求解器消费同一个 blocked 集,不会分叉),要么把 fx 改成 "...oldest cache can't swap"。

**4. `core/fx.gd:318-321` · 🟡 · 置信度中 · `bonus_target_pct` 的尺度基准继承了脸的加税**
`section_target` 来自 `beat.gd:101` 的 `run.target()`,它已乘 `variety_mult`(trilogy 段首 ×1.75,覆盖一种降一档)和 `target_mult`(raisedbar ×1.5)。于是 12 张跟随尺度的加分卡在 trilogy 段首多付 75%、随覆盖种数逐拍缩水;一张脸的惩罚变成小丑牌的红利。「数额跟随本段每拍目标」的本意是跟基准曲线。
修法:ctx 另传未加税的 `Run.section_target_for(table, sec, "")` 做 bonus 基准;若就是要跟加税走,把这条写进 numbers.md。

**5. `core/settle.gd:21-29` · 🟡 · 置信度高 · 文件头与实现脱节**
头注释说「四个计分侧扭曲:unplugged / static / norepeat / rotation」—— `faces.json` 里 unplugged、static 已无 tier(退役),而函数实际还做了 setlist(131-134)、request(135-137)、patchin 聚合半效(94-105),一个没提。27-29 行称返回的 `base × mult = score` 恒真,但 119-137 行的四个脸系数都在 `score` 定稿**之后**乘,返回的 `base/mult` 重建不出 `score`。LESSONS 的判据:「注释里出现必须/一定会,当场验证」。
修法:重写头注释;或把脸系数并进返回的 `mult`。

**6. `core/settle.gd:94-105` · 🟡 · 置信度高 · 「½ 」前缀写死,且贴到没被半效的金币弹窗上**
`joker_power` 是数据参数(现值 0.5),标签却硬编码 `"½ "`;而 `coins_bonus` 不在 94-103 行的缩放里,金币卡的 `+N◆` 弹窗也被冠以 ½。
修法:按 `patch_power` 生成标签;coins 通道要么也缩要么跳过前缀。

**7. `core/fx.gd:263-268` + `core/db.gd:929-937` · 🟡 · 置信度高 · DSL 两处静默坑没被校验锁住**
`_do` 的通道循环在第一个命中通道就 `return`,一条 `do` 写两个通道(如 `bonus`+`coins`)后者静默丢失;`per: "counter:X"` 与 `counter_gte: ["X", n]` 的 X 不校验是否在该卡 `counters` 里,拼错 = 恒 0 = 卡静默失效。今天 63 张卡数据都干净(逐条查过),是潜伏坑,但形状就是 `db.gd:853` 自己说的「静默不涨」。
修法:`validate_jokers` 加「通道键恰好一个」与「counter 名 ∈ counters」两条。

**8. `core/pattern.gd:386-389, 441` · 🟡 · 置信度高 · 规则牌路径下「皇家」判据与快路径不同**
快路径要求 bit 10..14 全在(316 行);参考路径只看 `ranks[0]==10 and ranks[4]==14`。开四指后 10♠J♠Q♠K♠A♥(四张同花 + 五张顺)读成 ROYAL_FLUSH(140 chips);四指 + 近道下 [10,J,Q,A,A] 同花也是皇家。对玩家有利、罕见,且模型与游戏同函数不分叉,但「皇家」在两条路径上是两个定义。另 441 行注释「n<=7 → 最多 21 组合」已过期(8 选 5 = 56)。
修法:皇家 = 同花顺且 distinct ranks ⊇ {10..14};加边角用例锁住。

**9. `core/tutorial.gd:29-34, 42-43` · 🟡 · 置信度高 · 「动作门」注释夸大,实际不存在死锁**
`run.gd:221` `STEP_MAX_BEATS := 1`,`tutorial_try_advance` 每拍末必推进;`require` 现在只管拍中提示提前换。因此 42-43 行「写错一个动作名那一步永远推进不了」已不成立(白名单 `db.gd:568` 仍在,是好事),头注释「没做就停在这一步」也不是事实。`unlocked()` 整套机制在 `tutorial.json` 里已声明作废,代码还当 API 留着。**按题 6 的镜头查过:没有能卡住推进的路径。**
修法:改注释为「软门 + 1 拍兜底」;考虑删 unlock 管线。

**10. `core/joker.gd:8-14` · 🟡 · 置信度高 · 钩子契约清单漏了第七个钩子**
头注释列六个钩子并称「unchanged」,而 223-237 行已有 `on_shop_event` / `notify_shop`(08-13 加)。`jokers.md` D1 同样没列。
修法:两处补上,并写明 D1 开口的理由已在 `Fx.on_shop_event` 注释。

**11. `core/blind_boon.gd:69-70` + `core/phrase.gd:111-112` · 🟡 · 置信度高 · `spotlight_cards` 是计数,实现只认 >0**
`start()` 里 `if spotlight_cards(boon) > 0: spotlight_card = deck.draw()` 恒抽一张,写 2 也还是 1。
修法:按 N 抽,或把参数改成 bool 并在 `_BOON_PARAMS` 注明。

**12. `core/phrase.gd:215-227` × `data/jokers.json` lonewolf / tipjar · 🟡 · 置信度中 · 补牌券绕过「零弃牌」条件**
`redeal_hand()` 刻意不计 `discards_used`(防券白喂成长卡,正确),但反面是 `discards_eq: 0` 的卡(独狼 +3◆、小费罐 +2◆)在整手重发后仍判零弃牌。券是局外资源、数量有限,所以是有界漏洞;但「券不进模型」意味着这条路径探针永远量不到。
修法:要么 redeal 置一个 `hand_changed` 标志让 `discards_eq 0` 读它,要么在 tickets 文档里明写这是有意的甜头。

**13. `docs/design/cards.md:54-64` · 🟡 · 置信度高 · 结算顺序文档与代码/CLAUDE.md 不一致**
cards.md 列「5 主角 → 6 Target → 7 Support」,`settle.gd:73-111` 与 CLAUDE.md 是「牌型 → Target → Support → 主角」。另 jokers.md A4「成长必须花钱(coins)」与弃牌免费后 vinyl/bassline 吃免费弃牌的现状冲突(cards.md ③ 已承认),A4 文本未同步。
修法:改 cards.md 顺序;A4 改成「有代价(时间或金币)或每拍天然一次」。

**14. 镜头 4(判生死唯一真相)· ✅ 无第二份 · 置信度高**
`Run.target()` = `section_target_for × variety_mult` 一处;`beat.gd:101` 的 ctx、`view/phrase.gd:952` 的商店板都消费 `run.target()`;`view/shop.gd:163` 的自算分支因调用方恒传 target 而不可达。唯一残余:`tools/runloop.gd:142-144` 用两个原语**重新拼**了一次乘积而不是调一个共享的 `target_for(table,…)`,将来给 `target()` 加第三个因子时这里会静默漏乘 —— 建议抽成 `Run.target_for(table, section, mod, kinds)` 让两边都调。

**15. 镜头 1/2 其余复核 · ✅**
`bonus_pct`(乘区)与 `bonus_target_pct`(落 `ctx.bonus`,乘法链后)两通道在 `fx.gd:301-338` 严格分开,`settle.gd:112-116` 合并顺序与公式一致;`target_factor` 只在 slot 0 采样、镜面读的是半效后的值;`same_as_prev`/`diff_from_prev` 在首拍(-99)都为假,无白拿;`on_phrase_end` 每拍一次、`on_discard` 只在成功弃牌的共同出口(`view/phrase.gd:1339`、`bot.gd:619`)触发,券路径已隔离;`modifier.gd` 的 `_param` 缺键退默认被 `db.gd:454-456` 的参数白名单兜住,`tiers`/`pool_for(section_idx+1)`/`tier_is_fixed(int())` 索引与 float 比较都对。

---

**整体健康度**:计分主链(牌型 → Target → Support → 主角,两条加分通道)与判生死单一真相落实得扎实,脸参数与 DSL 键都有测试期白名单;问题集中在**升级系统接入不完整**和**注释/文档追不上实现**这两类「不报错只是数悄悄偏」的形状。
**最该先修**:① 第 1 条(8 张卡升级等于白扣钱,且 bot 也在犯,A/B 测试一并补);② 第 2 条(`clone()` 丢 `level`,一行修复,解掉求解器对升级卡的系统性低估)。
---

# 切片:view-a

评审完成。以下按严重度排序,每条都已读到代码并核对过调用链。

---

**1. 🔴 `view/phrase.gd:786-797` · 置信度 高 · 教学商店里花真金买的牌在 `tutorial_done` 被整排没收**
`_advance()` 在 `run.tutorial and run.tutorial_done() and section_done` 时 `for i in range(run.joker_slots.size()): run.joker_slots[i] = null`,无条件清四槽。但教学段第 3 拍末 `shop_break` 会开一次真商店(`_open_draft` 只关了升级栏 `set_upgrades_on(false)`,买/替换全开),此时四槽已装满借展样品(`_stage_tutor_props`, step≥2)⇒ 任何 Support 购买都走 `replace_requested` → `_on_slot_tapped`:玩家付 `price`、拿到样品的 `sell_value` 退款、装上新卡;第 6 拍末**新卡连样品一起被删**,退款却留在钱包。连带:`new_j.on_acquire(run.deck)` 写下的 `enable_wilds / deck.rules / trim_low_ranks` 不会回滚——卡没了、规则还在。注释只防到「免费四张带进正式局」,没防「玩家在这个商店里花了钱」。`tests/t_tutorial.gd` 没有一条覆盖教学商店。
建议:没收时只清 `_stage_tutor_props` 装进去的那四个 id(记一份 `_tutor_sample_ids`),或教学段商店直接 `skipped`/只读;至少补一条 t_tutorial 断言「教学商店买的卡带进正式局」。

**2. 🔴 `view/phrase.gd:883-898` · 置信度 高 · 「再来一次」绕过了 Director/解锁门/局数计数**
`_on_end_retry` → `_reset_run(true)` → `run.reset()` → `roll_faces(face_seed)`,**`run_index` 走缺省 −1**;而 `choose_character` 那条路在 reset 之后还会 `_feed_director()` + `run.roll_faces(-1, _run_index)` + `SaveState.note_run_started()`,重开路径三样全没有。后果(已对到 core):`SectionMod.unlocked_at(id, -1)` 恒 true ⇒ `min_run` 门形同虚设(`core/director.gd:256` 的注释原话「禁回会在第 1 局重新冒出来, 而且不报错」描述的正是这条);`Director.face_bias(-1)` → `index_for` 落到第 1 局状态;`director_ctx` 是上一局开局的快照(刚写进 history 的这场败绩不在 streak 里);`_run_index` 不变 ⇒ `Director.shelf_rarity_mult(_run_index)` 用旧局号;`runs_total`/`last_seen` 不推进,`_session_runs` 不加。另外这里的 `Tape.begin` 少了 `sess`/`tutorial` 两个键,与主路径口径不一致。
建议:把「定身份之后的开局三步」(`_feed_director` → `_run_index` → `roll_faces(-1, _run_index)` → `note_run_started`)抽成 `_begin_run()`,两条路共用;并让 `Run.reset()` 不再内部掷脸或要求显式 `run_index`。

**3. 🟠 `view/shop.gd:103-127` + `:270` · 置信度 高 · 每次渲染都新建一对刷新/继续按钮,旧的不删**
08-13 把卡位摆放抽成 `_layout()` 时,原本只在 `_ready` 跑一次的按钮创建块被一并卷进了函数尾部;而 `_render()` 每次都调 `_layout(maxi(3, _candidates.size()))` ⇒ 开店、`redeal`、`sold`、升级回渲染各 +2 个 Button 叠在同一矩形,老的仍连着 `_on_reroll/_on_skip`。功能上新按钮在最上所以能用,但这是节点泄漏(一局几十个),且 0.9 alpha 的底板会透出下层旧价签(「刷新 · 3 ◆」压在「刷新 · 4 ◆」下)。
建议:按钮创建搬回 `_ready`,`_layout` 只改 position。

**4. 🟠 `view/shop.gd:257-264` · 置信度 高 · 升级商品位会覆盖「必定出 Target / 规则牌」的保底位**
保底补丁把 Target 钉在 `_candidates[last]`、规则牌钉在 `_candidates[0]`(224-249),随后升级上架用 `randi_range(0, size-1)` 随机选一位覆写——1/3(联票时 1/4)概率正好吃掉保底。独狼(`target_guaranteed`)/点唱机(`rule_guaranteed`)卡面承诺因此随机失效,违反「卡面不许说谎」。
建议:升级位只从未被保底占用的下标里选,或先放升级再做保底补丁。

**5. 🟠 `view/shop.gd:380-392` · 置信度 高 · 探索型货架让 shop 直接读存档,破了它自己的注入制**
新加的 boost 在组件内调 `SaveState.targets_used()` / `SaveState.is_probe()` / `Director.explore_on()`。同文件 32-37 行明写「shop 自己不读存档」「编排器开店时注入(探针一律 {} = 中性)」,`_free_rerolls`、`_rarity_mult`、`_upgrades_on` 全按这条做。现在「探针中性」的判断在编排器和组件各有一份,截图探针也无法注入 boost 来目视。
建议:编排器在 `_open_draft` 算好 `boost` 字典,走 `set_shelf_rarity_mult` 同款 setter 注入。

**6. 🟠 `view/phrase.gd:17,624,712-722` + `data/ui.json:345` + `view/settle_fx.gd:85-87` · 置信度 高(机制)/中(是否有意)· 分数滚动演出是死代码**
`resolve_hold = 1.0`,但 `burst_started` 在 settle_fx 的 `_t >= 1.50` 才发。1.0s 时 `_advance` → `_start_phrase` → `_refresh()`(`state != RESOLVE` ⇒ `_shown_score = run.section_score`)把 HUD 直接写成终值;1.5s `_on_settle_burst` 进来 `from == to` 立刻 return——「碎片飞到哪分数涨到哪」永远不会发生,碎片飞向一个已经写好的数字;同时分解面板还要在下一拍的前 1.45s 继续压在新手牌上(商店那条已被 `dismiss()` 处理,出牌这条没有)。
建议:要么 `resolve_hold` ≥ 1.5,要么 `_shown_score` 的推进只由 burst 驱动、`_start_phrase` 不抢先写。

**7. 🟡 `view/phrase.gd:134-135,305-306` + `view/beacon.gd:14,31` · 置信度 高 · `FIRST_SCAN_DELAY` 被 `_ready` 里的 `poke()` 架空**
`add_child(beacon)` 在树内同步跑完 `Beacon._ready`(`_req` 已建),紧接着 `_open_home()` 就 `beacon.poke()` ⇒ 开机立刻扫描上传,5 秒后定时器再 poke 一次。目前 `upload.enabled=false` 所以在睡,1.1 打开就生效。
建议:`_open_home` 里的 poke 只在 `state != FRONT` 来时调(即从结算屏回来),或 Beacon 自己用 `_booted` 闩住首扫。

**8. 🟡 `view/intro.gd` 全文 + `view/phrase.gd:79,301,331,424-429` · 置信度 高 · `BlindIntro` 已退役但还在树上、信号还连着**
08-18 特写接任后 `intro.open()` 零调用,`_on_intro_done` 与 `intro.skipped` 永不触发;`BlindIntro` 是 720×1280 默认 STOP 的全屏控件(仅靠 `visible=false` 不挡事),是一颗「谁一 `visible=true` 就盖住全场」的闲置雷。
建议:与「关开关不删代码」先例对齐的话至少把 `mouse_filter = IGNORE`、删掉 `_on_intro_done`;否则整块下架。

**9. 🟡 `view/blind_banner.gd:9-11,57-59`、`view/phrase.gd:392-400,1103` · 置信度 高 · 坐标/时长硬编码,`ui.json` 没有 `banner` 节**
`docs/design/tech.md` 写着 `banner: {w,h,show_y,done_text,wage_text}`,`core/db.gd:1017` 白名单也放行 `banner`,但 `data/ui.json` 根本没这一节,代码用 `const W/H/SHOW_Y` + `Lingo.t`。特写的 `Vector2(360,600)`、`z_index 210`、`2.4` 倍、`0.5/1.1/0.4` 秒,以及券提示兜底 `Vector2(500,600)` 同样写死。
建议:补 `ui.json` 的 `banner` 与 `closeup` 两节,文档与实现对齐。

**10. 🟡 `data/ui.json` shop 节 `upgrade_y/w/gap/text/maxed/locked/empty/h` · 置信度 高 · 8 个死键**
底部升级行 08-18 撤掉后,`core/ view/ tools/ tests/` 零引用;`DB.validate_ui` 只查「未知节」不查「未读键」,所以不会红。
建议:删键;或给 `t_lingo` 那套源码扫描加一条「ui.json 叶子键必须被某个 .gd 引用」。

**11. 🟡 注释与代码不符(LESSONS 第 4 次升格的检查项)· 置信度 高**
`view/phrase.gd:4`「弃牌 (1 coin each)」vs 08-06 拍板弃牌免费;`view/shop.gd:12`「orchestrator pays the skip reward」vs 08-06 删掉奖励;`view/phrase.gd:1388,1390-1391`「not enough coins」与 deny 原因 `"coins"` 不可达;`_refresh()` 的 `"fee": total_sel * DISCARD_COST` 恒 0,`hand.gd:466 discard_key.fee` 是弃牌免费前的遗物;`view/hand.gd:62-71` 同一段注释先说「PASS 不吞点击」再说「上面那句是错的」。
建议:一次清掉,别让下一个人按旧注释改代码。

**12. 🟡 `view/phrase.gd:1175` vs `view/shop.gd:413,456` · 置信度 高 · 「◆ 不足」两份来源**
替换流用 `Lingo.t("◆ 不足")`,商店用 `_cfg["insufficient"]`(值也是「◆ 不足」)。改一处另一处不跟。
建议:统一读 `DB.ui()["shop"]["insufficient"]`。

**13. 🟡 `view/phrase.gd:1486` · 置信度 中 · 教学关 `fraction = 0/0 = NaN`**
教学段 `run.target()` 恒 0,开局 `section_score` 也是 0 ⇒ `float(0)/float(0)` 得 NaN(GDScript 浮点除零不报错);`clampf(NaN,0,1)` 仍是 NaN,`GradBar._draw` 里 `maxf(size.x*NaN, 10)` 退成 10px 残条、颜色 lerp 成 NaN。Hud 对 `target == 0` 已特判隐藏「/ 0」,但进度条没有。
建议:`"fraction": 0.0 if target <= 0 else …`。

**14. 🟡 `view/phrase.gd:463 vs 490,1122` · 置信度 高 · 特写 2 秒内券托盘可见但点了没反应**
`_refresh_tray()` 在 `state=DECISION` 时先把托盘亮出来,随后 `_play_blind_closeup()` 切到 INTRO,`_on_ticket_use` 见 `state != DECISION` 静默 return。与 1270 行自己写的「锁定后的操作不许静默吞掉」同一类。
建议:`_play_blind_closeup` 里 `tray.visible=false`,`_closeup_done` 再 `_refresh_tray()`。

**15. 🟡 `view/phrase.gd:967-972` vs `:1025-1026` · 置信度 高 · 买入路径信任信号带的价,升级路径不信任**
`_on_shop_upgrade` 明写「信号带的数当提示, 不当依据」并复查钱;`_on_shop_bought` 却直接 `phrase.coins -= price` 不复查 `phrase.coins >= price`。现在 shop 的 `_coins` 与 `phrase.coins` 同步得住所以没出事,但两个入口一条原则两种做法。
建议:买入也按 `Economy.shelf_price(j, run.joker_slots)` 重算并校验余额。

---

**整体健康度**:铁律守得不错——钱、装槽、`Tape.on` 确实只在 `phrase.gd` 落地(shop/hand/tray/replace 都只发信号),状态机对双击/队列输入的闩锁齐全,信号接线顺序没有再埋 `_ready` 雷;真正的洞集中在**「第二条入口漏掉主路径的步骤」**(重开、教学商店)和**08-13 以后的重构残片**(按钮重复创建、死配置、死演出)。
**最该先修的两件**:#1(教学商店买的卡被没收,这是新玩家第一次花钱的体验)和 #2(重开绕过 Director/解锁门,1.1 的 Director 在「再来一次」这条最常走的路上等于没上岗)。
两者的共同修法是同一个:把「开局三步」和「样品回收」都收成**一份**函数,别再让两条入口各写各的。
---

# 切片:view-b

评审完成。以下为 view/ 渲染切片的发现,按严重度排列(全部读过对应代码行确认)。

---

**1. `view/honors.gd:77-83` · 🔴 · 置信度高 · 资产页买错货**
```gdscript
for i in range(_asset_rects.size()):
    if (_asset_rects[i] as Rect2).has_point(p):
        SaveState.buy_asset(String(Asset.roster()[i]["id"]))
```
而 `_draw_assets` 在 `honors.gd:347` 对「未持有且不在架」的条目 `continue`,`_asset_rects` 的下标从此与 `Asset.roster()` 错位。`data/assets.json:99` 已埋好 `season_now` 脚手架,第一件带 `season` 的资产一下架,它下面每一行点下去都买成**上一件**并真扣宝石。现在 11 件全常驻所以潜伏。
修法:`_asset_rects.append({"r": r, "id": id})`,命中时直接用存下来的 id。顺带:`:339` 注释说「10 行/行高 74」,代码是 11 件/`y += 76`;无滚动,第 12 件(1120..1190)会压进页签轨(`TAB_Y=1143`)。

**2. `view/home.gd:106-113` / `honors.gd:56-58` / `album.gd:118-125` / `heroes.gd:66-68` / `widgets.gd:1052-1054`(BlindBoard)· 🟠 · 置信度高 · 静态页面 60fps 全量重画**
这五处 `_process` 无条件 `queue_redraw()`。首页每帧:顶栏走**程序化玻璃** `_slab`(10 道渗光 + 6 道 `_lit_rim`,每道 `_dense` 出 ~100 点、每点 6-8 次 exp/pow)+ eq_band 34 条 ×2 贴图 + `Chrome.neon` ×3(各 15 次 draw_string)+ ~40 次 draw_string + ~12 次 `StageTheme.box()` 新建 StyleBoxFlat + 多次 `get_string_size`/`Lingo.t`。商店的 BlindBoard 同样每帧整块玻璃重画外加两个字号自适应 while 循环。唯一在动的只是 eq/脉冲/雨。album 最典型:`:120-125` 一帧触发 self + grid + RainLayer 三层重画,而只有 RainLayer 在动。手机上首页是停留最久的屏,这就是发热来源。
修法:把动效(雨/eq/扫描线/脉冲)拆成薄的子层每帧画,静态内容只在状态变化时 `queue_redraw()`(album 已经有 RainLayer 结构,删掉 `:120/:122` 两行即可);`StageTheme.box()` 的常用组合缓存成 static。

**3. `view/paper_card.gd:89-111` + `:61` / `joker_slot.gd:53` / `hand.gd:517` · 🟠 · 置信度中高 · 每个实例编译一份 Shader**
`_mask_material` 每次 `Shader.new()` 并塞同一段 code。每张 PaperCard `_ready` 建一个镜像 → 一份 Shader;`_get_drag_data` 的预览卡、`hand.gd:517` 每次弃牌的 `_ghost_fly` 幽灵卡、`joker_slot.gd:53` 四个槽 + 替换预览,全部各编译一份。弃牌免费无限 ⇒ 一拍内能触发多次 shader 编译。
修法:`static var _mask_shader: Shader`,只建一次,`ShaderMaterial` 按实例 new 即可。

**4. `view/chrome.gd:89` / `home.gd:36-37,317` / `honors.gd:21-35` · 🟠 · 置信度高 · 假数据跟着 1.0 出货**
`Chrome.page_bar` 在四屏读 `HomeScreen.PROFILE["coins"]` = 2480,与 `SaveState.gems()` 的**真钱包**并排画。按 meta.md 拍板「宝石/券双出口不碰局内金币」,META 层根本没有金币这种货币 —— 这颗 ◆2480 永远不会变真。同屏还有假 LV.12 / XP 340/500,荣誉页 8 条假成就(「累计游玩 50 局 50/50」)和一张把「NEON PLAYER」排进去的假榜。
修法:◆ 章直接删(或改读局内最近一局金币);PROFILE 余下字段要么接存档要么不画。

**5. `view/home.gd:391-393` · 🟠 · 置信度高 · 首页公示一个已废除的费用**
```gdscript
Lingo.t("%d 乐句 · %.0f 秒/句 · 弃牌 ◆%d/张") % [..., GameConfig.DISCARD_COST]
```
`economy.json:3` `discard_cost: 0` ⇒ 首页大卡每关都写着「弃牌 ◆0/张」/ "discard ◆0/card"。CLAUDE.md 2026-08-06 拍板弃牌免费,这行是前朝遗物。同源的 `widgets.gd:1183-1187` DJKey 费用角标(`fee > 0` 才画)和 `hand.gd:466` 的喂值也是死路。
修法:文案改为「N 乐句 · 8 秒/句 · 弃牌免费」并删 DJKey.fee 链路。

**6. `CLAUDE.md:217` / `docs/design/ui_meta.md:237` vs `view/widgets.gd:888-893` · 🟡 · 置信度高 · 档位色文档与代码不一致**
文档写 橙 `#ffb347` → 红 `#ff5f6e` → 粉 `#ff4fa3`,`accent_for` 实际返回 `AMBER ff9b2b` / `RED ff3632` / `PINK ff328d`(08-06 二次校色把主色对回规格,档位那行没跟着改;ui_meta:221 自己都说 `ff5f6e` 是「旧值」)。下一个人按 CLAUDE.md「还原」就会把校色退回去。同一批旧值还以字面量散落:`run_end.gd:145,159`(`35e8e0/ff4fa3/a56bff/ffb347`)、`stage_bg.gd:238-246`、`walker.gd:42-99` CREW 的 color、`honors.gd:17-18`;`widgets.gd:932` `BlindCard.MAGENTA := Color("ff328d")` 就是 `StageTheme.PINK` 抄了一份。
修法:改文档三个 hex;字面量换成 StageTheme 常量(仅 run_end 的彩带色按 mock 保留也应集中成一个表)。

**7. `view/home.gd:394-398` · 🟡 · 置信度高 · 四档画三颗星**
`tier_stars` 返回 1..4(`widgets.gd:896`),首页 `for i in range(3)` 只画 3 颗 ⇒ 第 3、4 段都是 ★★★,档位递进在星上断了一档。
修法:`range(GameConfig.SECTIONS_PER_RUN)` 并把起点 `cw - 68` 改成 `cw - 23*n + 1`。

**8. `view/layout.gd:9` vs `:152-233` · 🟡 · 置信度高 · 文件头立的规矩被自己违反**
头注「坐标一律从 data/ui.json 取,不许硬编码回代码」,正文写死 167(分隔线)/150(标签条)/200·172(槽位)/426·216(音浪)/626·44(eq)/132(唱片)/286(轨道框)等十余个数;`ui.json` 的 stage 节只有 12 个键。`home.gd:30-33` 的 CARD/PAD 同理。
修法:把这些搬进 `ui.json.stage`,或把头注改成实话。

**9. `view/chrome.gd:78-97` · 🟡 · 置信度中 · 同一块 chrome 两种画法**
首页顶栏按 ui_meta ⑭ 做成「色相跟随、饱和 ×0.20、明度 0.42」的无色玻璃(`home.gd:242-247`);三个图鉴页的 `page_bar` 却用页面主色(金/紫/主角色)**满饱和**画同一块玻璃条。它装的还是玩家身份/货币。另:`heroes.gd:114` 传了 `gems`,`honors.gd:94` / `album.gd:184` 没传 ⇒ 资产商店所在的荣誉页顶栏反而不显示宝石余额。(若三份 .dc.html 设计稿明确要求页色,则只剩宝石章这一条。)

**10. 死代码与注释失实 · 🟡 · 置信度高**
- `theme.gd:35,40,41,59-61,44-45,18,19`:`SLATE`(CLAUDE.md 仍说顶栏用它,代码只剩注释提到)、`SURFACE`、`SURFACE_DARK`、`PAPER0/PAPER_EDGE/PAPER_INNER`(「kept so older call sites still compile」,已无调用点)、`GLASS_TOP/BOT`、`FAINT`、`LINE` 全无引用。
- `widgets.gd:379-397` `StageCard.body_grad()/_body_grad`、`:451-452` `PANEL_INSET/PANEL_RADIUS` 无引用。
- `paper_card.gd:10-30` `RATIO/L/R/C/LAYOUTS` 无引用,文件头 `:6-7` 仍说「A–10 传统点阵、J/Q/K 大花色」,`:276-278` 自己承认已砍。
- `joker_slot.gd:318-328,353-355,383-411` `_chips/_icon_for/_mult_for` 无调用;其中 `_mult_for` 是一张**手抄的数额表**(CLAUDE.md:「卡面数额从 jokers.json 推导,不许再手抄第二份」),且已陈旧(twin `×3+` vs `ui.json:135` `×6`)。
- `home.gd:164,209` `_float/_glow` 无调用,`_toast` 永远为空却每帧判断。
- `walker.gd:42-99` CREW 的 `name/color` 与 `characters.json` 的 cn、`manifest.json` 的 primary 各一份(目前碰巧一致)。

**11. `view/stage_bg.gd:17-18,36-37` / `widgets.gd:1082-1084` / `widgets.gd:430-431` · 🟡 · 置信度中(需渲染采样)· 大面积柔光仍在**
局内 StageBg 画两团 1080×920 级径向光,青 0.16、紫 0.20;商店 BlindBoard 背后一团 1.7w×2.1h 档位色背光 0.30。ui_meta「背景 = 黑」一节的判据是**大面积柔光会把黑重新染回来**,首页同类层被压到 0.016~0.055 后整体删除。另 `draw_card` 贴图分支 `:430` 在 glass.png 下面又铺了一块 `0d0f22@0.70` 的海军蓝内衬(注释原话「内衬深底」),正是 08-06 用户以「只是一块玻璃板被打了光」否掉的那层,08-12 换素材时随贴图分支一起复活。建议各截一张图量中心 v 值再定。

**12. `view/vinyl_deck.gd:28-34` · 🟡 · 置信度高 · 注释承诺的节流不存在**
`set_armed` 精心做了「整秒不变就不重画」,但 `:49-53` `_process` 每帧无条件 `queue_redraw()`,这段门禁一帧都省不下。同类:`run_end.gd:379-389` `_sub` 每帧对每个字 `get_string_size` 两遍。

**13. 英文化截断** · 未发现**明显**必截断点。两处临界:`home.gd:376-378` BOSS 规则 "Rolled at start · previewed ahead" 19px 在 356px 内约 320px;`widgets.gd:966-973` 局内盲注卡(145 宽)脸名与右侧槽号同一行,"Forced Rotation" 约占 95px、槽号起点 124px,再长一个词就叠。

---

**整体健康度**:结构纪律(core/view 分离、档位色单点、花色两色、`data/ui.json` 文案)大体守住,视觉层最大的风险不在画法而在**性能模型**——全切片没有一处区分「静态内容」与「动效」,全靠 60fps 整屏重画撑着,再叠每实例一份 Shader。
**最该先修的两件**:① `honors.gd:80` 的资产下标错位(一行改动,避免第一个赛季上线就扣错钱);② 静态页/商店板的每帧重画 + `_mask_material` 的 Shader 缓存(发热与 iOS 内存两条线都指向这里)。顺手把 `弃牌 ◆0/张`、三颗星、文档里三个旧 hex 一起清掉。
---

# 切片:tools-tests

## 评审结果(tools/ · tests/ 切片,只读)

按严重度排;每条都读到了代码。

---

**1. `tools/gate.gd:574` + `tools/gate.gd:195-198` · 🔴 假绿 · 置信 高**
`_play_runs` 自己判生死:`target = round(section_target_for(table, section, mod) * target_scale)` —— **没乘 `Run.variety_mult`**。而 `core/run.gd:313` 注释写着「判生死只有一份:游戏(`target()`)与探针(`RunLoop`)都必须乘这里,别再各写」,`RunLoop.play` (runloop.gd:143) 确实乘了,gate 这一份没有。后果:trilogy 的 target 通路行为臂 `_play_sections(cfg,"trilogy")` 与基准臂**逐位相同**(`target_mult("trilogy")=1.0`,税又没算)⇒ 注释里「实测 0.0 ±0.0,配额对 bot 不 binding」其实是**结构性恒零**,随后被写进 `faces.json weak_upper_bound`(faces.json:393)。这是「规则在游戏里不在模型里」第 7 次,且被豁免表盖住了。修法:`_play_runs` 不要自己算,给 `RunLoop.Opts` 加 `target_scale` 走 `o.mortal`(或至少乘 `variety_mult(mod, run.section_kinds.size())`);修完 trilogy 必须从 `weak_upper_bound` 摘出来重测。

**2. `tools/runloop.gd:89-98` · 🔴 假绿/覆盖声明不实 · 置信 高**
`RunLoop.play` 建 `Run` 后只设 `run_faces`,**`run_boon` 永远是 ""** ⇒ `Run.boon()` 恒空 ⇒ `Beat.settle` 的 `boon_bonus`(beat.gd:110-119)、`Phrase` 的聚光/返场(phrase.gd:111/181)在**所有探针里不存在**。`grep boon tools/` 零命中。双响是 S4 每拍 +50%、余响 +10%,而 `curve.gd` 反解的 S4 目标分、`sim` 的 S4 死亡率、gate/kit/price 全在无 boon 的世界里量的;`t_run.gd:256-280` 只证了游戏侧(验定义绿、验行为红的经典形状)。STATUS.md:268 写「4 boon 全实装,gate.sh 全量绿」——门根本覆盖不到它。券那边至少显式写了「券不进模型」(beat.gd:122),boon 连声明都没有。修法:`Opts.boon`(默认空保持逐字节不变)+ sim/curve 按游戏顺序掷 boon + kit 加 boon 臂;或在 gates.md 显式登记为已知盲区。

**3. `tools/gate.sh:99-105` · 🔴 假绿 · 置信 高**
`tests()` 的判据只有 `grep -q ', 0 failed'`。① 注释「runner.gd 自己不返回非零退出码」是假的(runner.gd:32 `quit(1 if _fail>0)`),但 `out=$(…)` 把退出码丢了;② 不数 `SCRIPT ERROR` / `^ERROR`,不看通过数地板——LESSONS「四条同时满足才算绿」在**唯一要紧的地方**没落地,第 3 种假绿(域中途掐断、RESULT 照样 0 failed)直接过门;③ runner.gd `extends SceneTree` 不是 `Probe`,一个域 parse 失败 → `load().new()` 报错 → 永不 `quit()` → `$(…)` **无限挂起**(第 1 种假绿,门本身没有超时)。修法:`tests()` 里 `timeout`,保留退出码,加 `grep -c "SCRIPT ERROR"==0`、`^ERROR` 逐条过滤良性两类、passed ≥ 上次基线。

**4. `tools/runloop.gd:90` ↔ `core/run.gd:29,143` · 🔴 仪器债(sim A/A 抖 0.1pt 的根因候选)· 置信 中高**
`Run.new()` 的 `_blind_rng := RandomNumberGenerator.new()` 在 Godot 4 构造即 randomize;游戏走 `reset()` 会 seed/randomize 它,**RunLoop 从不 seed**。唯一消费者 `next_request_goal`(run.gd:143)在 `request` 脸(S2 池 8 张之一)当值时每拍掷一次 ⇒ 约 1/8 的局里求情目标随进程变 ⇒ 恰好是「1000 局翻 1 局、偏离换位置」的形状。其余随机源(Deck 有 seed、bot/solver/weighted_pick 走传入 rng)都查过。修法:`RunLoop.play` 里 `run._blind_rng.seed = o.deck_seed * 31 + 7`(不动主 rng 流),然后 A/A 一次验证。

**5. `tools/rankgen.py:35-45` · 🟠 会误导结论 · 置信 高(代码)/ 中(现表是否受害)**
退路解析 gate 日志的正则 `^\s{4}(\w+)(?::[^|]*)?\s+([+-]?\d+…)\s+±` 我用三种行型跑过:`facedown: 上帝 − 蒙住 +1835 ±…` 解析为 **+1835**(belief 通路的 d = oracle − blinded,是**正的信息值**),`trilogy: 通关段数(判生死) +0.0 ±0.0` 解析为 **0.0**(段数量纲)。按 `-t[1]` 排序后盖牌族会排成**最温和**、trilogy 最温和——与 gates.md 实测(盖牌 −1792/−2305,最狠之列)反号。现表 `ranking.json` 里 blackout 在 S3 第 3 位、facedown 在 S1 第 4 位,形状可疑但无法从日志反推来源。修法:退路只认 `---- ① score / ①b solver` 小节内的行,belief/target 一律走设计性覆盖;重刷后对照 gates.md 的量级自检。

**6. `tools/replay.gd:172-177` · 🟠 假 A/B · 置信 高**
`SYNC5_REPLAY_INJECT` 的「注入」是 `_fail.append("[INJECTED] …")`——没往事件流里塞任何非法决策,检查逻辑一行都没被走到。它证明的是「`_fail` 非空时退出码变红」,不是「重放能抓到违规」。与 LESSONS 七「注入误判照样全绿的假守卫」同形。修法:注入时篡改某条 `disc.cards` 为不在 A(s) 的牌,再断言 `_fail` 恰好多一条。

**7. `tools/pair.gd:67` · 🟠 假绿 · 置信 高**
三关全部只 `print` ✅/❌,末尾无条件 `quit(0)`。CLAUDE.md/STATUS 把它叫「守『求解器=游戏代码』」,但它的退出码永远绿;第一关 `diff0>0` 也是 0 退出。修法:`quit(1 if diff0>0 or |z|≥3 else 0)`。

**8. `tools/bot.gd:110-231` + `core/db.gd:1001` · 🟠 规则在游戏里不在模型里(死卡)· 置信 高**
`_card_ev` 是一张手维护的 `match id` 表,落表即返回 0(bot.gd:154 自己写着「缺臂 = bot 永远不买」)。我用脚本对了一遍:`popup`(support, proof:score)**无臂且不在 `sim.json ev.cards`**;db 只校验 `ev.cards ⊂ jokers`,不校验反向;`t_draft` 守的是求解器 `Draft.card_value`,不是规则 bot。sim 九条队列全 adaptive ⇒ 快闪在尺子里是一张从不被买的卡。修法:db 加「score/solver 通路的 support 必须有 ev.cards 条目」反向校验,或在 `_card_ev` 缺臂时 `push_error`。

**9. `tools/tapeserver.py:24,37,42-47` · 🟠 安全面 · 置信 高**
`SAFE = ^[A-Za-z0-9_.-]+$` 放行 `.` 与 `..`:`X-Sync5-Install: ..` ⇒ `os.path.join(ROOT,"..")` = 运行目录,配任意 fname 可在 inbox 之外**创建**文件(`exists` 去重挡住覆盖,挡不住新建);`int(Content-Length)` 非数字直接抛 ValueError(500,线程级)。修法:拒绝 `.`/`..`,`realpath` 容器检查,`Content-Length` try/except。webserve.py 没发现问题。

**10. `tests/t_asset.gd:58-71` · `tests/t_director.gd:321-328` · `tests/t_boon.gd` · 🟠 测试质量(恒真 + 漏契约)· 置信 高**
两处「逐字节等价」比的都是**默认实参 vs 显式同值**(`weighted_pick(…,{})` vs `(…,{},{})`;`roll_run(3,ra,rk)` vs `roll_run(3,rb,rk,{})`)——同一条路径跑两遍,必然相等,证不了「加 boost/ctx 之后空表路径没变」。**非空 boost 的效果零断言**(探索型货架 ×1.5 没有任何测试);`BlindBoon.roll` 的 `seen` 参数零测试(t_boon 根本不调 `roll`)。另 t_asset:144 消息写「must not write the save」但只断了返回值长度(LESSONS 说的前后对比形状没做)。

**11. `tools/gate.sh:110-111,130` + `gate.sh:46` · 🟠 注释承诺不存在的机制 / 增量盲区 · 置信 高**
注释「增量模式下…**单调性与哨兵仍然全跑**」为假:gate.gd:93 `if _only == ""` 才跑它们,而增量模式要么带 `SYNC5_GATE_FACE`(跳过),要么根本不启动 gate.gd;文件末尾横幅自己又说「单调性/哨兵未跑」。`MECH_RE` 漏了 `data/characters.json`(主角被动在结算链里)与 `data/boons.json` ⇒ 改主角被动后 `--changed` 判「没改卡/脸」,kit 与 gate.gd 全跳。

**12. `tools/probbook.py:115-126,161,179` · 🟡 仪器债(曝光列)· 置信 高**
① bot 列的 `n` 来自 report.gd:232 的 `support_drafted` = **购买次数**(bot.gd:480/495),表头却写「(n拍)」,且用它加权;② `human_rates` 只对 `held` 里的卡计 beats ⇒ 永远是「持有拍」分母,LESSONS 那条「换分母当场答完」(反事实曝光率)**从未进工具**——这就是「不产出曝光列」的根因;③ `DESIGN_P` 仍是 LESSONS §五.7 点名的散文表(含已删的 `backup`),`prior.gd` 的算式输出没有接进来。

**13. 手抄数值断言 · 🟡 · 置信 高**
`tests/t_economy.gd:14-25`(4/6/9/11、reroll 3/5、sell 5/2)、`tests/t_ticket.gd:17,22,45,62`(5 张、max_held 5、[1.2,2.5])全是 economy.json / tickets.json 的字面量,违反 runner.gd:49-52 的推导纪律(同文件的 `DISCARD_COST` 倒是推导的)。附:`t_lingo.gd:115-118` 任何含 `Lingo.t(`/`.get(`/`print(` 的**整行**免检,同一行里的裸中文字面量漏网。

**14. 死工具 / 会挂起的工具 / 文档失真 · 🟡 · 置信 高**
`tools/_measure.gd` 读 `assets/frames/{small,big,boss}.png`——目录里只有 `glass.png` ⇒ `null.get_image()` 报错后 `quit` 不可达,且不继承 `Probe` 无看门狗;`tools/blind_sheet.gd:5-6` 描述的是 08-06 已废的「小盲/BOSS 墙在 S2/4/6/8」结构,仓库零引用;`tools/hundred.gd:15` 用 `assert` 且 `extends SceneTree`(失败即挂);STATUS.md:102「41 个文件」实为 55 gd + 4 py + 1 sh;`price.gd:24` 说输出「没有下游」而 rankgen.py 正在消费它。

**15. `tools/runloop.gd:212-229` `fork()` · 🟡 · 置信 高**
显式逐字段拷贝,之后加进 `Run` 的 `section_kinds / section_discards_used / cache_meta / previous_raw_score / request_last / run_boon` 一个没跟上 ⇒ 买牌推演里 ration 预算重置、wetink/doubleseal 的缓存年龄归零、trilogy 税消失。没有污染(都是新字典),但没有「fork 字段完备」的测试守着,下次加字段还会漏。顺带:`wallet.gd:61` SpyBot 记的 `_offers` 拿不到 bot.gd:341-365 两个「必定出」补丁之后的货架,独狼/点唱机在场时观测与 bot 所见不一致。

---

**总结**:切片整体纪律很强(配对、具名豁免、反向锁、Probe 看门狗都在),但**两条「门」自身有结构洞**——gate.sh 的测试判据只看一个 grep、gate.gd 第三份判生死没乘税——而且洞恰好被豁免表和注释盖住了,形状和 LESSONS 里八种假绿同族。
**最该先修的两件**:① gate.gd `_play_runs` 改走 `RunLoop` 的那一份判生死并把 trilogy 从 `weak_upper_bound` 摘出重测(#1);② `RunLoop` 补 boon(或显式登记为盲区)并给 `_blind_rng` 上 seed(#2/#4)——前者决定 S4 目标分是否可信,后者让「逐字节不变」这把尺子重新能用。
---

# 切片:data

## 数据与配置评审(只读,全部条目已读到源码确认)

先说对照结果里**没问题**的部分,免得重复排查:`_PREDICATES`(26)与 `fx.gd::_when_ok` 的 match 臂 26/26 一致;`_DO_KEYS`(17)与 `_do` 处理的通道 17/17 一致;`_FACE_PARAMS`(30)与 `modifier.gd` 读的 30 个参数逐一对上;jokers.json 8 张带计数器的卡,定义名与 `counter_gte`/`per:counter:`/`{counter:}` 引用完全一致;`on_discard` 值全是 `"sum"`;ranking/assets→tickets/director→economy 的跨文件引用都有硬校验;lingo.json 317 条无死键、占位符齐;run.json 与 economy.json 的数字注释(420/增量/13.7%/38◆/12◆)与实际值一致;ui.json blindcard 文案数字与 faces 参数逐条一致。

---

### 🔴 1. `export_presets.cfg:12,72` · 两个预设的 `exclude_filter` 漏掉约 57MB 非运行时资源,已进了 92MB 的 web pck · 置信度高
在 `build/web/index.pck` 里按导入产物名(`<basename>.png-<md5>.ctex`)确认了这些**确实在包里**:`assets/characters/source/*`(48 张原画 **43MB**,唯一消费者是 `tools/art/build_character_assets.gd`)、`assets/reference/*.png`(10 张美术参考 **12MB**)、7 张退役小丑原画(backup/crescendo/declutter/doggybag/trio/twotone/xray,1.1MB)、`assets/characters/contact-sheet.png`、`assets/jokers/review-new-seven.png`、以及 **`build/web/index*.png`**(上一次导出的产物被当成项目资源重新导入,build/ 有 .import 文件为证,只 git-ignore 没 .gdignore)。`resources/*` 与 `design/*` 两条过滤项是死的——根目录不存在这两个目录。要紧在于 Web 预设注释自己写着「2026-08-12 内存止血:source 原画不进包,iOS 浏览器回收重载」——但只排了 `assets/jokers/source/*`,角色 source 漏了,43MB 原画仍然全解压进内存。**修法**:filter 追加 `assets/characters/source/*,assets/reference/*,assets/characters/contact-sheet.png,assets/jokers/review-new-seven.png`;`build/` 与 `assets/reference/` 各放一个 `.gdignore`;退役小丑 PNG 挪进 source/ 或删;删掉两条死过滤项。

### 🔴 2. `export_presets.cfg:48-50` · TapTap 包是 debug 签名 + 占位包名 + dev 版本号 · 置信度高
读了 `build/sync5-taptap.apk`(08-19 产物):签名证书 `CN=Android Debug`,manifest 含 `com.sync5.dev` / `0.1.0-dev` / versionCode 1。预设里 `package/signed=true` 但无 keystore 配置 ⇒ 走 debug keystore;`launcher_icons` 四项全空。TapTap 与各商店拒收 debug 签名包,**包名上传后不可改**(预设注释自己也写了)。记忆说 TapTap 走到「资质环节」,大概率还没传包,所以现在改是零代价,传了之后就是永久的。**修法**:用户自建 release keystore(这是凭据操作,我不碰),预设填 `keystore/release*`,包名定稿,版本号改成 `1.0.0`/code 2 起。

### 🔴 3. `data/tickets.json` ↔ `view/phrase.gd:1120-1150`、`view/tray.gd:19` · 券是「伪配置化」:行为按 id 写死在代码里,JSON 里的 `scope` 与两个 params 没有消费端 · 置信度高
`Ticket.scope()` 只有 `tests/t_ticket.gd:19` 调用;`params.rerolls`(点唱券)与 `params.hands`(补牌券)全仓库无人读(点唱券按持有张数算,phrase.gd:947);`tray.gd` 的 `ORDER := ["overtime","redeal","boost"]` 写死三张拍内券;`_on_ticket_use` 是 `match tid` 五个字面量。而 `Ticket.daily_pick()`(ticket.gd:199)**从 JSON 全表随机发**。后果:用户往 JSON 加一张新券(他会手改 data/*.json)⇒ 每日会发到他手里、占 `max_held` 的位、**托盘不显示、不能用、不报错**。另外 db.gd:114 那句「scope 写错会让券静默地在错误的时机可用」描述的门禁**不存在**——scope 从不参与任何判定,这正是 LESSONS 里「注释承诺不存在的机制」第 N 次。**修法**(二选一):要么 validator 加一条「ticket id ∈ 代码注册表」硬校验 + 注释改口「券需要代码接线」;要么把 tray 的 ORDER 改成按 `scope=="phrase"` 过滤、把 rerolls/hands 真接上。

### 🟠 4. `core/db.gd:883-953 validate_jokers` · 不校验 `kind` 与 `rarity` 枚举 · 置信度高
`rarity` 拼错 ⇒ `economy.gd:27` 定价静默落到 4◆、`economy.gd:88` 货架权重落到 1,`album.gd:263` 的 `RARITY_TINT[c["rarity"]]` 硬索引则直接崩;目前只靠 `t_joker.gd:22-30` 的张数断言**间接**兜住。`kind` 拼错且没写 curve ⇒ 校验**全过**;游戏侧全是 `!= "target"` 当 support(shop/joker/economy),但 `tools/bot.gd:296`、`report.gd:200`、`tapeprobe.gd:96` 是 `== "support"` ⇒ 这张卡**bot 永不买、报表不计**——正是「规则在游戏里不在模型里」的形状。**修法**:`kind ∈ ["target","support"]`,`rarity ∈ economy().draft_rarity_weights.keys()`,两行。

### 🟠 5. `data/sim.json target_tf` · Target 倍率的过期第二份,且 validator 不查 · 置信度高
twin 3.5(真值 6.0)、stair 8(11)、mono 6(12)、triplet 5(10),**wrecker 缺失** ⇒ `bot.gd:143` 给镜面估值时 `tf−1 = 0`,持拆迁时镜面在 bot 眼里一文不值。sim.json 自己的 `_comment` 写着「_target_mult 直接读 jokers.json,消灭双写」——`target_tf` 就是没消灭的那份。`validate_sim` 只查 `ev.cards` 的 id,不查 `target_tf / counterfactual_tv / timing.cards / discard_bias`。附带:`kind_prior` 只有 0..7,`bot.gd:257` 按先验键迭代 ⇒ 观测到的同花顺/皇家永不进混合。**修法**:`target_tf` 从 `Joker.slots_target_mult` 推导删掉这张表;至少 validator 断言键集 == target id 集。

### 🟠 6. `data/jokers.json` 13 张 `bonus_target_pct` 卡的英文 `fx` · 12 张仍写固定数 · 置信度高
encore「+240」(实为目标分 57.7%)、finale「+100」、turnover「+30 per discard」、neonsign「+50」、fullcast「+320」、rainbow「+180」、nopair「+190」、stilllife「+60」、segue「+40 each」、stageexit「+30」、earlyout「+80」、variation「+85」——08-16「加分族跟随尺度」之后一张没改(只有 popup 改成了「big bonus」)。现在不上屏(jokercard + lingo 优先),但它是 `joker.gd:25` 定义的「card text」、`t_joker` 按它断言 7 词,也是 jokercard 缺条目时的兜底。ui.json jokercard `_comment` 的原则正是「写死数字会撒谎」。**修法**:改成「Same hand again: +58% target」一类,顺手让测试断言 `bonus_target_pct` 卡的 fx 不含 `+\d{2,}` 纯数。

### 🟠 7. `data/ui.json jokercard/blindcard` ↔ jokers/faces · 无交叉校验,已有 5 条死条目,缺条目静默降级 · 置信度高
jokercard 里 `declutter / xray / crescendo / doggybag / trio` 对应的小丑牌已不存在;反向没锁:新脸漏写 blindcard ⇒ `widgets.gd:1042` 退回只画 `cn_name`,盲注卡上**只剩「禁回」两个字、规则读不到**;新卡漏写 jokercard ⇒ `joker_slot.gd:216` 退回英文 fx(见第 6 条的过期数字)。另外 `validate_ui` 只查节名,而 view 里约 40 处 `_cfg["key"]` 硬索引(shop.gd 22 处、hud.gd 10 处、hand.gd 6 处,如 `_cfg["insufficient"]`)⇒ 用户手改 ui.json 删错一个键 = 运行时崩、单测全绿。**修法**:validate_ui 增加「每张入池脸有 blindcard、每张小丑有 jokercard、无孤儿条目」+ 每节必备键表。

### 🟠 8. `assets/jokers/manifest.json` · 6 条退役卡仍在,且被图鉴当「未入池」展示 · 置信度高
manifest 69 条 vs jokers.json 63 张,多的 6 条(backup/crescendo/declutter/doggybag/trio/xray)在 `album.gd:95-112` 会以 `pooled=false` 渲染进图鉴——玩家看到的是「还没出的卡」,实际是删掉的卡。反过来 blacktone / jukebox / redtone 三张在售卡**没有原画**(`assets/jokers/joker_*.png` 缺)。**修法**:manifest 删 6 条(或加 `retired: true` 且 album 过滤),三张补图归用户。

### 🟡 9. `data/director.json _context`、`core/db.gd:638,668` · 「两个布尔开关」实际四个;禁用表的理由与 explore_shelf 自相矛盾;三个数值在代码里
`returning` / `explore_shelf` 08-20 加入后注释没跟。`_DIRECTOR_FORBIDDEN.target_weight_mult` 的理由是「货架上 Target 的权重是卡面效果,不是按局数的暗改」,而 `view/shop.gd:385-390` 正按 context 给没用过的 Target **×1.5**。这些开关的数都不在 JSON:连败 −2 / 连胜 +3(`director.gd:135-138`)、×1.5(`shop.gd:390`)、「隔 3 天算回归」(`save.gd:295 RETURN_GAP_S`)——与「数值全部在 data/*.json」铁律的缺口,也是本切片里最重的三个魔法数。**修法**:context 节放 `{streak_down:2, streak_up:3, explore_mult:1.5, return_gap_days:3}`,validator 范围校验(explore_mult ≤1.5 是批过的上限);禁用表改口「按局数的暗改不许,按 context 的探索加权走 context 节」。

### 🟡 10. `data/tutorial.json` 11 段 `_comment` 描述的是 6-7 步的旧版 · 置信度高
数据只有 4 步、没有商店步,而注释里有「第 2/3 步、第 4/5 步」「第 6 步指两块」「第 6 步仍要求跨区多选」「缓存那一步(第 3/4 步)保留两拍」「最后一步(商店)是唯一不设门的」。注释体积已是数据的数倍,读表的人会按注释理解流程。**修法**:注释只留现状(`_comment_five` 那段),演进史挪 CHANGELOG。

### 🟡 11. 几处过期注释 · 置信度高
`economy.json _comment_shelf`:「twotone 双色调(2026-08-14 刚升 rare)」——08-16 已拆成 redtone/blacktone(db.gd:861),「61 张」现为 63;`tickets.json _comment` 末句「『怎么拿到』(每日发放)与 UI 都还没接」——`settle_daily_grant` 与 `view/tray.gd` 都在;`db.gd:194` flair 报错信息「白名单: confetti/crowd」漏了 homejuke;`t_joker.gd:8` 断言 63 而消息写「holds 62」。

### 🟡 12. `core/db.gd` 三处「按段/按表长索引」未锁 · 置信度高
`validate_ranking:254,269` 写死 `["0","1","2","3"]`,不从 `sections_per_gig × gigs_per_run` 推——CLAUDE.md 点名的「改段数要顺手核对所有按段索引的表」正是这种表,改成 5 段时它不会红;`joker_upgrade.costs` 长度不与 `max_level−1` 对账,短了 ⇒ `joker.gd:58` 返回 −1 ⇒ `shop.gd:406` 永远弹「钱不够」;`joker_price_overrides` 的 id 不查是否存在(退役卡的覆盖价会静默悬空)。都是一行校验。

---

**总结**:整体健康度**偏好**——这套 validator 比多数项目严得多(DSL 操作码、脸参数、计数器名、跨文件引用全是 1:1 对得上的),真正的漏洞集中在**「配置化的承诺」与代码不一致**的地方(券、sim 的 target_tf、ui 文案表)和**注释没跟上数据**。
**最该先修的两件**:① 发布线——export filter 补 `assets/characters/source/*` 等并给 build/ 加 .gdignore,同时换 release 签名与正式包名(传包前做,传了就改不了);② 券的伪配置化——要么加「id 必须在代码注册表里」的硬校验并改口注释,要么把 scope/params 真接上,否则用户手加一张券就是一颗不报错的地雷。
---

# 切片:docs-design

## 设计文档评审(docs/design/ 35 篇)· 只读

按严重度排。每条均已读到文档行并对照代码/数据确认。

---

### 🔴 误导实现的矛盾

**1. `levels.md:411-447`(经济与商店)整节是 08-06 之前的经济** · 置信度高
README ⑦ 明说「经济与商店归这一篇」,但表里写着 `Skipping a shop +2`(:428)、`Discard 1 per card`(:437)、`Target swap (S4+ shops) 8`(:440)、`All numbers live in core/config.gd and core/economy.gd`(:443)、`Zero coins: Paid discards disable`(:448)。代码:`data/economy.json` `discard_cost: 0`、无 `target_swap` 键、无 skip 奖励;而 08-16 加的**金币主出口 `joker_upgrade`**(`max_level 5 / costs [4,7,11,16] / step 0.25`)**全目录 35 篇零提及**(`grep joker_upgrade docs/design` 为空)。要紧:这是 README 指定的经济权威,照它做会把弃牌重新收费。修法:整节按 economy.json 重写,加 `joker_upgrade` 小节;旧表移 CHANGELOG。

**2. `levels.md` 目标分表两代过期,三处重复** · 高
`:120` `:276` `:633` 都写 `section_targets = [850, 2400, 6900, 19300]`、`:277` `bot_targets = [215, 540, 895, 1345]`;实际 `data/run.json` `[420, 1500, 3100, 5600]`(08-15~17 真人重锚,STATUS.md:217),`data/sim.json` `[496, 995, 4270, 5678]`。同篇 `:6` 写「每 3 拍一次商店(**8 次**)」、`:8` 写「7 商店」——头两行自相矛盾。修法:数字只留一处并注「以 run.json 为准」,其余引用。

**3. `levels.md:160-166` Target swap 节(`from_section: 1` / `35% shelf chance` / `8◆`)没有任何推翻标注** · 高
同仓库 `jokers.md:646-649` 与 CLAUDE.md 都写 `target_swap{price,chance,from_section}` 整体删除;`levels.md:642` 验证节也划掉了 `from_section`,但 `:48` 与 `:160-166` 正文仍当现行写。`:175` 顶栏「小盲/大盲/BOSS」、`:177`「4 groups × 3」进度点(实际 `view/hud.gd:38` 只画 `SECTIONS_PER_RUN`=4 个)同属 12 段时代残留。修法:整段加 `⚠⚠ 已被 Target 回池取代`。

**4. `tech.md` 的 schema 节是 08-05 快照,而它被 README ⑧ 与 CLAUDE.md 指定为 schema 权威** · 高
`:289-301` run.json 示例:12 个 `section_targets`、`blind_names ["小盲","大盲","BOSS"]`、`phrases_per_section: 5`、`gig_clocks 9.0`;`:305-315` economy.json 示例:`discard_cost: 1`、`draft_rarity_weights 70/25/5`(实际 35/30/25)、含 `target_swap`。`:49-67` tutorial.json 写「6 步」、`seconds: 12`、键只有 `seconds/unlock/command/signal`,而 `core/db.gd:561` 白名单是 `[seconds, unlock, require, command, signal, focus]`——**动作门 `require` 与 `focus` 这两个现行的核心键 schema 文档里不存在**。`:31-40` 文件表列了 7 个文件,`data/` 实有 15 个(缺 tickets/assets/director/ranking/boons/ui/tape/lingo)。修法:示例块逐个换成「只列键名 + 指向 db.gd 校验函数」,不再抄数值。

**5. `difficulty.md` 说 Director「未接线」、C 轴「未实现」,两者都已实装** · 高
`:20` 表格「Director(已实装,未接线)」、`:239` §3 标题同、`:241`「游戏还没有调用它」、`:246-248`「还差 ②接线」。代码:`core/run.gd:98` `Director.roll_run(run_index, _blind_rng, face_ranking, director_ctx)`,`view/phrase.gd:559` 组 ctx。`:21` `:26` `:229`(§2.4)说脸的解锁表「未实现」,而 `core/modifier.gd:141-146` `unlocked_at()/min_run` 已在,`faces.json` `norepeat min_run: 10`。`:302` 第 3 条指「§2.3 解锁曲线」实为 §2.4。修法:§0 表、§3 标题、§2.4 状态三处改「已实装」,加 min_run 的规格。

**6. `difficulty.md` 断言「排序绝不进 data/」,而 `data/ranking.json` 已存在三天** · 高
`:243-246` `:311-316`「排序本身是 price.gd 的读数…**抄进 data/ 就会过期**…所以它是 roll_run 的入参」。实际:`data/ranking.json`(`tools/rankgen.py` 08-18 生成,文件头自称「仪器输出手改无效」),`core/db.gd:236-270` `validate_ranking` 含反向完备性校验,`core/run.gd:172` 从 `DB.ranking_tiers()` 读。`difficulty.md` 全文无 `ranking`/`rankgen` 一词,`data/director.json._comment_band` 同样过期。这正是 LESSONS「注释承诺了一个不存在的机制」的反向形态:文档禁止的东西代码做了。修法:§3 加「排序的落点 = ranking.json(生成物,不手改,db 守完备性)」并注明为何改了主意。

**7. `difficulty.md §4` 教学关三个版本并存,无一与 `data/tutorial.json` 一致** · 高
`:366`「6 步脚本」、`:440`「教学关建议 gig_clocks [12,10,8]」、`:451-463`「现行脚本(**7 步**)」表(12/12/10/10/10/8/8 秒,门 play/discard/discard/swap/swap/multiselect)。实际 `tutorial.json`:**4 步 × 8.0s**,`require` 为 `play / swap / "" / ""`,第 3、4 步教小丑牌样品与盲注(CHANGELOG「教学四轮定稿」)。虽有「tutorial.json 是权威」一句,但整张表会让人按 7 步去改。修法:删表,只留「步数/秒数/门见 JSON」+ 三条设计判据。

**8. `meta.md:13` 红线 ②「db 校验:纯数值分红已废(结构性保障,不是自律)」—— 校验恰好相反** · 高
`core/db.gd:196` 的「无出口」判定是 `yg == 0 and tk == "" and tr == "" and fl == ""`,即 **`yield_gems > 0` 单独就算合法出口**;`tests/t_asset.gd:111-113` 更是显式断言一条「每局分红 +1 宝石」的纯分红资产 `validates clean`。红线说有门,测试锁的是「门开着」。修法:要么改 db 拒 yield-only(顺手删 `yield_gems` 白名单),要么把红线改成「靠 roster 自律,t_asset 锁出厂零分红」。

---

### 🟠 权威 / 标注混乱

**9. `context.md` 与 `meta.md` 落地当晚就被代码超车,待拍清单里一半已拍已做** · 高
context.md `:12`「director.json 只有**两个**布尔开关」、`:35`「boon、货架、剧本状态**尚未**接 context」、§7 岔 #1/#3/#4 标「等拍/做」。实际 `data/director.json.context` 四键 `novelty/streak_shift/returning/explore_shelf`(`db.gd:677` 白名单同),`core/blind_boon.gd:40` `roll(rng, seen)`,`view/shop.gd:385` 探索货架 ×1.5,`core/save.gd:297` `RETURN_GAP_S = 3 天`;director.json `_context` 注明「08-20 用户委托按设计稿推荐落地」。`difficulty.md:261`「context 节只认两个布尔」、`core/director.gd:12`「两个旋钮」同样过期。meta.md `:32,:36`「现役十件」实为 11(`turntable` 点唱机 = §2「推荐下一批」已做),§4 赛季窗口的 `season`/`season_now` 脚手架已在(`asset.gd:57-65`),§6 验收表缺点唱机一行。修法:两篇 §1/§7 各加「08-20 落地」行,四岔改 ✅。

**10. `ui_meta.md` META 节:v1「资产分红」未标被 v2 推翻;开头与 README 仍称「未实施」** · 高
`:4` 与 README ⑥「UI 与 META(**均为前瞻,未实施**)」;`:106-113` 说 08-19 已上线 v1 且「财富 = 宝石(按通关段数入账 + **资产每局分红**)」——分红当晚被 v2 判死(meta.md:7),此处无 ⚠⚠;`:514`「META —— 不验证,因为还没做」,而 `tests/t_asset.gd` 45 条。修法:META 节只留三层生命周期表 + 指针到 meta.md,其余删;README ⑥ 改写。

**11. Director「不读 context」的反转只更新了 difficulty.md 一处** · 高
`levels.md:466-480` 标题「Director(前瞻,未实施)」+ 08-14 横幅「三节因读 context 作废」,未加 08-19 反转;`generating.md:139-160`「**m 现在几乎是空的**」「ui_meta(meta)整块未做」「会话边界…没做」——现 `save.gd` 有 `streak/faces_seen/boons_seen/targets_used`,`core/tape.gd:58` 有 `sess`,资产已上线。context.md 自称「与 generating.md §5 分工写死」,但 generating.md 没有回指 context.md。修法:三处各加一行 ⚠⚠ 指 context.md/meta.md。

**12. `jokers.md` 正文前半仍是 v0.1 roster,与自己后半矛盾** · 高
`:180-196` Draft shop「Skip pays +2 ◆」「Targets… One per run」;`:198-213` Roster v0.1「Targets (5, **no rarity**)」Twin「Pair ×3, Two Pair ×5」、Lone Wolf「×4」,vs `jokers.json` twin `rarity: rare`、`×6` 族内统一、lonewolf「+3 coins; Targets always offered」,共 63 张;`:246-266` Boss faces 仍列 6 张含已退役 `Cover Charge`;`:630`「Target 5 + Support 18」;`:664` 小丑牌门「🔨 建设中」、`:671`「小丑牌**没有**门」—— `tools/kit.gd` 已在且 CLAUDE.md 列为命令(`gates.md:510` 同样过期)。修法:v0.1 roster 整段搬 jokers_history,正文只留「现役见 jokers.json + STATUS」。

**13. `telemetry.md` 事件表少 4 类,「未做」清单里两项已做,回传通道零记载** · 高
`:38` 「21 类」表无 `lock / ticket / upgrade / tutorial_done`(`grep Tape.on view/` 可见);`:154-166` §0.10 列「`early_settle()` UI 还没接」(08-13 已接,即 `lock` 事件,ui_meta.md:520 有全文)与「会话边界未做」(`tape.gd:58` `sess{id,gap,runs_prev}`)。1.1 的回传通道(`tape.json.upload`、`core/uplink.gd`、`view/beacon.gd`、`tools/tapeserver.py`)在打点规格里一字没有。修法:补四行事件 + 一节「回传:缺省关、批量/重试/sent 目录、隐私页待补」。

**14. `numbers.md:28` 说 p̂ 已改由 prior.gd 算出,账本脚本仍是手推** · 高
`tools/probbook.py:41`「设计概率 p̂:**策划手推**,带一句推导」,`probbook.md` p̂ 列仍是散文;账本生成于 08-12(12 局、~20 张卡),roster 已 63 张。「仪器读数手改无效」与「仪器没重跑」叠在一起,读者会以为表是现行的。修法:numbers.md §1 改成「p̂ 的先验值在 prior.gd 输出,probbook 尚未接入(仪器债)」,或真接入后重刷。

**15. `blinds.md` 头部状态停在 08-10,个别脸语义过期** · 中高
`:3-6`「尚未合并…七项**逐项待用户裁决**」,而 `blinds_review.md:303`「08-13 用户裁决:同意你的判断」逐条落定;`:104` trilogy「六拍内需要完成三个不同牌型」未写 08-13 改成的「缺一种目标 ×1.25」(`faces.json` fx「Three hand types, or target rises」,`variety_penalty 0.25`);`:29`「开局公开**前三轮**盲注和第四轮**固定的赶场**」——第四轮已 4 张,且游戏只预告下一场(`view/phrase.gd:442` 取 `section_idx + 1`),`blind_candidate_atlas.md:9` 的「四张开局全部公开」同。修法:头部改「08-13 已裁决,见 review §6」;两处机制句对齐数据。

**16. `visual.md` 的「已批准」边框色规则没有实现,也没有验证节发现它** · 中
`:38`「Frame color: Target/Common cyan, Uncommon violet, Rare gold, Blind magenta」;`view/joker_slot.gd:128` `_accent()` 恒返回 `CYAN`,图鉴 `album.gd:24` 用 `8ea3c8/5fd8ff/ffd36e`(无紫)。`:51` 资产路径 `assets/docs/design/…html` 不存在,实际 `assets/design/joker_blind_visual_system.html`(像是 `design/→docs/design/` 批量替换误伤)。修法:标「视觉规则未实装」或落地;修路径;补一行验证(「截图对照四色」)。

**17. `solving.md` 手速预算数字未随 08-13 校准更新,且与 generating.md 打架** · 中
`:187` `:719` `beat_budget{discards: 2}`「现在是猜的」;`run.json` `discards: 4`,`generating.md:301` 明写「已校准到 4(2026-08-13)」。修法:solving.md §2.7 加一句「已量到 4,见 generating.md III-1」。

**18. `gates.md §10`「建议调研四个方向」= `research_pacing_retention.md` 已写完的四项** · 中
`:518-529` 仍以「建议做一次正式调研」口吻列 DDA/心流/near-miss/短局留存——LESSONS 八「调研前先查仓库」正是被这种遗留指引坑的。§9 表 row 2(可加性)已在 `:132` ✅ 却未划掉;row 7「不读 context」过期。修法:§10 改成四条指向 research_pacing_retention 的结论编号。

**19. `taptap.md` 结论与后续拍板脱节** · 中
`:3-5`「免软著…硬门槛 = **防沉迷**」;`TODO.md:776` 08-17 用户拍板不做防沉迷(TapTap 只是试玩渠道),交接记忆称资质环节「大概率只差软著」;1.1 的回传通道让「纯单机」前提(`:90` 开放问题)变成现实问题;`meta.md §5` 若选 IAP 岔 B 会直接翻转 `:13-17` 资质矩阵,两篇互不引用。修法:头部加 08-17 拍板与「回传上线后不再是纯离线」两行。

---

### 🟡 链接 / 整理

**20. README 导览与指针** · 高
未收录 `blind_candidate_atlas` / `blinds_review` / `taptap` 三篇;⑥ 描述过期(见 #10);`:26`「21 类事件」过期;`:61`「`blinds.md §6` 加一张新脸的完整流程」—— §6 是退池裁决,流程在 §5.1;cards/levels/ui_meta/tech/vision 五篇头部「由 `X.md` + `X.md` 合并而成」是改名脚本留下的自指废话,且都说「README 的**九**篇结构」而 README 是 11 篇。老编号残留:`generating.md:7` `18_Solver_Plan §2`、`:186` `19 §4.1`、`:224` `19 §7.5`、`levels.md:647` `19_Generator_Validation §4.1`;CLAUDE.md:32「按 22 → 23 → 24 → 25 读」。

**21. `solving.md` / `generating.md` 小节编号重复,跨篇引用无法定位** · 中
solving.md `## 3/4/5/6/7/8` 各出现两次(`:223` 与 `:463`、`:355` 与 `:526`…),`### 8.2b` 嵌在 §3 里,「§7.1」既是「先验 DP」(:573)又是「时间约束 binding 实测」(:780)——generating.md:308 引的就是后者;generating.md `## 1` 下挂 `### 4.1-4.3`,`### 5.1-5.4` 出现两轮。修法:一次性重编号,老编号用 `（旧 §x）` 保留一轮。

**22. 验证节缺失或空转** · 中
无验证节:`numbers.md`(只有 SOP)、`visual.md`(见 #16)、`probbook.md`、`jokers_atlas`、`archetypes`、`taptap`;已过期的验证节:`levels.md:638-671`(引 `19_Generator_Validation`)、`difficulty.md §5` 回归基线 1104(STATUS 已 1868)、`ui_meta.md:514`(见 #10)、`jokers.md:659-668`(kit.gd 状态)。

**过程混进规格最重的篇目**(按 CLAUDE.md 判据):`levels.md`(§1-5「存档」+ `:181-200` 三轮 bot 校准 + `:593-636` 附录,约 45% 篇幅是经过)· `jokers.md`(`:280-402` Calibration 8×1000 runs 逐轮账 + `:516-658` 附录)· `difficulty.md`(§4.1 三版诊断、§4.4 两次实测失败、§4.3.1 外链、§5 回归数字)· `ui_meta.md`(返工史、`:520-552` 点唱片 M5 整段是一次改动的经过)· `tech.md`(`:633-737` 五步迁移的逐日实测)。

---

**整体健康度**:中偏差。建模/原则类(prior、capability、gates 前半、solving 主干、numbers §0-§8)仍可信;但 08-15→08-20 那一波(目标分重锚、教学四轮、升级出口、券、资产、ranking.json、context 四开关)几乎只进了代码与 STATUS/CHANGELOG,**设计篇普遍落后 1-3 代**,而 README/CLAUDE.md 把 levels/tech 指定为经济与 schema 权威——这是最危险的组合。
**最该先修**:① `levels.md` 经济节 + 目标分表 + Target swap(#1-3);② `tech.md` schema 块改成「键名 + 指向校验函数」不抄数值(#4);③ `difficulty.md` 三处状态(Director 接线 / ranking.json / 教学 4 步)(#5-7)。顺手把 #8 的红线改成真话。
**合并或降级为历史的建议**:`blind_candidate_atlas` + `blinds_review` → 并入 `blinds_history`(已消化);`jokers_atlas` + `archetypes` → 头部改「已消化入 63 张 roster,剩余候选」或入 `jokers_history`;`ui_meta.md` META 节整体让位 `meta.md`,`visual.md` 并入 ui_meta 的现行实现节;`levels.md` §1-5「存档」与 bot 校准节搬 CHANGELOG;`gates.md §6/§10` 删减为指针;`taptap.md` 移出 design(它是发行事务,归 STATUS/TODO 更合适)。
---

# 切片:docs-root

## 根文档评审(只读,已逐条核对到实物)

### 🔴 会误导接手者的过期事实 / 矛盾

**1. `CLAUDE.md:32` + `CLAUDE.md:100` · 🔴 · 置信度高**
「建模这条线按 `22 → 23 → 24 → 25` 读」「docs/design/ 01/02/04/05/08/11/12 已同步;07/09/10 是前瞻」—— 编号文档 08-09 已全部去号重命名(`ls docs/design` 无任何数字前缀;CHANGELOG:780-806 记了这次重组)。这是 CLAUDE.md 的第一屏,新人照着找会一篇都找不到。修法:L32 改成「建模线按 `prior → solving → generating → capability` 读」(docs/design/README.md:92 的顺序);L100 标题括号整段删掉,或改成「现行规格以 `docs/design/README.md` 主结构表为准」。

**2. `CLAUDE.md:105` · 🔴 · 置信度高**
「唯一的闸门是 8 秒钟,**金币只剩买牌一个出口**」—— 08-16 起升级系统是**金币的主出口**(`data/economy.json` `joker_upgrade`:5 级、costs 4/7/11/16、step 0.25、「金币的主出口」原话就写在注释里)。而且升级的三条规则(按**增量**放大不按整数 / 金币通道不放大 / 规则牌不可升级)都是去掉数字仍成立的原则,CLAUDE.md「已拍板的规则」里一个字没有。修法:L105 改「金币两个出口:买牌 + 升级」,并在 draft 商店条目后补一条「升级」原则(三句话,数字留在 economy.json)。

**3. `TODO.md:140-147` + `TODO.md:354-357` · 🔴 · 置信度高**
两个「下一个 session 从这里接」标题并存(08-17 与 08-16),08-17 那个第一句是「🚨 第一件事:门已经过期了,必须重跑(~4h)」。实际全量门 08-18 凌晨已跑完(CHANGELOG:184-187,16192s,唯一红点 lowend 已豁免),1.0 已出货(TODO:206 自己写的)。接手者从 TODO 顶部往下读,第一个动作指令就是错的。修法:两个交接节整段搬 CHANGELOG(见末尾方案),TODO 只留一个「从哪接」指针指向 STATUS 增量快照。

**4. `STATUS.md:176-180`「三条一眼就该知道的现状」· 🔴 · 置信度高**
#1「目标分表是占位」与 #3「真人数据为零」都被同一份文件推翻:STATUS:147/269 写「真人数据有了,11 局合格局」;STATUS:216-218 写 `section_targets` 已由真人试玩重锚 `[420,1500,3100,5600]`(`data/run.json` 核实一致,并说明是「目标分由生成器算」的显式例外)。这一节没有任何「旧文」标记,而标题恰恰是给新人看的。修法:重写三条 —— ① `section_targets` 是真人重锚值、`bot_targets` 是仪器刻度,别用 sim 验前者;② 模型只信相对排序;③ 真人样本薄(11 局),发挥系数仍禁拍初值。

**5. `STATUS.md:280-287` Android/TapTap 段 · 🔴 · 置信度高(软著一句为中)**
三处与现状冲突:「硬门槛 = 防沉迷 SDK」vs TODO:776「防沉迷 SDK 明确不做(08-17)」;「上传 TapTap 前要换正式包名 + 发布 keystore,**见 TODO**」—— TODO 里已无此项(grep keystore 仅此一处),且 1.0 实际以 `com.sync5.dev` debug 签名出货(TODO:208);「免版号/软著/ICP」vs TODO:210「软著材料包」仍悬着、CHANGELOG:106「备案自己去跑」。修法:整段改写成「1.0 已出 APK(build/sync5-taptap.apk,debug 签,占位包名)· 正式发行目标美国 · 资质/软著归用户自办 · 防沉迷不做」,把 Web/Android 导出命令保留。

**6. `STATUS.md:41` Boss 脸计数 · 🔴 · 置信度高**
「29 张在池;另有 1 张退役(rotation)」。`data/faces.json` 实测:33 条,有 `tier` 的 28 张(8/8/8/4),无 tier 的 5 张(unplugged/static/rotation/cover/freshsheet = 按 db.gd:477 的规则即未入池)。同文件 STATUS:235 又写「30 张脸一行没改」,TODO:679 写「28 脸」。三个数打架。修法:改「28 张在池(按 tier 计,8/8/8/4)+ 5 张无 tier 未入池;以 `faces.json` 有无 `tier` 为准」。

**7. `TODO.md:177-190` vs `LESSONS.md:129-159` vs `STATUS.md:224` · 🔴 · 置信度高**
TODO 列「七种绿是假的」并声称「全部写进 LESSONS」;LESSONS 的第五/六/七种是「门跑时改源码 / 账本说谎 / --check-only 漏孤儿代码」,与 TODO 的 #5/#6/#7(改源码 / 门覆盖不到 / 探针闸让 `consume_ticket` 恒 false)只对上一条;STATUS 又说「八种」。`grep consume_ticket\|探针闸 LESSONS.md` = 0。「全部写进」是假账,形状正好是 LESSONS 第六种自己说的那种。修法:LESSONS 统一编号到八种,补「门覆盖不到的地方(输入命中)」与「自己把代码移出测量范围(探针闸)」两条;TODO 那张表删掉,只留一句指针。

**8. `LESSONS.md:586-587`(+ `TODO.md:198-199`)· 🔴 · 置信度高**
「要覆盖教学关就像 `tools/tutorsheet.gd` 那样直接把 `run.tutorial` 按上去」—— 08-18 起这正是被判定为「按晚了 = 两次假象来源」而废弃的办法(CHANGELOG:194-196);现行是 `SYNC5_PROBE_FRESH=1` 走真人同款入口(`tools/tutorsheet.gd:7,26`、`core/save.gd:38` 已改)。LESSONS 作为「别退回去」的文件,此处推荐的是退回去的做法。TODO:198 同一条待办未划掉(TODO:219 又标 ✅)。修法:LESSONS 就地标「⚠⚠ 已被 `SYNC5_PROBE_FRESH` 取代」并写一句为何旧法错;TODO:198-199 删。

### 🟠 分工违反

**9. `CHANGELOG.md` 整体 · 🟠 · 置信度高 —— 08-16/17 第一批没有任何条目**
`grep "420\|bonus_target_pct\|joker_upgrade\|做中学" CHANGELOG.md` = 0。S1 921→560→420、升级系统、加分族 A 案(13 张换 `bonus_target_pct`)、教学关重做、双色调拆分、`min_run` 新通路、Director 主通道接线、`bot_targets` 重锚、14 条真人 bug —— 这批最大的转折只活在 TODO:140-352。STATUS:215 写「细账在 TODO「2026-08-17 交接」与 CHANGELOG」,后半是空指针。修法:新增 CHANGELOG「2026-08-16 · 第二批」「2026-08-17 · 第一批 + 14 条真人 bug」两条,内容从 TODO 搬。

**10. `CLAUDE.md:42,45,51-53` · 🟠 · 置信度高**
「~15 分钟」「~3 分钟」「S10 把单测从 <300s 拖到 ~716s,地板 12 分钟以上」—— 按本文件自己的判据(去掉数字还站得住吗)这是证据,STATUS:119-135 与 CHANGELOG:302-307 已各有一份。修法:命令表去掉所有耗时;L51-53 压成一句「耗时会过期,跑前看 STATUS 门耗时表估」。

**11. `TODO.md:268-352` + `TODO.md:484-661` · 🟠 · 置信度高**
前者是 08-16 两批「账」(分级门 9 轮、D1/D2、门抓到的三件、新欠的),全是已完成的经过;后者是加分族 10 倍差距的三版推导、14 张期望表、牌型倍率全表、「窗口窄只有 2 张」—— 推导已落地(A 案 08-17 实装,两对 ×3 已恢复),按 TODO:428-434 自己定的规则应归 CHANGELOG / `docs/design/jokers.md`·`cards.md`。共约 260 行,是 TODO 体量超标的主因。

**12. 08-18 ~ 08-20 的可复用判据只在 CHANGELOG/TODO,没进 LESSONS · 🟠 · 置信度中高**
「PASS ≠ 透明」(TODO:163)·「冻结是看不见的 / 没人报的赠品和没发过长得一样」(TODO:172,CHANGELOG:197)·「headless 套件对 view 全盲,渲染探针是 `_ready` 雷唯一的网」(CHANGELOG:163-167)·「半编译树的红是级联假象,看 SCRIPT ERROR 第一行」与「`\p{Han}` 把「·」算 Hani」(CHANGELOG:135-139)·「守卫要写在形状上,不写在名字上」(trilogy 丢脸,CHANGELOG:21)。每条都去掉日期仍成立。修法:LESSONS 七/工程踩坑表各加一行。

### 🟡 可读性 / 过期计数 / 重复

**13. `LESSONS.md:492-509` + `:518` · 🟡 · 置信度高**
「迁移时最容易丢的四样」先列短版,紧接着「四样的完整版」逐字重复同四条,lambda 捕获坑在 :508 与 :518 表里再出现一次。修法:只留完整版一份,lambda 只留在七节的表里。

**14. `STATUS.md:7 / :18 / :102 / :142` · 🟡 · 置信度高**
「最后更新 08-19」但含 08-20 条目(:187);「回归状态(2026-08-09)」标题下是 08-17 数据;「工具链 41 个文件 / 6777 行」—— `tools/` 现 60 个 .gd/.py/.sh;表里没有 `hundred.gd`(Director 100 关验证)、`rankgen.py`(ranking.json 唯一合法来源)、`tapeserver.py`、`webserve.py`、`probbook.py`、`flow_probe`/`tapeprobe`。修法:日期改 08-20;工具表补上述 7 行(hundred/rankgen 尤其重要,它们是 Director 的仪器)。

**15. `STATUS.md:158-172` 设计文档地图 · 🟡 · 置信度高**
「30 篇 → 20 篇」而 `docs/design/` 现 35 个文件;地图漏 difficulty/numbers/probbook/prior/context/meta/archetypes/taptap/visual,且标 ui_meta「META(前瞻)」—— META 资产循环 08-19 已实装。修法:整节删到一句「目录页 = docs/design/README.md」(那边已经维护着完整表;顺带提醒 docs 评审:README.md:21 同样还写着「均为前瞻,未实施」)。

**16. `STATUS.md:86-96` 数据表 + `CLAUDE.md:246` · 🟡 · 置信度高**
数据表 15 个 JSON 只列 8 个,漏 `tickets/tutorial/director/ranking/assets/lingo/boons`(其中 ranking 是「仪器读数手改无效」、lingo 是「改文案改这里」,新人最需要知道)。CLAUDE.md:246「ui.json stage/hud/shop/hand/banner 五节」—— 实际键为 blindcard/jokercard/stage/hud/shop/hand/tickets/tutor_focus/patterns,无 banner。修法:补 7 行;CLAUDE.md 去掉节名枚举,只说「以 ui.json 顶层键为准」。

**17. `CLAUDE.md:116` + `:265` · 🟡 · 置信度高**
「docs/design/levels.md + docs/design/levels.md 为准」同一路径写两遍(08-18 搬家 sed 残留);`docs/mockups/` 清单漏了 `主角.dc.html / 小丑牌.dc.html / 荣誉.dc.html`。

**18. `CLAUDE.md` 缺最近三天产生的原则 · 🟡 · 置信度中高**
全部去掉数字仍成立,但只散在 CHANGELOG:84-92/117-124 与 TODO:672-674:① 玩家可见文案一律走 `Lingo.t()` / `data/lingo.json`,裸中文字面量 `t_lingo` 直接红;Tape 不走语言层,探针恒 cn;② `ranking.json` 是仪器输出,`rankgen.py` 重刷,手改无效;③ context 四开关只换「哪张脸上场」,不碰目标分/规则/数值/UI;④ META 循环宝石/券双出口,不碰局内金币、不许永久底倍率;⑤ 券不许破解脸规则,`redeal` 不是弃牌(零挂机成长);⑥ 拍长一律取偶数秒(120 BPM 对齐,TODO:102 自己说「该写进设计的约束」)。修法:架构铁律/已拍板规则各加一行。

**19. `TODO.md:41-83 / :114-136 / :201-204 / :682-693` · 🟡 · 置信度高**
1.1 节里「5. 6.」排在「1.-4.」之前;:114-135 音乐选材站点表自己标「已用不上,历史保留」(22 行死内容);:201-204「1.1 音乐(用户自己生成中)」与 :105-112「素材已到库、接线完成」矛盾;:682-693 Director 旧账标题已划掉、正文仍在。全部可删。

**20. CHANGELOG/TODO 内部重复 · 🟡 · 置信度高**
CHANGELOG:463 与 :477 两条都叫「08-13(夜)引擎波次子波 1」,金币单调性哨兵「+0.00 ✓ / −0.00 ❌ 同一个零」在 :465-470 和 :499-506 各讲一遍;TODO 里 `bot_targets` 重锚写了三处(:155 / :301-306 / :314),「sim 读的是另一张表」写了两处(:36-37 / :379-394,LESSONS:65 还有第三份)。修法:CHANGELOG 两条合一;TODO 各留一处。

---

**整体健康度**:CHANGELOG 与 LESSONS 质量高、契约基本守住(LESSONS 条条带「形状 + 判据」);CLAUDE.md 原则部分扎实但**第一屏指针坏了、一条核心经济原则反了**;STATUS 的「增量快照」是准的,但**前 180 行旧文没打标、三条「一眼该知道」全错**;TODO 776 行里真正的待办不到 150 行。新人 15 分钟路径(CLAUDE → STATUS → TODO)目前会被三处绊倒:编号文档找不到 → 「真人数据为零」→ 「第一件事重跑门」。

**最该先修的三件**:① CLAUDE.md:32/100 指针 + :105 金币出口(半小时);② STATUS「三条现状」+ Android 段 + 脸计数(三处都是新人第一眼会信的话);③ CHANGELOG 补 08-16/17 两条 —— 这一步做完,TODO 才有地方搬。

**TODO 压回待办体量的搬家方案**(776 → 约 180 行):
- **→ CHANGELOG(新增两条 08-16 / 08-17)**::140-200 交接 + 14 条 bug 表 + 三条探针盲区;:206-265(1.0 出货 / 「1.0 还差」✅ 列表 / 券使用入口实现账);:268-352 两批账本与分级门;:354-395 08-16 交接(S1 420 的推导保留在 CHANGELOG,「sim 读另一张表」LESSONS 已有)。
- **→ docs/design**::484-586 加分族诊断 + A 案推导 + 14 张期望表 → `jokers.md`(或 `jokers_history.md`);:588-630 牌型倍率全表与顶端三档缺口 → `cards.md`;:88-103 BPM 算术 → `levels.md`/`tech.md`;:746-759 模型成本表 → `capability.md`(LESSONS:237 的指针跟着改)。
- **→ LESSONS**::177-190 七种绿的 #6/#7;:192-197 探针盲区三条;:725-742 sim 抖动压成 3 行(LESSONS:610 已有全文)。
- **→ CLAUDE.md 一行**::15-38「批次纪律」压成 4 行进「命令」节(改动期间不跑 sim/门,用户喊才跑;交付前必过 JSON 校验 + 相关单测 + 截图);:102「拍长偶数秒」。
- **直接删**::114-136 音乐选材表与两个划掉标题;:201-204;:213 划掉标题;:298-316 已 ✅ 的划线项;:682-693;🔴/🟡/🟢 各表里所有 ✅ 行(:405/:407 的 C1、:415-417、:439-440、:449-457、:480、:666-667、:705-707)。
- **留下的待办**:1.1 四件的 ⏳ 残项(语言切换 UI、fontsubset 重跑、端点部署、广告出口)· context/meta 仍在等的四条 · 🔴 表(发挥系数 / 会话数据 / 新手数据 / 3 张插画 / 顶端三档)· 🟡 只剩 M1 · 🟢:清理剩余 ⏳、一轮限定卡复审 + 副歌补偿、和弦/排练改条件或删、N5、tiers 填表、断点续玩、C5/M3/M4/M6、两条仪器债、求解器 S2/S3/S6/S7 · 明确不做表。