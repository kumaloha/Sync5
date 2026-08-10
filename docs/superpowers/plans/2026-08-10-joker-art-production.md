# 60 Joker Art Production Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce all 60 approved Joker central illustrations, full rendered cards, in-run previews, prompt records, and a validated manifest without changing Joker mechanics.

**Architecture:** Treat `assets/jokers/manifest.json` as the art-production source of truth. Generate only the central cyber-tarot subject with ImageGen, derive the runtime-safe wide illustration deterministically, and render frame/text through one browser template so all 60 cards share exact geometry. Keep pending-mechanics Jokers in the art manifest without adding them to `data/jokers.json`.

**Tech Stack:** OpenAI ImageGen, Godot 4.6/GDScript image processing and validation, HTML/CSS, headless Google Chrome, JSON, repository fonts.

---

## File map

- Create `assets/jokers/manifest.json`: 60 immutable art records and display copy.
- Create `assets/jokers/source/joker_<id>.png`: 1024×1024 master subjects.
- Create `assets/jokers/joker_<id>.png`: 1024×400 runtime-safe central art used by `view/joker_slot.gd`.
- Create `assets/jokers/cards/joker_<id>.png`: 1240×1376 complete card renders.
- Create `assets/jokers/previews/joker_<id>.png`: 155×172 acceptance renders.
- Create `assets/jokers/prompts/joker_<id>.json`: exact prompt, source hash, and revision.
- Create `assets/jokers/contact-sheet.png`: visual review sheet for all 60 previews.
- Create `tools/art/build_joker_runtime_art.gd`: converts square masters to non-distorted runtime art.
- Create `tools/art/joker_card_renderer.html`: deterministic frame/text renderer.
- Create `tools/art/render_joker_cards.sh`: renders full cards and previews with Chrome.
- Create `tools/art/verify_joker_assets.gd`: validates IDs, fields, dimensions, and file coverage.
- Create `tools/art/joker_contact_sheet.gd`: renders the 60-card review sheet.
- Modify `assets/design/README.md`: records ownership and output paths.
- Do not modify `data/jokers.json`, `core/`, `view/`, or Joker mechanics in this plan.

### Task 1: Lock the 60-card manifest contract with a failing validator

**Files:**
- Create: `tools/art/verify_joker_assets.gd`

- [ ] **Step 1: Add the immutable ID list and manifest checks**

The validator must use this exact order and reject missing, duplicate, or extra IDs:

```gdscript
const IDS := [
	"twin", "stair", "mono", "triplet", "lonewolf", "kaleido", "shredder", "wrecker",
	"encore", "finale", "turnover", "tipjar", "chord", "neonsign", "vinyl", "chorus",
	"interest", "momentum", "vip", "glowstick", "shortcut", "fourfingers", "twotone",
	"bassline", "mirror", "wildcard", "variation", "reprise", "fullcast", "superfan",
	"opener", "popup", "rainbow", "nopair", "backup", "rehearsal", "trio", "bassclef",
	"warmtone", "cooltone", "undertone", "curtain", "stopwatch", "freeze", "earlyout",
	"crescendo", "segue", "stilllife", "declutter", "stageexit", "doggybag", "royalty",
	"digger", "collector", "doublebill", "sponsor", "skint", "rebrand", "trim", "xray",
]
const REQUIRED := ["id", "cn", "code", "kind", "rarity", "trigger_zh", "amount", "art_subject"]
const VALID_KIND := ["target", "support"]
const VALID_RARITY := ["common", "uncommon", "rare"]
```

For each record, assert exact ID order, non-empty required strings, valid kind/rarity, no placeholder copy, and no line break in `amount`. Exit 1 after printing every error; exit 0 only when all checks pass.

- [ ] **Step 2: Add asset checks without making them optional**

For every ID, load and check:

```gdscript
{
	"source": ["res://assets/jokers/source/joker_%s.png", Vector2i(1024, 1024)],
	"runtime": ["res://assets/jokers/joker_%s.png", Vector2i(1024, 400)],
	"card": ["res://assets/jokers/cards/joker_%s.png", Vector2i(1240, 1376)],
	"preview": ["res://assets/jokers/previews/joker_%s.png", Vector2i(155, 172)],
}
```

Also require `assets/jokers/prompts/joker_<id>.json` to contain the same ID, a non-empty `prompt`, `revision >= 1`, and a 64-character lowercase SHA-256 `source_sha256`.

- [ ] **Step 3: Run the validator and verify RED**

Run:

```bash
godot --headless --path . --script res://tools/art/verify_joker_assets.gd
```

Expected: exit 1 with `missing assets/jokers/manifest.json` before any art is added.

- [ ] **Step 4: Commit the validator**

Commit only `tools/art/verify_joker_assets.gd` using the Lore protocol. Record the expected RED result in `Tested:`.

### Task 2: Author the complete art manifest

**Files:**
- Create: `assets/jokers/manifest.json`

- [ ] **Step 1: Create the manifest with exact top-level structure**

```json
{
  "version": 1,
  "card_size": [1240, 1376],
  "preview_size": [155, 172],
  "runtime_art_size": [1024, 400],
  "cards": []
}
```

- [ ] **Step 2: Enter all 60 records from the frozen production tables**

For the 39 implemented records, preserve gameplay values and use this exact display copy and subject:

| id | trigger_zh | amount | art_subject |
|---|---|---|---|
| twin | 对子或两对 | ×6 | 一对镜像舞者 |
| stair | 顺子或同花顺 | ×10 | 通往聚光灯的霓虹台阶 |
| mono | 同花或同花顺 | ×7 | 单色灯光淹没的舞台 |
| triplet | 三条、葫芦或四条 | ×5 | 三个重叠音符组成三人和声 |
| lonewolf | 本拍零弃牌；目标牌必定出现 | +3◆ | 独自站在麦克风前的狼 |
| kaleido | 与上一拍不同的成牌 | ×4 | 万花筒中不断变形的牌面 |
| shredder | 提前完成且为成牌 | ×4 | 吉他速弹与指尖残影 |
| encore | 与上一拍相同牌型 | +80 | 返场呼喊形成回声的观众席 |
| finale | 最后两秒行动 | +70 | 最后一秒爆开的谢幕烟花 |
| turnover | 本拍每次弃牌 | +20 | 飞速换牌的一双手 |
| tipjar | 本拍零弃牌 | +2◆ | 塞满硬币的玻璃小费罐 |
| chord | 缓存全为同一花色 | +120 | 三根同色发光琴弦 |
| neonsign | 始终生效 | +80 | 一块纯粹的霓虹招牌 |
| vinyl | 每次弃牌后永久 | +3 | 唱针下旋转的黑胶纹路 |
| chorus | 本节最后一拍 | +75% | 全场合唱的高潮声浪 |
| interest | 每持有四枚金币 | +1◆ | 一枚硬币生出小硬币 |
| momentum | 每次提前完成后永久 | +10% | 越滚越快的节拍飞轮 |
| vip | 人头牌点数 | 15 | 贵宾席上的 J、Q、K |
| glowstick | 初始加成，每拍衰减 6% | +60% | 逐拍变暗的荧光棒 |
| shortcut | 顺子可以跳过一级 | RULE | 跨过断层的捷径台阶 |
| fourfingers | 四张牌也算顺子 | RULE | 一只清楚可数的四指手套 |
| twotone | 同色即可组成同花 | RULE | 半红半黑的双色舞台灯 |
| bassline | 每累计十二次弃牌后永久 | ×0.25 | 重复震动的低音贝斯线 |
| mirror | 复制目标牌效果 | ×50% | 一面映出另一张牌的镜子 |
| wildcard | 两张万能牌加入牌库 | +2 | 大小王从牌堆中探出 |
| variation | 与上一拍不同牌型 | +50 | 同一旋律的两种写法 |
| reprise | 与上一拍相同牌型 | +50% | 重复出现的乐句记号 |
| fullcast | 五张牌组成的牌型 | +150 | 五人全员站在谢幕线上 |
| superfan | 每持有两枚金币 | +5% | 攥着钱包尖叫的铁杆粉丝 |
| opener | 本节第一拍 | +80% | 拉开大幕后射入第一束光 |
| popup | 仅第一节 | +200 | 一张突然点亮的快闪海报 |
| rainbow | 手牌包含四种花色 | +150 | 四色灯同时打向舞台 |
| nopair | 手牌没有对子 | +60 | 五张互不相认的牌 |
| backup | 缓存全为人头牌 | +150 | 三张人头牌组成伴唱 |
| rehearsal | 缓存形成连续点数 | +150 | 候场牌排成连续队列 |
| bassclef | 低点数牌按此点数计算 | 10 | 放大的低音谱号托起小牌 |
| warmtone | 每张参与计分的红色牌 | +6 | 红桃与方块沐浴暖光 |
| cooltone | 每张参与计分的黑色牌 | +6 | 黑桃与梅花浸在冷光中 |
| undertone | 每张参与计分的五及以下牌 | +9 | 小点数牌组成低声部合唱 |

Use `data/jokers.json` for their exact `cn/kind/rarity`. Then add the following exact 21 art-only records. Do not add these 21 to gameplay data.

| id | cn | kind / rarity | trigger_zh | amount | art_subject |
|---|---|---|---|---|---|
| wrecker | 拆迁 | target / rare | 本拍弃牌三次后，成牌 | ×3.5 | 铁球砸穿一堵扑克牌墙 |
| trio | 三重唱 | support / common | 缓存三张同点数牌 | +200 | 三张同点数牌并肩合唱 |
| curtain | 谢幕 | support / uncommon | 最后一秒行动 | +60% | 幕布落下前的最后一躬 |
| stopwatch | 秒表 | support / uncommon | 结算时每剩余一秒 | +8% | 停在剩余秒数上的机械秒表 |
| freeze | 定格 | support / uncommon | 提前完成后，下一拍 | +30% | 定格舞姿投影进下一段时间切片 |
| earlyout | 早弃 | support / common | 所有弃牌都在前四秒 | +80 | 开场灯亮前飞出的扑克牌 |
| crescendo | 渐强 | support / common | 超过上一拍得分 | +60 | 渐强记号推高一堵音浪 |
| segue | 串场 | support / common | 换入且参与成牌的每张牌 | +40 | 扑克牌从候场滑入聚光灯 |
| stilllife | 静物 | support / common | 本拍零交换 | +60 | 三张缓存牌纹丝不动地陈列 |
| declutter | 断舍离 | support / uncommon | 一次弃掉五张牌 | +50% | 一只手把整手牌一次撒出 |
| stageexit | 让位 | support / common | 每张被弃的人头牌 | +30 | J、Q、K 鞠躬离开舞台 |
| doggybag | 打包 | support / common | 得分达到目标两倍 | +3◆ | 溢出分数被装进发光外带袋 |
| royalty | 分成 | support / uncommon | 牌型金币奖励 | ×2 | 唱片分成支票分裂成两份 |
| digger | 淘碟 | support / uncommon | 每次刷新后永久 | +12 | 一只手在黑胶唱片堆中淘碟 |
| collector | 收藏家 | support / uncommon | 每购买一张牌后永久 | +15 | 一整面墙陈列收藏卡 |
| doublebill | 联票 | support / rare | 商店展示四张，可购买两张 | RULE | 一张撕线票根连接两场演出 |
| sponsor | 赞助 | support / uncommon | 商店牌价格 | −1◆ | 赞助横幅压下一枚价格标签 |
| skint | 穷开心 | support / rare | 金币上限五枚 | ×1.3 | 空口袋的人在霓虹雨中大笑 |
| rebrand | 转型 | support / uncommon | 每次更换目标牌后永久 | +40% | 撕掉旧海报露出新的流派旗帜 |
| trim | 修剪 | support / rare | 2 和 3 离开牌库 | RULE | 霓虹修枝剪剪断数字 2 与 3 |
| xray | 透牌 | support / uncommon | 预览下一张补牌 | INFO | 荧光透视屏显出下一张牌轮廓 |

- [ ] **Step 3: Assign deterministic display codes**

Use `T-01` through `T-08` for the first eight Target records and `S-01` through `S-52` for Support records in manifest order. Store the result in each record's `code` field.

- [ ] **Step 4: Run manifest-only validation**

Run the validator. Expected: exactly 60 manifest records pass; the command remains RED only because image files and prompt records do not exist.

- [ ] **Step 5: Commit the manifest**

Commit only `assets/jokers/manifest.json`. `Tested:` must state `60 unique IDs; manifest fields pass; assets intentionally absent`.

### Task 3: Build deterministic runtime and full-card renderers

**Files:**
- Create: `tools/art/build_joker_runtime_art.gd`
- Create: `tools/art/joker_card_renderer.html`
- Create: `tools/art/render_joker_cards.sh`

- [ ] **Step 1: Implement the runtime-art converter**

For each 1024×1024 source, create a transparent 1024×400 image, resize the source to at most 400×400 with Lanczos filtering, and center it without stretching. Save it to `assets/jokers/joker_<id>.png`. Reject a missing source or a source containing no non-transparent pixel. Accept `--id=<id>` for a single card and `--ids=<comma-separated IDs>` for a batch; no argument means all 60.

Run:

```bash
godot --headless --path . --script res://tools/art/build_joker_runtime_art.gd
```

Expected before generation: exit 1 listing 60 missing source images.

- [ ] **Step 2: Implement one-card HTML rendering**

`joker_card_renderer.html` must read `?id=<id>&scale=<1|8>`, fetch the manifest, and render exactly one card. Use these base-pixel layout constants multiplied by `scale`:

```javascript
const layout = {
  width: 155, height: 172, radius: 14, outerPad: 6,
  headerHeight: 35, artHeight: 74, descriptionHeight: 61,
  nameSize: 18, amountSize: 17, effectSize: 14,
  frame: '#36f2e3', targetHot: '#ff4f9d',
  rarity: {common:'#36f2e3', uncommon:'#9e74ff', rare:'#ffd453'}
};
```

The outer frame is always cyan. Rarity affects only the top-right code mark, amount chip, and a small art glow. Render `cn`, `amount`, and `trigger_zh`; never render generated text from the image.

- [ ] **Step 3: Implement the batch render shell script**

The script must:

1. resolve the repository root from its own path;
2. launch `python3 -m http.server 61355 --bind 127.0.0.1` at the root;
3. wait for `http://127.0.0.1:61355/assets/jokers/manifest.json`;
4. iterate `jq -r '.cards[].id' assets/jokers/manifest.json`;
5. use `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --headless=new --hide-scrollbars --disable-gpu`;
6. render 1240×1376 at `scale=8` and 155×172 at `scale=1`;
7. accept one positional argument containing `all`, one ID, or a comma-separated ID list;
8. stop the server through a shell trap even on failure.

- [ ] **Step 4: Smoke-test with one temporary source**

Copy one existing approved Joker reference to `assets/jokers/source/joker_twin.png`, run both builders for `twin`, and verify the four expected sizes. Remove the temporary source and derived files before committing tooling.

- [ ] **Step 5: Commit renderer tooling**

Commit the three files with the Lore protocol. Do not commit the temporary smoke-test image.

### Task 4: Generate Batch A — eight Targets and seven core Supports

**Files:**
- Create 15 source images and 15 prompt records for manifest positions 1–15.

- [ ] **Step 1: Read the ImageGen skill and use the approved visual reference**

Use `assets/design/joker_blind_visual_system.html` and the approved Style C card preview as composition references. ImageGen produces only the central subject, not the card frame.

- [ ] **Step 2: Generate each source with the exact shared prompt contract**

```text
Create one isolated cyber-tarot mechanism totem for the Sync5 Joker card “{cn}”.
Subject: {art_subject}.
Original cyberpunk nightclub illustration; dark glass, cyan neon edge light, one small {rarity_accent} hotspot, strong readable silhouette, hard graphic shapes, centered within a square safe area, designed to remain recognizable inside a 145×50 game window.
One main subject and at most one supporting object. No complete scene, no people unless the subject explicitly requires one, no card border, no title, no numbers, no letters, no logo, no watermark. Transparent background.
```

Generate each ID separately. Copy the accepted result to `assets/jokers/source/joker_<id>.png`, normalize to 1024×1024, and write the exact prompt/revision/source hash to its prompt JSON.

- [ ] **Step 3: Derive runtime art, cards, and previews**

Run both builders with the comma-separated IDs for positions 1–15. Inspect all 15 at 155×172 before accepting the batch.

- [ ] **Step 4: Commit Batch A**

Commit only the 75 files belonging to these 15 cards: source, runtime, card, preview, and prompt.

### Task 5: Generate Batch B — manifest positions 16–30

**Files:**
- Create 15 source images and 15 prompt records for manifest positions 16–30.

- [ ] **Step 1: Generate each source with the locked prompt**

```text
Create one isolated cyber-tarot mechanism totem for the Sync5 Joker card “{cn}”.
Subject: {art_subject}.
Original cyberpunk nightclub illustration; dark glass, cyan neon edge light, one small {rarity_accent} hotspot, strong readable silhouette, hard graphic shapes, centered within a square safe area, designed to remain recognizable inside a 145×50 game window.
One main subject and at most one supporting object. No complete scene, no people unless the subject explicitly requires one, no card border, no title, no numbers, no letters, no logo, no watermark. Transparent background.
```

Generate every ID separately and write its prompt/revision/source hash record. Reject any subject that duplicates a Batch A silhouette or contains text.

- [ ] **Step 2: Build and inspect the batch**

Run both builders with the comma-separated IDs for positions 16–30. Inspect all 15 previews at 155×172 and reject any card that becomes illegible.

- [ ] **Step 3: Commit Batch B**

Commit the 75 source/runtime/card/preview/prompt files only after all 15 previews pass.

### Task 6: Generate Batch C — manifest positions 31–45

**Files:**
- Create 15 source images and 15 prompt records for manifest positions 31–45.

- [ ] **Step 1: Generate each source with the locked prompt**

```text
Create one isolated cyber-tarot mechanism totem for the Sync5 Joker card “{cn}”.
Subject: {art_subject}.
Original cyberpunk nightclub illustration; dark glass, cyan neon edge light, one small {rarity_accent} hotspot, strong readable silhouette, hard graphic shapes, centered within a square safe area, designed to remain recognizable inside a 145×50 game window.
One main subject and at most one supporting object. No complete scene, no people unless the subject explicitly requires one, no card border, no title, no numbers, no letters, no logo, no watermark. Transparent background.
```

Generate every ID separately and write its prompt/revision/source hash record. For `trio`, `curtain`, `stopwatch`, and `freeze`, the prop must communicate the trigger without the title.

- [ ] **Step 2: Build and inspect the batch**

Run both builders with the comma-separated IDs for positions 31–45 and inspect all previews at 155×172.

- [ ] **Step 3: Commit Batch C**

Commit the 75 source/runtime/card/preview/prompt files only after all 15 previews pass.

### Task 7: Generate Batch D — manifest positions 46–60

**Files:**
- Create 15 source images and 15 prompt records for manifest positions 46–60.

- [ ] **Step 1: Generate each source with the locked prompt**

```text
Create one isolated cyber-tarot mechanism totem for the Sync5 Joker card “{cn}”.
Subject: {art_subject}.
Original cyberpunk nightclub illustration; dark glass, cyan neon edge light, one small {rarity_accent} hotspot, strong readable silhouette, hard graphic shapes, centered within a square safe area, designed to remain recognizable inside a 145×50 game window.
One main subject and at most one supporting object. No complete scene, no people unless the subject explicitly requires one, no card border, no title, no numbers, no letters, no logo, no watermark. Transparent background.
```

Generate every ID separately and write its prompt/revision/source hash record. For `doublebill`, `skint`, `trim`, and `xray`, use one symbolic machine or prop instead of a narrative scene.

- [ ] **Step 2: Build and inspect the batch**

Run both builders with the comma-separated IDs for positions 46–60 and inspect all previews at 155×172.

- [ ] **Step 3: Commit Batch D**

Commit the 75 source/runtime/card/preview/prompt files only after all 15 previews pass.

### Task 8: Build the final contact sheet and verify the complete deck

**Files:**
- Create: `tools/art/joker_contact_sheet.gd`
- Create: `assets/jokers/contact-sheet.png`
- Modify: `assets/design/README.md`

- [ ] **Step 1: Render a 10×6 preview sheet**

Create a 1610×1122 transparent/dark contact sheet with 10 columns, 6 rows, 6px horizontal gap, and 14px vertical gap. Place each 155×172 preview in manifest order and save to `assets/jokers/contact-sheet.png`.

- [ ] **Step 2: Run all automated checks**

```bash
godot --headless --path . --script res://tools/art/verify_joker_assets.gd
godot --headless --path . --editor --quit
godot --headless --path . --script res://tests/runner.gd
git diff --check
```

Expected: 60 manifest records, 300 per-card files across five categories, all dimensions exact, zero duplicate/extra IDs, project import succeeds, and existing gameplay tests remain green.

- [ ] **Step 3: Perform visual acceptance at real size**

Inspect the contact sheet at 100% scale. Confirm every Chinese title and trigger is readable, every card is cyan-first, rarity accents stay secondary, and no pair of cards shares the same central silhouette.

- [ ] **Step 4: Document ownership and commit**

Add the manifest, directory meanings, regeneration commands, and the rule that `assets/jokers/joker_<id>.png` is central art—not a full card—to `assets/design/README.md`. Commit the contact sheet, tool, and README update with the Lore protocol.
