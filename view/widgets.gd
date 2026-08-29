class_name Widgets
extends RefCounted

## Small self-contained neon widgets (docs/design/tech.md view split). Moved verbatim
## from view/phrase.gd's tail — behavior identical, referenced as
## Widgets.GradBar / Widgets.SegPill / Widgets.DJKey.


## 高亮区的形状 —— 光层 / 压暗层 / 提亮层**必须共用这一份**(2026-08-18)。
## 上一版光会画圆、暗只会挖方:圆形光晕外面套一圈没被压暗的方角,
## 正是用户报的「包了一层形状不对的光晕」。**形状一旦有两份就必然再岔开。**
## 判据:近正方形(长宽比 <1.3)= 圆钮(弃牌/理牌的 DJ 键)⇒ 按整圆;长条区域 ⇒ 固定圆角。
static func focus_radius(q: Rect2) -> float:
	# 圆形分支只给**小方件**(理牌/弃牌那对 ~108px 圆键)——判据带尺寸上限:
	# 2026-08-24 用户点名「区域是长方形, 灯光打过去是个圆」:教学常亮洞 720×608
	# 长宽比 1.18 也落进旧判据, 被挖成 304px 圆角的怪圆。大块区域一律方洞(18px 圆角)。
	var ratio := maxf(q.size.x, q.size.y) / maxf(1.0, minf(q.size.x, q.size.y))
	if ratio < 1.3 and minf(q.size.x, q.size.y) <= 160.0:
		return minf(q.size.x, q.size.y) * 0.5
	return 18.0


## ---- 教学文案的 {} 双色拼段(v6)----
## `{...}` = 这一句的高亮段(db 校验:至多一个)。返回 [{"t": 文本, "hi": bool}]。
static func hint_parts(s: String) -> Array:
	var out: Array = []
	var rest := s
	while true:
		var a := rest.find("{")
		if a < 0:
			break
		var b := rest.find("}", a + 1)
		if b < 0:
			break
		if a > 0:
			out.append({"t": rest.substr(0, a), "hi": false})
		out.append({"t": rest.substr(a + 1, b - a - 1), "hi": true})
		rest = rest.substr(b + 1)
	if rest != "":
		out.append({"t": rest, "hi": false})
	return out


## 高亮段的颜色:钱的话题(◆ / 免费 / free, en 表值走后者)→ 金, 其余概念 → 青。
static func hint_hue(seg: String) -> Color:
	if seg.find("◆") != -1 or seg.find("免费") != -1 or seg.to_lower().find("free") != -1:
		return StageTheme.GOLD
	return StageTheme.CYAN


## 提示条的公共画法 —— TutorHint 与 γ 公示卡(view/intro.gd)共用这一份:
## 暗玻璃底 + 青描边 + {} 双色拼段;`en` 空串就不画右侧短标。
## ⚠ 中文走 StageTheme.zh()(系统中文), 拉丁走 Rajdhani —— 混用会让中文掉进
## fallback 字形(「数字对了形态错了」的典型形状)。
static func draw_hint_bar(ci: CanvasItem, r: Rect2, cn: String, en: String) -> void:
	ci.draw_style_box(StageTheme.box(Color(0.02, 0.03, 0.08, 0.88),
		Color(StageTheme.CYAN.r, StageTheme.CYAN.g, StageTheme.CYAN.b, 0.55), 1, 8), r)
	var fs := 20
	var x := r.position.x + 14.0
	var base_y := r.get_center().y + fs * 0.36
	# ⚠ 正文是**白墨**不是青 —— 高亮段(青/金)要跳出来, 底色必须让位;
	# 旧版整句青, {} 双色里的青段会隐形(截图对账抓到的)。
	for seg in hint_parts(cn):
		var txt := String(seg["t"])
		if txt == "":
			continue
		var col: Color = hint_hue(txt) if bool(seg["hi"]) else Color(0.87, 0.91, 1.0, 0.92)
		ci.draw_string(StageTheme.zh(), Vector2(x, base_y), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		x += StageTheme.zh().get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if en != "":
		# ⚠ 右对齐时 position 是**盒子左边**、width 定盒宽 —— 传 0 宽度会退成左对齐。
		ci.draw_string(StageTheme.num("Medium"), Vector2(r.position.x, r.get_center().y + 5), en,
			HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 12, 13, Color(1, 1, 1, 0.42))


## 教学关的一行提示(docs/design/difficulty.md §4.4)。
##
## ⚑ 契约是**不打断**:不暂停、不弹窗、不需要点确认 —— 因为「8 秒是唯一闸门」,
## 第一次体验若是暂停态, 真正开始时的手忙脚乱会加倍。
## ⚠ 它**只在教学关出现**;正式局 `set_hint("", "")` 就整块隐身, 不占位、不画。
## 语言沿用全屏那套:暗玻璃底 + 主色描边 + 外发光(CLAUDE.md 美术方向)。
class TutorHint:
	extends Control
	var _cn := ""
	var _en := ""
	## 这一步指向的区域矩形(全屏坐标)。⚑ 「说」和「指」是同一件事的两半 ——
	## 拆开会让「文案换了但高亮没跟着换」变成一种可能, 而那正是第一版的毛病(光说不指)。
	## ⚠ **所以哪怕光挪到了 TutorGlow 那一层, 入口仍然只有 `set_hint` 这一个** ——
	## 拆的是**画在哪一层**, 不是**谁来决定指哪**。glow 由本部件转发, 调用方感知不到它。
	var _focus: Array = []
	## 画在手牌/缓存**下面**的光、内容**上面**的暗、暗之上的加法**提亮**(`Layout.build` 塞进来)。
	## 都可以是 null(测试/探针)。⚑ 四层由本部件统一转发 ⇒ 调用方仍然只有 `set_hint` 一个口。
	var glow = null
	var dim = null
	var light = null
	## 提示条要躲开的矩形(全部可高亮区域)。空 = 不躲(旧行为)。
	var _avoid: Array = []
	## 压暗层的**常亮洞**(2026-08-24 用户:「倒计时边框也应该在教学的时候被看到」
	## 「展示小丑牌的时候下方整个版面是黑的」):这些矩形只是**不压暗**, 不吃提亮、
	## 不吃光圈、不参与提示条定位 —— 它们不是「这一步指向哪」, 是「永远不许黑」。
	var _holes: Array = []
	## 分镜的条锚位(v6):>= 0 就把条钉在这个 y 上, 跳过「贴高亮区 + 躲避」的自动逻辑 ——
	## 分镜 = 高光构图 + **文字条锚位**, 同 shot 两拍条不动(镜头不跳)。-1 = 走自动。
	var _anchor_y := -1.0
	## 次级强调(光斑)的目标矩形(v6):转发给提亮层画小半径柔光圈, 不动条与 focus。
	var _spot := Rect2()

	## ⚠ 本部件铺满全屏, 所以**必须** MOUSE_FILTER_IGNORE, 否则整屏点不动。
	func set_hint(cn: String, en: String, focus: Array = [], avoid: Array = [],
			holes: Array = [], anchor_y: float = -1.0, spot: Rect2 = Rect2()) -> void:
		_avoid = avoid
		if cn == _cn and en == _en and focus == _focus and holes == _holes \
				and anchor_y == _anchor_y and spot == _spot:
			return                      # 每拍都会被调, 不变就别重画
		_cn = cn
		_en = en
		_focus = focus
		_holes = holes
		_anchor_y = anchor_y
		_spot = spot
		visible = cn != ""
		if glow != null:
			glow.set_focus(focus if cn != "" else [])
		if dim != null:
			dim.set_focus((focus + holes) if cn != "" else [])
		if light != null:
			light.set_focus(focus if cn != "" else [])
			light.set_spot(spot if cn != "" else Rect2())
		queue_redraw()

	## 提示条**跟着高亮区走**(2026-08-16 用户:「教学描述放在高亮区附近」)——
	## 说的和指的挨在一起, 眼睛不用在屏幕两头来回找。
	##
	## ⚠ 这是**绝对坐标**(本部件铺满全屏)。`BAR` 只保留 x/宽/高;y 由 `_bar_rect()` 按
	## 这一步的高亮区算。没有高亮区时退回 384 —— 那个数是截图逐版调出来的
	## (y=96 压进顶栏 / y=132 盖住「♪ 小丑牌 ♪」/ y=384 落在小丑牌槽位下沿与音浪层上沿的空带)。
	const BAR := Rect2(26, 384, 668, 40)
	const BAR_GAP := 12.0

	## 条贴在高亮区的**上方**;顶上放不下就翻到**下方**。
	## ⚠ 多块高亮区时取**并集**(第 6 步同时指手牌 + 缓存)—— 贴着其中一块会把另一块甩下。
	## ⚑ v6:分镜给了显式锚位(_anchor_y ≥ 0)就直接钉死 —— 同 shot 两拍条不动。
	func _bar_rect() -> Rect2:
		if _anchor_y >= 0.0:
			return Rect2(BAR.position.x,
				clampf(_anchor_y, 60.0, 1280.0 - BAR.size.y - 16.0), BAR.size.x, BAR.size.y)
		if _focus.is_empty():
			return BAR
		var top := INF
		var bottom := -INF
		for r in _focus:
			top = minf(top, (r as Rect2).position.y)
			bottom = maxf(bottom, (r as Rect2).end.y)
		var y := top - BAR_GAP - BAR.size.y
		if y < 60.0:                       # 顶上放不下(会压进顶栏)⇒ 翻到区域下方
			y = bottom + BAR_GAP
		# ⚑⚑ **再往上躲开所有可高亮区域**(2026-08-16 第二版)。
		# 第一版只做「贴着高亮区上方」, 于是指弃牌键(右下角 108×108)那两步,
		# 条落在 y=1004 —— 正好压住「缓存区」标签和卡片顶沿。**屏幕下半部被
		# 手牌/缓存/弃牌三块占满, 那里根本没有空带**, 硬贴必然压住东西。
		# ⇒ 撞上谁就挪到谁的上方, 迭代到不撞为止。对底部那几步, 结果是落在
		# 手牌行上沿的空带(≈620)—— **离得远一点, 但不压字**。
		# ⚑ 这在有了压暗层之后才成立:高亮区被单独照亮、其余压暗, 所以
		# 「说的」和「指的」不必物理挨着也不会认错 —— **对比度接管了邻近性**。
		# ⚠ `_avoid` 由编排器喂(全部四块区域的真实矩形), 空数组时退回旧行为。
		for _pass in range(4):             # 有界迭代:四块区域, 最多躲四次
			var hit := false
			for a in _avoid:
				var q: Rect2 = a as Rect2
				var bar := Rect2(BAR.position.x, y, BAR.size.x, BAR.size.y)
				if bar.intersects(q.grow(BAR_GAP)):
					y = q.position.y - BAR_GAP - BAR.size.y
					hit = true
			if not hit:
				break
		y = clampf(y, 60.0, 1280.0 - BAR.size.y - 16.0)
		return Rect2(BAR.position.x, y, BAR.size.x, BAR.size.y)

	func _draw() -> void:
		if _cn == "":
			return
		# ⚑ 「指」已经不在这一层了 —— 高亮走 `TutorGlow`, 它画在**手牌/缓存的下面**。
		# 理由见 TutorGlow 的文件头:在最上层加光必然盖住卡面、把花色染掉。
		# 画法(玻璃条 + {} 双色拼段)与 γ 公示卡共用 `Widgets.draw_hint_bar` 这一份。
		Widgets.draw_hint_bar(self, _bar_rect(), _cn, _en)


## 教学关的**区域高亮** —— 打光, 不画框(2026-08-16 用户拍板:「需要操作的和需要注意的,
## 打高亮, 不要画框」)。
##
## ⚑ **为什么高亮比描边对**:描边是**边界**语言, 说的是「这块到那块为止」;
## 而这里要说的是「**看这儿**」—— 那是**注意力**语言。何况这个界面里描边已经被占满了
## (手牌区/缓存区/顶栏/每张卡各自都有主色描边), 再套一圈只是**又多一个框**, 跳不出来。
## ⚑ 打光还正好是这套美术的母语 —— **霓虹舞台**上「看这儿」的自然写法就是**一束追光**。
##
## ⚠⚠⚠ **它必须画在手牌/缓存的下面, 这不是风格选择, 是硬约束。**
## `Layout.build()` 把它 add 在 `hud`/`hand` **之前**(add_child 的顺序 = 画的顺序)。
## 起因:第一版把光画在 TutorHint 那一层(铺满全屏、最上层), 结果 ——
##   · 铺 0.13 的青 ⇒ 缓存区的 ♥♦ 从 `#ff6aa9` **变成灰紫**;
##   · 改成「零填充 + 大外发光」⇒ StyleBoxFlat 的阴影是**填充**的扩张矩形,
##     bg 全透就直接透出来, 整块糊成一片青, 比上一版更糟。
## ⇒ **在最上层做不出「不染色的高亮」**。而放到下面就天然成立:面板底是**半透黑**
## (CLAUDE.md 那条), 光从后面透上来, 卡面画在更上层, **花色一个像素不动**。
## ⚠ 这两版都是「改了视觉就渲染出来自己看」当场抓到的, 靠想象一个都发现不了。
##
## ⚠ **仍然不做遮罩/压暗** —— 那要全屏铺半透黑, 而 CLAUDE.md 拍死「画面里的光全部由
## 光效层承担, 底色不贡献亮度」。**加光, 不减光。**
class TutorGlow:
	extends Control
	var _focus: Array = []

	## ⚠ 入参是 **`Rect2` 的数组**(2026-08-16 从 `[x,y,w,h]` 四元数组改过来)——
	## 现在矩形由 `Hand.focus_rect()` 从活部件算, 不再从 `ui.json` 抄。
	func set_focus(focus: Array) -> void:
		if focus == _focus:
			return
		_focus = focus
		visible = not focus.is_empty()
		queue_redraw()

	## ⚑ **白光, 不用主色**(2026-08-16 用户:「高光的颜色你改一下, 现在太艳了,
	## 白色高光就好啦」)。青色是**语义色** —— 这一屏的青已经被顶栏、手牌框、理牌键占着,
	## 再拿它当追光等于在一堆青里再加一块青, **艳而不显**。白是这套配色里唯一没被占用的,
	## 所以它反而最跳。⚠ **白在同 alpha 下比任何主色都亮**, 所以数值要压低(0.22 → 0.10)。
	func _draw() -> void:
		# ⚑⚑ **第三版:什么都不画**(2026-08-18 用户两次报「模糊」后)。
		# 前两版都在用「柔光」做亮 —— 软洗光垫在半透明面板**后面**, 物理上就是雾:
		# 白光透过暗玻璃 = 灰蒙蒙的一层, 收多紧都是雾。撤掉之后高亮区的内容
		# **一个像素不被碰** = 能达到的最大清晰度;「亮」由 TutorDim 的对比 +
		# 洞边一条锐利的光圈线承担(见 TutorDim._rim)。
		# 类和接线都留着:形状语言若再变(比如想给某步单独加光), 口子还在。
		pass


## 教学关的**压暗层** —— 高亮区之外整屏压暗(2026-08-16 用户:「高光打起来的时候,
## 其他部分要暗一点」)。
##
## ⚠⚠ **这一条显式推翻了 CLAUDE.md 的「不做遮罩/压暗」。** 那条原话是「画面里的光全部由
## 光效层承担, 底色不贡献亮度」, 我据此在上一版**拒绝过压暗** —— 用户直接指令优先, 已照改。
## ⚑ 而且它有独立理由:**只加光不减光时对比度不够** —— 这一屏本来就到处是霓虹, 光加在
## 一片亮里读不出来。**压暗提供的是对比, 不是亮度**, 与那条原则并不真冲突。
##
## ⚠ **它必须画在内容之上**(与 `TutorGlow` 正相反, glow 在下、dim 在上)——
## 要暗的是**卡面本身**, 画在下面等于什么都没暗到。
## ⚠ **挖洞用四条边带, 不是画个洞**:Canvas 没有便宜的「反向裁剪」, 所以在高亮区
## 上/下/左/右各铺一条暗带, 中间那块自然留空。多块高亮时取**并集**(第 6 步同时指
## 手牌 + 缓存)—— 逐块挖会在两块之间留下一条没被暗到的缝。
class TutorDim:
	extends Control
	## ⚠ 0.46 → 0.38:压暗是**对比手段**不是主角。太重会让「被指的那块」显得更暗
	## (2026-08-17 用户报的)—— 光是加法, 暗只是背景, 两者一起调才对。
	## 0.38 → 0.50 → **0.85**(2026-08-18 第六版, 用户对零白色的 v5 仍报「朦胧」后):
	## 最后一层雾就是压暗自己 —— **半透明的黑罩在霓虹上照样读作「蒙了一层」**。
	## 真正的舞台关灯不是半透明, 是近全黑:其余区域退成剪影, 聚光区因此锋利。
	## 判据补全:教学高亮层不许画任何非黑色, 而黑也必须黑到**不读作一层膜**。
	const ALPHA := 0.85
	var _focus: Array = []

	func set_focus(focus: Array) -> void:
		if focus == _focus:
			return
		_focus = focus
		visible = not focus.is_empty()
		queue_redraw()

	## 洞比高亮区放宽这么多, 免得暗带压住 glow 的外溢辉光(压住会画出一条硬边 = 又变成框)。
	const HOLE_GROW := 14.0

	## ⚑⚑ **逐块挖形状洞**(2026-08-18 重写, 用户:「有时候包了一层形状不对的光晕, 怪」)。
	## 旧版两个毛病同一个根:洞和光的形状是两套逻辑 ——
	## ① 洞永远是矩形:圆形光晕(弃牌键)外面套一圈没被压暗的**方角**;
	## ② 多块高亮取**并集**挖一个大洞:手牌与缓存**之间的空当**也跟着亮, 又一圈怪形状。
	## 现在:每块一个洞, 形状走共用的 `Widgets.focus_radius`(圆就挖圆洞),
	## 圆角处用「反向圆角补片」把方洞的四个角补成暗的。
	## ⚠ 洞与洞横向重叠时退回并集(补片会互相涂进对方的洞里);现役四块区域都是纵向排布,
	## 这个分支只是兜底, 真走到了宁可形状糙也不能把该亮的压暗。
	func _draw() -> void:
		if _focus.is_empty():
			return
		var d := Color(0, 0, 0, ALPHA)
		var w := 720.0
		var h := 1280.0
		var holes: Array[Rect2] = []
		for rect in _focus:
			holes.append((rect as Rect2).grow(HOLE_GROW))
		holes.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.y < b.position.y)
		for i in range(holes.size() - 1):          # 纵向重叠 ⇒ 并掉, 保证带状分解成立
			if holes[i].end.y > holes[i + 1].position.y:
				holes[i + 1] = holes[i].merge(holes[i + 1])
				holes[i] = Rect2()
		var live: Array[Rect2] = []
		for q in holes:
			if q.size.y > 0.0:
				live.append(q)
		# 横向带状分解:洞外的每一横带整幅铺暗, 洞所在的竖向区间只铺左右两侧
		var y := 0.0
		for q in live:
			if q.position.y > y:
				draw_rect(Rect2(0, y, w, q.position.y - y), d)
			draw_rect(Rect2(0, q.position.y, maxf(0.0, q.position.x), q.size.y), d)
			draw_rect(Rect2(q.end.x, q.position.y, maxf(0.0, w - q.end.x), q.size.y), d)
			_corner_patches(q, d)
			y = q.end.y
		if y < h:
			draw_rect(Rect2(0, y, w, h - y), d)

	## ⚑⚑ 第五版 = **纯对比, 零白色**(2026-08-18 用户第三次报「朦胧/模糊」后终于听懂):
	## v1/v2 柔光、v3 光圈、v4 光锥 —— 四版的共同点是**都往画面上叠半透明的白**,
	## 而白色叠在内容上就是雾, 无论把它叫什么。追光的「感觉」不需要画光:
	## **其余压暗 + 该操作的区域一个像素不动**, 对比本身就是打光。
	## 判据从此一句话:**教学高亮层不许画任何非黑色。**


	## 反向圆角补片:洞是按矩形留空的, 四个角要按共用形状补回暗色 ——
	## 「角方光圆」正是旧版那圈怪光晕的形状来源。
	## (定义先于使用即可, 放在 _draw 后面只为让主路径先读到。)
	func _corner_patches(q: Rect2, d: Color) -> void:
		var r: float = minf(Widgets.focus_radius(q.grow(-HOLE_GROW)) + HOLE_GROW,
			minf(q.size.x, q.size.y) * 0.5)
		if r < 2.0:
			return
		const SEGS := 12
		for c in range(4):
			var corner := Vector2(
				q.position.x if c % 2 == 0 else q.end.x,
				q.position.y if c < 2 else q.end.y)
			var center := corner + Vector2(r if c % 2 == 0 else -r, r if c < 2 else -r)
			var pts := PackedVector2Array([corner])
			for s in range(SEGS + 1):
				var ang := TAU * 0.25 * float(s) / float(SEGS)
				# 从「贴着角的水平边」转到「贴着角的竖直边」, 方向随象限翻转
				var off := Vector2(cos(ang), sin(ang)) * r
				off.x *= -1.0 if c % 2 == 0 else 1.0
				off.y *= -1.0 if c < 2 else 1.0
				pts.append(center + off)
			draw_colored_polygon(pts, d)


## 教学高亮的**提亮层**(2026-08-18, 用户:「其实是需要操作的区域提亮, 其他地方变暗」)。
##
## ⚑ **加法混合(BLEND_MODE_ADD), 画在内容之上** —— 这是唯一能把**不透明小件**
## (弃牌键)真正照亮的位置。历史上两版「最上层加光」都翻车(0.13 青把 ♥♦ 染灰紫 /
## 零填充大外发光糊成一片), 但那都是**普通混合**:半透明白往上盖 = 往灰里拉。
## 加法是**加光不加灰**:低值白 add 只抬亮度, 色相基本不动 —— 和翻车的两版不是一回事。
## ⚠ 数值刻意低(0.12):add 模式下白比什么都亮, 提亮读得出来就够,
## 「亮」的大头仍由压暗层的**对比**承担。形状走共用的 `Widgets.focus_radius`。
class TutorLight:
	extends Control
	var _focus: Array = []
	## 次级强调(v6 分镜化, 用户拍板):**小半径柔光圈**, 位置随步切换, 不动条与 focus。
	## ⚠ 这是对「教学高亮层不许画任何非黑色」判据的**一次有意豁免**(v6 规格明写「光斑」):
	## 豁免只给这一个小圆 —— 加法混合 + 小半径 + 低值, 不是当年糊掉全屏的那种柔光洗。
	var _spot := Rect2()

	func _init() -> void:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m

	func set_focus(focus: Array) -> void:
		if focus == _focus:
			return
		_focus = focus
		visible = (not _focus.is_empty()) or _spot.size.x > 0.0
		queue_redraw()

	func set_spot(q: Rect2) -> void:
		if q == _spot:
			return
		_spot = q
		visible = (not _focus.is_empty()) or _spot.size.x > 0.0
		queue_redraw()

	func _draw() -> void:
		# focus 本身仍零白色(判据在 TutorDim:对比就是打光);只画 spot 的光斑。
		if _spot.size.x <= 0.0:
			return
		# 同心圆角盒叠加(加法混合):内里累计到 ~0.18 白, 向外逐层软掉 ——
		# 形状走共用的 `Widgets.focus_radius`(键 = 圆, 行 = 圆角长条), 光贴合看到的形状。
		const LAYERS := 10
		for i in range(LAYERS):
			var q := _spot.grow(float(LAYERS - 1 - i) * 3.0)
			draw_style_box(StageTheme.box(Color(1, 1, 1, 0.016), Color(0, 0, 0, 0), 0,
				int(Widgets.focus_radius(q))), q)


class GradBar:
	extends Control
	var fraction := 0.0:
		set(v):
			fraction = v
			queue_redraw()
	func _draw() -> void:
		var track := StageTheme.box(Color(0.03, 0.04, 0.10, 0.85),
			Color(0.63, 0.71, 1.0, 0.16), 1, 6)
		draw_style_box(track, Rect2(Vector2.ZERO, size))
		if fraction <= 0.0:
			return
		var w: float = maxf(size.x * fraction, 10.0)
		# the fill heats cyan → pink as the target closes, same language the
		# wave uses for score
		# squared ramp: it stays cyan through the middle and only goes hot near
		# the target, instead of sitting in a washed-out teal the whole time
		var c: Color = StageTheme.CYAN.lerp(StageTheme.PINK, pow(clampf(fraction, 0.0, 1.0), 2.2))
		draw_style_box(StageTheme.box(Color(c.r, c.g, c.b, 0.30), Color(0, 0, 0, 0), 0, 9),
			Rect2(-4, -5, w + 8, size.y + 10))
		draw_style_box(StageTheme.box(c, Color(0, 0, 0, 0), 0, 6), Rect2(0, 0, w, size.y))
		draw_rect(Rect2(3, 2, maxf(w - 6, 1.0), 2), Color(1, 1, 1, 0.55), true)


## One phrase marker in the info bar. Lights up rather than just changing
## colour, so the row reads as part of the neon rig.
class SegPill:
	extends Control
	var lit := false:
		set(v):
			lit = v
			queue_redraw()
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if not lit:
			draw_style_box(StageTheme.box(Color(0.63, 0.71, 1.0, 0.13),
				Color(0, 0, 0, 0), 0, 3), r)
			return
		var c := StageTheme.CYAN
		draw_style_box(StageTheme.box(Color(c.r, c.g, c.b, 0.22), Color(0, 0, 0, 0), 0, 6),
			r.grow(5.0))
		draw_style_box(StageTheme.box(c, Color(0, 0, 0, 0), 0, 3), r)


## ── shared "stage card" chrome ─────────────────────────────────────────────
## The home screen's big glass card (docs/mockups/home.html) and the in-game
## blind board are THE SAME OBJECT — a level IS a blind (用户 2026-08-05).
## These statics are the one place the look is defined, so the two can never
## drift apart.
##
## The mock hangs `assets/frame-glass4.png` — a glass BEZEL ~34px thick around
## an inset, translucent well — over the card, at 113.2% height so its lower
## section reaches past the card and frames the tab menu as a reflection.
## That art is not in the repo, so the bezel is drawn: outer bloom, pale glass
## plate, bright inner/outer rims, cut corners with brackets, side vents, a
## top notch with an LED, and `menu_reflection()` for the mirrored tail.
## Second pass 2026-08-05 (用户: 质感差距大 — 要透明感/边缘发光/倒影兜菜单).
class StageCard:
	extends RefCounted

	## ── 玻璃卡的程序化临摹 ────────────────────────────────────────────────
	## 参照 docs/mockups/godot-handoff/card_glass_full.png 的构成:
	##   半透玻璃体 + 内缩一圈细亮边 + 26px 点阵 + 斜向高光楔 + 底部镜面倒影。
	## **为什么不直接贴那张图**(用户 2026-08-05 拍板): 素材是 842×1355 固定竖版,
	## 局内盲注板是 560×276 的扁板, 拉伸会把圆角和边框粗细拽变形; 而且那张 PNG
	## 的 alpha 抠得脏(内部有大片斑块残留)。程序化画法尺寸无关, 两处才能真正同源。
	## 尺寸参数一律用**显示像素绝对值**(交接件 842 宽 → 显示 640, 比例 0.76:
	## 内缩 40→30, 圆角 30→23), 所以扁板和大卡看起来是同一块玻璃。
	const RADIUS := 26.0          # 圆角(显示像素)
	const RIM_INSET := 13.0       # 内框: 玻璃体内侧那圈细线
	## 玻璃体比外框小一圈 —— home.html 的 640×972 是外框 div, 真正的玻璃是
	## `inset:34px` 之后的 572×904, 外面那圈是留给辉光溢出的。照着外框画会偏大。
	const BLEED := 34.0
	const GRID := 26.0            # 交接件: 26px 点阵(用户钦点保留)

	## ── 素材路径 ────────────────────────────────────────────────────────────
	## `docs/mockups/godot-handoff/` 的灰白玻璃图(alpha 已抠), 运行时副本在
	## assets/frames/。灰白 = 原图 saturate(0) 预烘焙, 所以能直接用 modulate
	## 按盲注档位上色 —— 交接件「卡体不带色, 颜色来自灯」在这里落成"给灯上色"。
	##
	## **九宫格是尺寸问题的答案**(交接件: 9-slice 四边各 60px): 只拉中间,
	## 四角和边框保持原始像素, 所以 560×276 的扁板不会把圆角/边框拽变形。
	## 带倒影的整图不能九宫格(倒影会落进下边条), 首页大卡按设计稿整图拉伸,
	## 比例本来就对得上。
	const NINE := 118.0
	const FRAME_TAIL := 1355.0 / 1197.0   # 交接件倒影比例 = html 的 113.2%
	static var _tex: Dictionary = {}

	static func glass_tex(with_tail: bool) -> Texture2D:
		var key := "glass" if with_tail else "glassface"
		if _tex.has(key):
			return _tex[key]
		var path := "res://assets/frames/%s.png" % key
		var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
		_tex[key] = t
		return t


	## 九宫格贴图: 四角原样, 四边单向拉, 中间双向拉。
	static func draw_nine(ci: CanvasItem, tex: Texture2D, r: Rect2, m: float,
			tint: Color) -> void:
		var tw := float(tex.get_width())
		var th := float(tex.get_height())
		var mx: float = minf(m, minf(tw, r.size.x) * 0.5 - 1.0)
		var my: float = minf(m, minf(th, r.size.y) * 0.5 - 1.0)
		var sx := [0.0, mx, tw - mx, tw]           # 源切边
		var sy := [0.0, my, th - my, th]
		var dx := [r.position.x, r.position.x + mx, r.end.x - mx, r.end.x]
		var dy := [r.position.y, r.position.y + my, r.end.y - my, r.end.y]
		for i in range(3):
			for j in range(3):
				var src := Rect2(sx[i], sy[j], sx[i + 1] - sx[i], sy[j + 1] - sy[j])
				var dst := Rect2(dx[i], dy[j], dx[i + 1] - dx[i], dy[j + 1] - dy[j])
				if dst.size.x <= 0.0 or dst.size.y <= 0.0:
					continue
				ci.draw_texture_rect_region(tex, dst, src, tint)


	static var _body_grad: GradientTexture2D = null

	## 玻璃体的竖向渐变(**暗**的, 不是白纱): 交接件给的
	## rgba(24,28,56,.34) → rgba(7,9,22,.42)。
	static func body_grad() -> GradientTexture2D:
		if _body_grad != null:
			return _body_grad
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 1.0])
		g.colors = PackedColorArray([Color(0.094, 0.110, 0.220, 0.34),
			Color(0.027, 0.031, 0.086, 0.42)])
		_body_grad = GradientTexture2D.new()
		_body_grad.gradient = g
		_body_grad.width = 8
		_body_grad.height = 256
		_body_grad.fill_from = Vector2(0, 0)
		_body_grad.fill_to = Vector2(0, 1)
		return _body_grad


	## `r` 传**外框**(设计稿的 640×972 div), 玻璃体自己内缩 BLEED。
	## `tail` = 用带倒影的整图(首页大卡, 倒影兜住菜单); false = 无倒影版走九宫格。
	## `body` 给全局 chrome(顶栏)用: 传一个半透黑就能压过按档位色算出来的玻璃体。
	static func draw_card(ci: CanvasItem, r: Rect2, acc: Color, radius := -1.0,
			inset := -1.0, tail := false, body := Color(0, 0, 0, 0)) -> void:
		var rad: float = RADIUS if radius < 0.0 else radius
		var ins: float = RIM_INSET if inset < 0.0 else inset
		var tex := glass_tex(tail)
		if tex != null:
			# 交接件分层: 内衬深底(内缩 34, 圆角 18) → 玻璃贴图 → 内容(调用方画)
			ci.draw_style_box(StageTheme.box(Color(0.051, 0.059, 0.133, 0.70),
				Color(0, 0, 0, 0), 0, 18), r.grow(-BLEED))
			var tint := Color(acc.r, acc.g, acc.b, 1.0)
			if tail:
				ci.draw_texture_rect(tex, Rect2(r.position,
					Vector2(r.size.x, r.size.y * FRAME_TAIL)), false, tint)
			else:
				draw_nine(ci, tex, r, NINE, tint)
			return
		# r 传外框, 内缩由 _slab 自己按设计稿处理。`tail` 的倒影是独立的镜像层
		# (见 draw_mirror), 不在这里画。
		_slab(ci, r, acc, rad, ins, 1.0, false, body)


	## 一块玻璃。a = 整体透明度(倒影复用同一套画法, 只是压扁调暗)。
	##
	## **照着交接件 PNG 的像素剖面画**(tools 里量过, 2026-08-05):
	##   · 整张图**只有一条线**: 在图宽 4.9% 处, 近白(灰度 0.93)、alpha 0.99、约 3px;
	##   · 这条线**外面 alpha 全是 0** —— 设计稿没有外光晕, 也没有主色描边;
	##   · 线内侧 alpha 0.18→0.07 缓降, 是一层很淡的浅灰玻璃膜, 不是深色板。
	## 2026-08-06 用户拍板:「我最初的设计仅仅是一块玻璃板被打了光」——
	## 分层砍成: **单块玻璃体**(圆角多边形逐顶点竖向渐变, 无任何内部边界)
	## → 点阵(用户钦点保留)→ 右上受光楔 → 那一条白线。
	## 「玻璃板里面卡别的图层是很难动」针对的是**有边界的板/贴图矩形**。曾照 html 的 `inset:34px` 搬过一层
	## 内衬深底 + 渐变贴图矩形, 两组可见的矩形边被用户点名(「内置矩形」), 已删。
	## **别再加外发光/主色描边/第二块内板** —— 都是凭空多出来的。
	const LINE_INSET := 30.0      # 白线距外框(显示像素, 设计稿 4.9%×640≈31)
	const PANEL_INSET := 34.0     # 内衬深底, 设计稿 inset:34px
	const PANEL_RADIUS := 18.0    # 设计稿 border-radius:18px

	## `ins` = 白线距外框(大卡 30 / 玩家条这种小件要按比例缩), 内衬深底再往里 4。
	## `lit_only` = 只画会发光的部分(线 + 一层极淡玻璃膜), 给倒影用 ——
	## 实物倒影里深色内衬几乎不反射, 连它一起镜像会把底部页签压暗。
	static func _slab(ci: CanvasItem, r: Rect2, acc: Color, rad: float, ins: float,
			a: float, lit_only := false, body_override := Color(0, 0, 0, 0)) -> void:
		# 剖面显示玻璃体在**线的外侧也还有**(x=30..38 alpha 0.02→0.13), 所以玻璃
		# 要比线更往外一点 —— 线是嵌在玻璃里的, 不是浮在玻璃外面(用户:「和玻璃板
		# 不太贴合」)。
		# 注意: 这里曾经铺过一层淡蓝白的"玻璃膜"(0.10 白), 已删 —— 它和下面的
		# sheen 一起, 就是"玻璃板上有一层白白的东西"的来源(用户 2026-08-05)。
		# 玻璃的通透靠**暗**渐变 + 局部高光, 不靠往上糊白。
		var panel := r.grow(-(ins + 4.0))
		var w := panel.size.x
		var h := panel.size.y

		if lit_only:
			_line(ci, r, acc, rad, ins, a)
			return

		# 1. 玻璃体 = **一块**(2026-08-06 用户:「我最初的设计仅仅是一块玻璃板
		# 被打了光」, 并点名看到了「内置矩形」)。旧做法是 内衬深底(有边的圆角板)
		# + 内缩矩形上的渐变贴图 —— 后者为了不从圆角溢出往里缩了 ~9px, 贴图四条
		# alpha 硬边就是那个「内置矩形」。现在整块玻璃是**一个圆角多边形逐顶点
		# 竖向渐变**:颜色是 y 的线性函数, 重心插值精确重现, 天生没有任何内部
		# 边界。剖面显示线内外都有玻璃, 玻璃体延伸到白线**外** 8px(线嵌在玻璃里)。
		# 颜色在**玻璃体**里(掺 22% 档位色), 光在**边**上(白线是纯白)。
		# 体色按参考图**实测**(2026-08-06 像素剖面): 近黑 + ~5% 档位色,
		# 中心 v3-7 —— 玻璃的"颜色感"主要来自线和光, 不是体。
		# 体色按参考实测: 是**高饱和、低明度的档位色**(red 体 #120000 s=1.00,
		# green #000705, gold #080501), 不是中性黑掺一点色 —— 后者会把红卡画成灰卡。
		# 体色 = **边缘有色、中心近黑**(用户 2026-08-06:「这块板靠中间是偏黑的,
		# 靠四周(线条)是比较有颜色的……你现在整块板都带着那个颜色」)。
		# 物理上就是这样: 发光的是**边上那根霓虹管**, 光往玻璃里渗, 越靠中心越弱。
		# 做法 = **三角扇**: 中心一个顶点给近黑, 边缘顶点给档位色, 重心插值天然
		# 得到径向衰减, 而且**没有任何内部边界**(同心多边形分层会露出圈)。
		# ⚠ **不要用三角扇**做这个径向衰减: 重心插值的等值线**平行于每条边**,
		# 长宽比大的矩形会显出一圈圈方形光晕(实测中心有明显菱形接缝)。
		# 光是**沿法线从边渗进来**的 —— 等值线应该是均匀内缩的圆角矩形。
		# 所以: 纯黑玻璃体 + 一叠向内内缩的宽描边(渗光), 指数衰减。
		var glass := r.grow(-(ins - maxf(2.0 * clampf(ins / 30.0, 0.42, 1.0), 1.0) - 1.0))
		var gpath := _rounded_path(glass, rad + 4.0)
		# 参考放大图的板面是**有颜色的暗档位色**(不是纯黑) —— 点阵浮在它上面。
		var core_c := Color.from_hsv(acc.h, minf(acc.s * 1.15, 1.0), 0.052)
		var gcols := PackedColorArray()
		for gp in gpath:
			var t: float = clampf((gp.y - glass.position.y) / maxf(glass.size.y, 1.0), 0.0, 1.0)
			gcols.append(Color(core_c.r, core_c.g, core_c.b, (0.96 - 0.10 * t) * a))
		ci.draw_polygon(gpath, gcols)
		# 边缘渗光: 靠线的一圈更亮, 陡衰减(只占卡宽 ~12%), 中间保持暗。
		# 参考放大图里板面靠边明显更亮 —— 光是从那根霓虹管渗进来的。
		var bleed_c := Color.from_hsv(acc.h, minf(acc.s * 1.2, 1.0), 1.0)
		var bstep: float = maxf(glass.size.x * 0.012, 4.0)
		for bi in range(10):
			var bd: float = float(bi) * bstep
			if bd > glass.size.x * 0.14 or bd > glass.size.y * 0.14:
				break
			var bwid: float = bstep * 2.6
			_lit_rim(ci, glass.grow(-(bd + bwid * 0.5)),
				maxf(rad + 4.0 - bd * 0.25, 10.0), bleed_c,
				0.055 * exp(-float(bi) * 0.34) * a, 1.0, bwid, 0.0)

		# ⚠⚠ **玻璃体里不做任何均匀染色**(2026-08-06 用户:「把板子中间, 带有颜色
		# 的那么大的面积, 去掉, 变黑。只剩斑点带颜色点缀」)。我先后做过整块均匀染色、
		# 三角扇径向渐变、向内内缩的渗光环 —— **全都是多余的**: 板体就是黑的,
		# 颜色只由 ①那条白边(带档位色+白光) ②点阵 承担。

		# 2. 26px 点阵(2026-08-06 曾按「玻璃里不卡图层」误删, 用户:「点阵别删」)
		# 点阵**是有颜色的**(用户 2026-08-06)。同样跟着"边亮中暗": 越靠边越显色。
		var dot_c := Color.from_hsv(acc.h, minf(acc.s * 1.1, 1.0), 1.0)
		var dot_ctr := panel.get_center()
		var dot_rmax: float = maxf(dot_ctr.distance_to(panel.position), 1.0)
		var gy := panel.position.y + GRID
		while gy < panel.end.y - 6.0:
			var gx := panel.position.x + GRID
			while gx < panel.end.x - 6.0:
				var dr: float = clampf(Vector2(gx, gy).distance_to(dot_ctr) / dot_rmax, 0.0, 1.0)
				# 板体全黑之后, **点阵是唯一的颜色点缀** —— 要看得见。
				ci.draw_rect(Rect2(gx, gy, 1.6, 1.6),
					Color(dot_c.r, dot_c.g, dot_c.b, (0.16 + 0.34 * dr * dr) * a), true)
				gx += GRID
			gy += GRID

		# 3. 受光: **只有右上角一块**。参照设计稿近景 —— 卡面是干净的暗色,
		#    只有右上角被灯切出一个三角亮面, 边界是一条清楚的斜线。
		#    这里**不要**再叠 `PaperCard.sheen()`(那是整块面板的白色反光带),
		#    也不要满幅的白色柔光 —— 两者都会让玻璃"蒙一层白"(用户两次指出)。
		# 3. **光线造成的明暗**(用户 2026-08-06 给了右上角放大图:「我说的是这个东西」)。
		# ⚠ 形态与我先前的理解**正好相反**: 不是"右上角亮、其余黑", 而是
		# **板面主体受光, 右上角被一条清楚的斜线切出一块暗区**(玻璃的另一个反射面),
		# 而白色热点在**边线的右上角**。光从右上来说的是那个热点, 不是板面的亮块。
		var lit := acc.lerp(Color(1, 1, 1), 0.80)
		# 3a. 板面主体的受光(左上→中部, 很淡, 只是把板面提起来一点)
		# **光从右上往左下射**(用户 2026-08-06 原话) —— 板面**右上亮、左下暗**,
		# 所以直角顶点在 panel 右上, 沿光线方向衰减。
		ci.draw_polygon(PackedVector2Array([
			panel.position + Vector2(w, 0.0),
			panel.position + Vector2(w * 0.10, 0.0),
			panel.position + Vector2(w, h * 0.92)]),
			PackedColorArray([Color(lit.r, lit.g, lit.b, 0.095 * a),
				Color(lit.r, lit.g, lit.b, 0.010 * a), Color(lit.r, lit.g, lit.b, 0.010 * a)]))
		# 3b. **右上角的暗区**: 一条斜线切下来, 线右下侧压黑 —— 这是画面里
		# 最明显的那道分界, 用纯黑叠加而不是"少给光", 边界才利落。
		# 尺寸按放大图换算: 那张图是整卡右上角约 1/4 的局部, 斜线在其中约 45°,
		# 折回整卡 = **只切掉右上角一小块**(从上边 76% 处到右边 26% 高度), 不是一大片。
		ci.draw_polygon(PackedVector2Array([
			panel.position + Vector2(w * 0.76, 0.0),
			panel.position + Vector2(w, 0.0),
			panel.position + Vector2(w, h * 0.26)]),
			PackedColorArray([Color(0, 0, 0, 0.55 * a), Color(0, 0, 0, 0.66 * a),
				Color(0, 0, 0, 0.48 * a)]))

		# (四角的径向辉光已删: 角的增强由 `_lit_rim` 的 corner boost 在**线上**做,
		# 额外贴一团光只会变成卡外的雾, 且容易读成灯泡。)

		_line(ci, r, acc, rad, ins, a)


	## 那条线 = 一根霓虹灯管: 剖面在峰值两侧是 0.13/0.10/0.04/0.01 的衰减,
	## 所以要**先铺两侧辉光再画锐利白芯**, 硬边 2px 画出来是"不发光"的
	## (用户:「白边不够发光」)。辉光取档位色, 芯保持近白。
	## 外圈的光是**白的**(用户 2026-08-05:「外圈的光应该就是白色的」)——
	## 档位色留给玻璃体, 边上这道是灯打在玻璃棱上的反光, 掺主色会立刻变脏。
	## `blur` 给倒影用: 只留宽而软的几道、不画锐利白芯, 读起来就是糊开的。
	static func _line(ci: CanvasItem, r: Rect2, acc: Color, rad: float, ins: float,
			a: float, blur := false) -> void:
		var line := r.grow(-ins)
		# 2026-08-06 用户给了五张玻璃卡终极参考(粉/紫/青/金/红):**线是档位色的
		# 霓虹管**, 只在热点处烧到近白 —— 取代旧拍板「外圈纯白」(那是灰白交接件
		# 的剖面结论, 参考图升级后作废)。辉光 = 档位色, 芯 = 档位色提亮。
		# ⚠ 芯必须**近白**(参考边色@50%: #ffe9f9/#f9f7fd/#eefdfc/#fbd983)。
		# 2026-08-06 曾把它降到 0.32 白 + 最内圈辉光提到 0.42 纯档位色, 结果白芯
		# 被辉光染回彩色 —— 用户:「光圈不白了」。芯在最上层, 但压不过太强的内圈辉光。
		var w := acc.lerp(Color(1, 1, 1), 0.42)
		# 辉光的宽度要跟着件的大小缩: 大卡的内缩是 30, 局内盲注板只有 14,
		# 照搬绝对值那圈白光在小板上就显得很厚(用户 2026-08-05:「局内盲注外面的
		# 白色光圈不用那么厚, 但可以有点光泽」)。薄一圈, 但层数不减 —— 光泽靠
		# 层次, 不靠厚度。
		var k: float = clampf(ins / 30.0, 0.42, 1.0)
		if blur:
			# **糊的是边缘, 形还在**(用户 2026-08-05 指出): 只铺宽而淡的几道会把
			# 倒影整个稀释成看不见。正确做法是保留一道**柔和的芯**(比正面宽、比
			# 正面暗, 不锐利), 外面再散开 —— 像失焦的镜像, 不是一团雾。
			for spec in [[15.0, 20, 0.05], [10.0, 15, 0.09], [5.5, 10, 0.15],
					[2.0, 6, 0.24], [0.0, 5, 0.42]]:
				var bg: float = float(spec[0])
				var bbw: int = int(spec[1])
				var ba: float = float(spec[2])
				ci.draw_style_box(StageTheme.box(Color(0, 0, 0, 0),
					Color(acc.r, acc.g, acc.b, ba * a), bbw, int(rad + bg)), line.grow(bg))
			return
		# 辉光与芯**共用同一个亮度场**(对账实测: 均匀 StyleBox 环把底边抬到 v81,
		# 参考是 v2-10 —— 底边的暗必须一路暗到辉光)。环外扩到 +20px:
		# 参考纵剖外侧 8px 处 v8-16, 均匀环时代我们是 0。
		var floor_k := clampf(lerpf(0.75, -0.15, k * k), 0.0, 1.0)
		# 对账实测(2026-08-06): 参考的辉光**主要往内渗**, 外侧很克制 ——
		# 顶边中点纵剖 外侧 −8/−4px 只有 v5/v8, 内侧 +4..+24px 却有 v23/20/16。
		# 所以外环薄, 内环厚(内环还兼顾"上部光线"的近边那一截)。
		# 强度按参考辉光带对齐: 实测参考 v=0.35-0.51, 旧值只有 ~0.12(饱和采样都
		# 采不到) —— 这就是「带光线的部分比目标少」的另一半。
		# ⚠⚠ **卡外不做光晕**(2026-08-06 用户:「我让你加强边缘光, 中间不要光,
		# 你给我加光晕」)。用户要的一直是**玻璃内侧靠边的渗光**, 不是卡片外面
		# 糊一圈雾。这里只留紧贴线的一道 2px 过渡, 让线不显得像贴纸 —— 到此为止。
		for spec in [[2.0, 3.0, 0.10]]:
			var g: float = float(spec[0]) * k
			var bw: float = maxf(float(spec[1]) * k, 1.5)
			_lit_rim(ci, line.grow(g), rad + g, acc, float(spec[2]) * a,
				floor_k, bw, 0.25)
		for spec in [[2.5, 5.0, 0.16], [6.0, 6.0, 0.055]]:
			var gi: float = float(spec[0]) * k
			var bwi: float = maxf(float(spec[1]) * k, 1.5)
			_lit_rim(ci, line.grow(-gi), maxf(rad - gi, 4.0), acc,
				float(spec[2]) * a, floor_k, bwi, 0.25)
		# 芯不是均匀一圈: 光从左上来, 迎光的边亮、背光的边暗(用户 2026-08-05:
		# 「白色光边部分地方的光泽会比较大, 不是全均匀的」)。
		# 受光不均的幅度也要跟着尺寸缩: 大卡上"迎光亮/背光暗"是质感, 到局内小板上
		# 就成了"一头毛毛一头很细"(用户 2026-08-05), 所以小件几乎均匀。
		_lit_rim(ci, line, rad, w, 1.0 * a, floor_k, maxf(4.0 * k, 2.0), 1.0)
		# **边缘的立体感**(用户 2026-08-06:「他的边缘还有点立体感你没做」):
		# 参考里边不是一条线, 是**有厚度的玻璃棱** —— 亮芯内侧紧跟一道暗内壁
		# (棱的背光面), 再往内一道极细的二次反光。三层叠起来才有"板有厚度"的读感。
		var wall := Color(0, 0, 0)
		_lit_rim(ci, line.grow(-2.6 * k), maxf(rad - 2.6 * k, 4.0), wall,
			0.72 * a, floor_k, maxf(2.4 * k, 1.4), 0.0)
		var inner := acc.lerp(Color(1, 1, 1), 0.85)
		_lit_rim(ci, line.grow(-4.6 * k), maxf(rad - 4.6 * k, 4.0), inner,
			0.50 * a, floor_k, maxf(1.6 * k, 1.0), 0.5, true)


	## 把路径上距离超过 step 的相邻点段插值细分 —— 逐点着色需要边上有点。
	static func _dense(pts: PackedVector2Array, step: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		for i in range(pts.size()):
			var a2 := pts[i]
			var b2 := pts[(i + 1) % pts.size()]
			out.append(a2)
			var d := a2.distance_to(b2)
			var n := int(d / step)
			for j in range(1, n + 1):
				out.append(a2.lerp(b2, float(j) / float(n + 1)))
		return out


	## 圆角矩形路径(四角用短弧近似), 给"受光不均"的描边用。
	static func _rounded_path(r: Rect2, rad: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		var seg := 5
		var corners := [
			[Vector2(r.end.x - rad, r.position.y + rad), -PI * 0.5, 0.0],
			[Vector2(r.end.x - rad, r.end.y - rad), 0.0, PI * 0.5],
			[Vector2(r.position.x + rad, r.end.y - rad), PI * 0.5, PI],
			[Vector2(r.position.x + rad, r.position.y + rad), PI, PI * 1.5]]
		for c in corners:
			var o: Vector2 = c[0]
			var a0: float = c[1]
			var a1: float = c[2]
			for i in range(seg + 1):
				var t: float = float(i) / float(seg)
				var ang: float = lerpf(a0, a1, t)
				pts.append(o + Vector2(cos(ang), sin(ang)) * rad)
		pts.append(pts[0])
		return pts


	## 受光不均的描边: 法线朝左上的地方最亮, 背面掉到三成。
	## `floor_k` = 背光处保留多少亮度(1.0 = 完全均匀)。
	## 亮度分布按 2026-08-06 参考图**像素实测**(目测版是反的, 别退回去):
	## **侧边最亮**(全程 v98-100, 中段烧近白, 近底有凹陷)→ 顶边其次(保饱和)
	## → **底边中段是暗的**, 只有底角亮。floor_k 越高越均匀(小件规矩不变)。
	static func _lit_rim(ci: CanvasItem, r: Rect2, rad: float, col: Color,
			a: float, floor_k := 0.30, width := 2.2, whiten_scale := 1.0,
			invert := false) -> void:
		# ⚠ _rounded_path 只在圆角出点, 直边是单段长线 —— 逐点亮度会被两端角的值
		# 线性插满整条边(对账实测: 底边被底角的 0.69 填成 v70, 剖面完全没生效)。
		# 必须先把直边细分。
		var pts := _dense(_rounded_path(r, rad), 22.0)
		var uneven: float = clampf(1.0 - floor_k, 0.0, 1.0)
		var cols := PackedColorArray()
		for p in pts:
			var u: float = clampf((p.x - r.position.x) / maxf(r.size.x, 1.0), 0.0, 1.0)
			var v: float = clampf((p.y - r.position.y) / maxf(r.size.y, 1.0), 0.0, 1.0)
			var topness: float = exp(-pow(v / 0.05, 2.0))
			var botness: float = exp(-pow((1.0 - v) / 0.05, 2.0))
			var sideness: float = clampf(1.0 - topness - botness, 0.0, 1.0)
			# 实测剖面: 侧边 v98-100 全程亮(近底 v≈0.9 凹陷), 顶边 v93-99,
			# **底边中段 v2-9 暗**, 底角亮(v30-60)。
			var corner_b: float = exp(-pow(u / 0.10, 2.0)) + exp(-pow((1.0 - u) / 0.10, 2.0))
			var lit_side: float = 1.0 - 0.45 * exp(-pow((v - 0.9) / 0.06, 2.0))
			var lit_bot: float = 0.06 + 0.57 * corner_b
			# 角上的光更强 —— 但要沿着**线**增强, 不能贴一团圆点(那读成灯泡)。
			var cu: float = minf(u, 1.0 - u)
			var cv: float = minf(v, 1.0 - v)
			var corner_k: float = exp(-(pow(cu / 0.16, 2.0) + pow(cv / 0.10, 2.0)))
			var profile: float = topness * 0.96 + botness * lit_bot + sideness * lit_side
			profile = minf(profile + 0.45 * corner_k, 1.35)
			# 烧白在**侧边中段**(实测 #ffe9f9 近白), 顶边保饱和
			# 顶边**保饱和**(参考 #f392c7/#fb4a47), 只有侧边中段烧到近白(#ffe9f9)
			# 白热点在**右上角**(用户放大图: 那一段边是纯白的, 往两边褪回档位色)。
			var hot_tr: float = exp(-(pow((1.0 - u) / 0.30, 2.0) + pow(v / 0.22, 2.0)))
			var whiten: float = (0.95 * hot_tr
				+ sideness * 0.35 * exp(-pow((v - 0.5) / 0.30, 2.0)) * u) * whiten_scale
			var lit: float = lerpf(1.0, profile, uneven)
			if invert:
				# 内壁模式: 光从左上进玻璃, 穿过板体照亮**右下**的内壁 ——
				# 左上内壁反而在阴影里。这个方向差才是"板有厚度"的来源,
				# 同心等亮的三条线只会读成三条贴纸。
				# 光从右上进玻璃 → 照亮**左下**内壁; 右上内壁在阴影里
				lit = clampf(0.12 + 0.88 * ((1.0 - u) * 0.5 + v * 0.5), 0.0, 1.0)
			var cw: Color = col.lerp(Color(1, 1, 1), clampf(whiten * uneven, 0.0, 0.92))
			cols.append(Color(cw.r, cw.g, cw.b, clampf(a * lit, 0.0, 1.0)))
		ci.draw_polyline_colors(pts, cols, width, true)


	## ── 底部倒影 = 真镜像 ─────────────────────────────────────────────────
	## 把素材那截倒影整段裁出来看过(不是点采样): 接缝处一条很亮的横线(卡片底边
	## 的镜像)+ 往下延续的圆角与两侧竖轨 + 淡淡的镜像玻璃体, **1:1 不压扁**,
	## 随距离渐隐。带高 = 卡高的 13.2%(= home.html 的 height:113.2%)。
	##
	## 遮罩必须走 **shader**(docs/design/ui_meta.md 渲染手法):渐隐要统一作用在 StyleBox /
	## 贴图 / 线条上, 用一张渐变矩形盖上去只能糊住颜色、盖不住 alpha。
	## 画法与 `PaperCard._mask_material` 同源, 只是这里按屏幕 y 做带状渐隐。
	## 走过的弯路: 压扁整块玻璃(读成"第二张小卡片")、只画左右两条竖光带
	## (丢了接缝亮线和圆角)——都是没把倒影整段看一眼就下的结论。
	## 镜像轴 = **霓虹轨底边**(裁图实测: 那条很亮的接缝线就在轨底, 不是外框底,
	## 按外框底起算会整体下掉一个内缩的高度、和卡之间空出一条缝)。
	## 带高 = 卡高的 13.5% —— 正是交接件倒影带的比例(1355/1197-1), 光刚好铺满
	## 底部整排页签的高度:**页签是坐在倒影里的**(用户 2026-08-05:「底部 menu 现在
	## 是在卡牌倒影中……光线没有覆盖到整个 menu 的高度」)。
	## 早先砍到 6% 是因为那时倒影画得太实(整块玻璃压扁/满不透明度), 拉长就会把
	## 页签圈成"第二块板"; 现在倒影只剩柔光 + shader 渐隐, 铺满才是对的。
	const TAIL_RATIO := 0.135
	## 卡片与倒影之间留一道缝: 卡是**浮在**反光地面上的, 浮空物体的镜像本就从
	## 地面再往下退一个离地高度, 贴死会像插在地上; 而且上方(信息栏↔卡片)有呼吸、
	## 下方贴死会不对称(用户 2026-08-05 提的)。
	const TAIL_GAP := 12.0

	static var _mirror_shader: Shader   # 只编译一份(同 PaperCard._mask_shader)

	static func mirror_material(y0: float, band: float, peak: float) -> ShaderMaterial:
		if _mirror_shader == null:
			_mirror_shader = Shader.new()
			_mirror_shader.code = _MIRROR_CODE
		var m := ShaderMaterial.new()
		m.shader = _mirror_shader
		m.set_shader_parameter("y0", y0)
		m.set_shader_parameter("band", band)
		m.set_shader_parameter("peak", peak)
		return m

	const _MIRROR_CODE := """
shader_type canvas_item;
uniform float y0 = 0.0;
uniform float band = 128.0;
uniform float peak = 0.55;
varying float ly;
void vertex() { ly = VERTEX.y; }
void fragment() {
	float t = clamp((ly - y0) / max(band, 0.001), 0.0, 1.0);
	COLOR.a *= peak * pow(1.0 - t, 1.35);
}
"""


	## 在 `ci` 上把 `card` 这块玻璃 1:1 翻转画到下方(调用方负责挂遮罩材质)。
	## 镜像轴 = **霓虹轨的底边**(card.end.y - ins), 不是外框底边。
	##
	## **不能用 `draw_set_transform` 做翻转**: shader 里的 `VERTEX.y` 拿到的是
	## 变换**之前**的局部坐标, 带状渐隐会整个失效(镜像会以满不透明度铺下去,
	## 把底部页签圈成"第二块板")。改成直接算出镜像后的矩形再画 —— 霓虹轨是
	## 上下对称的圆角矩形, 画出来和真镜像等价, 而 shader 能拿到正确的 y。
	static func draw_mirror(ci: CanvasItem, card: Rect2, acc: Color, rad: float,
			ins: float) -> void:
		var seam := card.end.y - ins + TAIL_GAP
		var m := Rect2(card.position.x, seam * 2.0 - card.end.y,
			card.size.x, card.size.y)
		# 参考图里倒影是**糊开的**, 不是一条清晰的线(用户指出)
		_line(ci, m, acc, rad, ins, 1.0, true)


	## 分隔线: 2px 渐变横条 (设计稿的 section rule)。
	static func rule_line(ci: CanvasItem, x: float, y: float, w: float, acc: Color,
			both := false) -> void:
		var a := Color(acc.r, acc.g, acc.b, 0.7)
		var b := Color(acc.r, acc.g, acc.b, 0.18)
		ci.draw_polyline_colors(
			PackedVector2Array([Vector2(x, y), Vector2(x + w * 0.5, y), Vector2(x + w, y)]),
			PackedColorArray([b if both else a, a, b]), 2.0)


	## 均衡器带: 中轴发亮, 两侧镜像条, 包络中间高。`t` 驱动脉动,
	## `seed_n` 让同一个盲注的波形保持稳定。
	static func eq_band(ci: CanvasItem, r: Rect2, acc: Color, t: float, seed_n: int,
			bars := 34) -> void:
		var mid := r.position.y + r.size.y * 0.5
		var bw: float = r.size.x / float(bars)
		for i in range(bars):
			var env: float = pow(sin(PI * (float(i) + 0.5) / float(bars)), 1.7)
			var h1: float = _hash(seed_n * 100 + i)
			var h2: float = _hash(seed_n * 100 + i + 60)
			var h3: float = _hash(seed_n * 100 + i + 120)
			var h: float = (0.08 + env * (0.55 + h1 * 0.42)) * r.size.y
			if h2 > 0.82:
				h *= 1.25
			var dur: float = 0.8 + h3 * 0.9
			var ph: float = fmod(t / dur + h2 * 1.2, 1.0)
			h *= 0.45 + 0.55 * (0.5 - 0.5 * cos(ph * TAU))
			h = minf(h, r.size.y * 0.92)
			var x := r.position.x + float(i) * bw
			var bar := Rect2(x + bw * 0.22, mid - h * 0.5, maxf(bw * 0.56, 2.0), h)
			ci.draw_texture_rect(bar_tex(), bar, false, Color(acc.r, acc.g, acc.b, 0.95))
			ci.draw_texture_rect(bar_tex(), Rect2(bar.position.x, mid - h * 0.22,
				bar.size.x, h * 0.44), false, Color(1, 1, 1, 0.9))
		ci.draw_polyline_colors(
			PackedVector2Array([Vector2(r.position.x, mid),
				Vector2(r.position.x + r.size.x * 0.5, mid), Vector2(r.end.x, mid)]),
			PackedColorArray([Color(acc.r, acc.g, acc.b, 0.0), Color(1, 1, 1, 0.95),
				Color(acc.r, acc.g, acc.b, 0.0)]), 2.0)

	static func _hash(k: int) -> float:
		var x: float = sin(float(k + 1) * 12.9898) * 43758.5453
		return x - floor(x)

	static var _bar: GradientTexture2D = null

	## 竖向渐变条: 透明 → 主色 → 白芯 → 主色 → 透明。必须建一次并缓存
	## (每帧 new 的 GradientTexture2D 首帧渲染成白, docs/design/ui_meta.md 渲染手法)。
	static func bar_tex() -> GradientTexture2D:
		if _bar != null:
			return _bar
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.32, 0.5, 0.68, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.75),
			Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.75), Color(1, 1, 1, 0.0)])
		_bar = GradientTexture2D.new()
		_bar.gradient = g
		_bar.width = 4
		_bar.height = 96
		_bar.fill_from = Vector2(0, 0)
		_bar.fill_to = Vector2(0, 1)
		return _bar


	## 档位色 = **四档递进**(2026-08-06 用户拍板: 4 个盲注全是 BOSS 墙,
	## 小盲/大盲的概念作废, 递进感全部由档位色 + 序号承担):
	## 蓝 → 橙 → 红 → 粉, 逐档升温。前三档沿用用户拍板的红蓝橙
	## (「不喜欢这个绿色, 红蓝橙可能更好」), 第四档取调色板里的粉——
	## 霓虹灯管最刺眼的就是品红, 语义上是「红再往上」的终局色。
	## 首页舞台卡与局内盲注卡共用这一处, 两边永远同色。
	## (2026-08-10 曾被改成全轮统一品红, 违反上述已锁定拍板, 已还原。)
	static func accent_for(section_idx: int) -> Color:
		match clampi(section_idx, 0, 3):
			0: return StageTheme.BLUE
			1: return StageTheme.AMBER
			2: return StageTheme.RED
			_: return StageTheme.PINK
		return StageTheme.BLUE

	## 第四轮爽点的专属色:金。它是「正向惊喜」这个新视觉类别, 不参与档位递进,
	## 也只在 boon 条上出现 —— 语义自带颜色的小件不受全局 chrome 规则影响(同头像环青/金币金)。
	static func boon_accent() -> Color:
		return StageTheme.GOLD

	## ★★☆ difficulty read of the blind tier (NOT a save record — meta
	## progression is docs/design/ui_meta.md and unimplemented). 四档结构下直接是 1..4。
	static func tier_stars(section_idx: int) -> int:
		return clampi(section_idx + 1, 1, GameConfig.SECTIONS_PER_RUN)


## 局内盲注卡 —— **竖版卡牌, 摆在音浪层左侧**(用户 2026-08-05 拍板:
## 「不如把它放小丑牌下面, 音浪那一层的左边, 放一张卡牌而不是现在这样拉横的」)。
## 之前做成通栏横条, 把上半屏拦腰切断; 竖卡放左边正好和右边的唱片对称,
## 音浪从两者之间穿过。
##
## 分工不变: **HUD 管「当前数值」**(分数/目标、金币、第几拍、进度),
## **这张卡管「你在打什么」**(档位、第几场、BOSS 规则)。
class BlindCard:
	extends Control
	var section_idx := 0
	var mod = null            # 本段的脸(只有墙才有)
	var next_mod = null       # 下一面墙的预告
	var boon = null           # 第四轮进入时才揭示的正向惊喜
	var status_text := ""     # per-phrase public state (request, budget, seals)
	var roll_note := ""       # 掷类脸的明掷结果(编排器灌入, 追加在 command 后)

	func setup(p_section: int, p_mod, p_next, p_boon = null) -> void:
		section_idx = p_section
		mod = p_mod
		next_mod = p_next
		boon = p_boon
		status_text = ""
		queue_redraw()

	func set_status(text: String) -> void:
		if status_text == text:
			return
		status_text = text
		queue_redraw()

	## 2026-08-11 换代:照 assets/docs/design/blind_card_ui.html(已批目录「Final Blind
	## signal deck」)的解剖重写 —— 118×176 设计空间、25 头带(名+槽号)、机制指纹
	## 信号箱(68×68 SVG 纹理)、43 结果脚(command + SIGNAL 短码/live 状态)。
	## **压力盲注统一品红、boon 金**(目录页脚:「盲注统一粉红;轮次由编号与标题表达,
	## 中央机制指纹负责记忆」)—— 这张牌从此不吃档位色;首页/商店的 StageCard 档位
	## 四档递进不受影响。文案在 data/ui.json 的 blindcard 节(改文案 = 改 JSON)。
	## 旧卡面(2026-08-05「照抄手牌排版」版)被本目录明确换代,git 历史可查。
	const MAGENTA := Color("ff328d")
	const HOT_INK := Color("f4fbff")
	var _fp_cache := {}     # face id -> Texture2D / false(试过缺图)

	func _fingerprint(fid: String) -> Texture2D:
		if _fp_cache.get(fid) is Texture2D:
			return _fp_cache[fid]
		if _fp_cache.has(fid):
			return null
		var p := "res://assets/blinds/fp_%s.svg" % fid
		if not ResourceLoader.exists(p):
			# 2026-08-25 起新脸的特写用素材库 PNG(键控透明), svg 优先、png 兜底。
			p = "res://assets/blinds/fp_%s.png" % fid
		if not ResourceLoader.exists(p):
			# 档位扩池(2026-08-26, blinds.md §2.6):同机制不同数值 = 同图标 + 档记号,
			# 缺图时回落 faces.json 的 `base` 指向的原脸图标(db 校验 base 必存在)。
			# ⚑ 复合脸(2026-08-27, versus.md 复合语法)同走这条回落, 落在**第一成分** ——
			# 图标说题干(甲脸的机制), 记号说「这不是本尊」。`base_of` 是两者唯一的口。
			var bid := SectionMod.base_of(fid)
			if bid != "":
				return _fingerprint(bid)
		_fp_cache[fid] = load(p) if ResourceLoader.exists(p) else false
		return _fp_cache[fid] if _fp_cache[fid] is Texture2D else null

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var s := w / 118.0                      # 目录设计空间:118 × 176
		var face = mod if mod != null else next_mod
		var preview := mod == null and next_mod != null
		var acc := MAGENTA
		var dim := 0.62 if preview else 1.0     # 预告态整体收敛

		var zh := StageTheme.zh()
		var med := StageTheme.num("Medium")
		var bold := StageTheme.num("Bold")

		# ---- 卡体:深底 + 1px 品红边 + 点阵纹 + 内衬细线 + 辉光 ----
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("070510")
		sb.set_corner_radius_all(int(9.0 * s))
		sb.set_border_width_all(1)
		sb.border_color = Color(acc.r, acc.g, acc.b, 0.95 * dim)
		sb.shadow_color = Color(acc.r, acc.g, acc.b, 0.27 * dim)
		sb.shadow_size = int(10.0 * s)
		draw_style_box(sb, Rect2(0, 0, w, h))
		var dot := Color(acc.r, acc.g, acc.b, 0.13 * dim)
		var step := 14.0 * s
		var dy := step * 0.5
		while dy < h - 2.0:
			var dx := step * 0.5
			while dx < w - 2.0:
				draw_circle(Vector2(dx, dy), 0.7 * s, dot)
				dx += step
			dy += step
		draw_rect(Rect2(4.0 * s, 4.0 * s, w - 8.0 * s, h - 8.0 * s),
			Color(1, 1, 1, 0.09), false, 1.0)

		# ---- 头带 25s:左 = 脸名(白), 右 = 槽号 / 6s / NEXT ----
		var head_h := 25.0 * s
		var head_name: String = String(face.cn_name) if face != null else GameConfig.blind_name(section_idx)
		draw_string(zh, Vector2(7.0 * s, head_h * 0.72), head_name,
			HORIZONTAL_ALIGNMENT_LEFT, w - 14.0 * s, int(10.0 * s),
			Color(HOT_INK.r, HOT_INK.g, HOT_INK.b, dim))
		# 档记号(2026-08-26 档位扩池, blinds.md §2.6「同机制同图标 + 档记号」):
		# 带 `base` 的档位脸在脸名右上角上标一枚 ◈ —— 表意「同族档位」, 不区分松紧,
		# 与 _fingerprint 的图标回落是同一条原则的两半(图标说机制, 记号说档位)。
		# ⚑ 复合脸(2026-08-27)也戴这枚 ◈:它同样是「图标那张脸的变体」, 而**名字已经
		# 把复合说清楚了**(双名连写 = 零学习成本), 记号不必再分一种形状。
		if face != null and SectionMod.base_of(String(face.id)) != "":
			var nw: float = minf(zh.get_string_size(head_name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(10.0 * s)).x, w - 14.0 * s)
			draw_string(zh, Vector2(7.0 * s + nw + 2.0 * s, head_h * 0.52), "◈",
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(8.0 * s), Color(acc.r, acc.g, acc.b, dim))
		var slot_txt := "NEXT" if preview else \
			("6s" if face != null and face.id == "rush" else "%02d" % (section_idx + 1))
		var stw := med.get_string_size(slot_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(8.0 * s)).x
		draw_string(med, Vector2(w - 7.0 * s - stw, head_h * 0.70), slot_txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(8.0 * s), Color(acc.r, acc.g, acc.b, dim))
		draw_line(Vector2(0, head_h), Vector2(w, head_h), Color(acc.r, acc.g, acc.b, 0.8 * dim), 1.0)

		# ---- 信号箱:边框 + 网格 + 68s 指纹;S4 有 boon 时让 20s 出来 ----
		var foot_h := 43.0 * s
		var boon_h := (20.0 * s) if (boon != null and not preview) else 0.0
		var box := Rect2(6.0 * s, head_h + 5.0 * s,
			w - 12.0 * s, h - head_h - foot_h - boon_h - 17.0 * s)
		draw_rect(box, Color(acc.r, acc.g, acc.b, 0.35 * dim), false, 1.0)
		var gcol := Color(acc.r, acc.g, acc.b, 0.08 * dim)
		var gx := box.position.x + 19.0 * s
		while gx < box.end.x:
			draw_line(Vector2(gx, box.position.y), Vector2(gx, box.end.y), gcol, 1.0)
			gx += 19.0 * s
		var gy := box.position.y + 14.0 * s
		while gy < box.end.y:
			draw_line(Vector2(box.position.x, gy), Vector2(box.end.x, gy), gcol, 1.0)
			gy += 14.0 * s
		if face != null:
			var fp := _fingerprint(String(face.id))
			var fp_side := minf(68.0 * s, box.size.y - 8.0 * s)
			if fp != null:
				var fr := Rect2(box.position + (box.size - Vector2(fp_side, fp_side)) * 0.5,
					Vector2(fp_side, fp_side))
				draw_texture_rect(fp, fr, false, Color(1, 1, 1, dim))
			else:
				# 指纹缺图兜底:中央大字脸名(无素材环境的探针照跑)
				draw_string(zh, Vector2(box.position.x, box.position.y + box.size.y * 0.58),
					face.cn_name, HORIZONTAL_ALIGNMENT_CENTER, box.size.x,
					int(22.0 * s), Color(acc.r, acc.g, acc.b, 0.9 * dim))

		# ---- S4 金 boon 条(揭晓后) ----
		if boon != null and not preview:
			var bc := StageCard.boon_accent()
			var br := Rect2(6.0 * s, box.end.y + 4.0 * s, w - 12.0 * s, 16.0 * s)
			draw_style_box(StageTheme.box(Color(bc.r, bc.g, bc.b, 0.14),
				Color(bc.r, bc.g, bc.b, 0.68), 1, int(5.0 * s)), br)
			draw_string(zh, Vector2(br.position.x, br.position.y + 12.0 * s),
				"✦ %s" % boon.cn_name, HORIZONTAL_ALIGNMENT_CENTER, br.size.x,
				int(9.0 * s), bc)

		# ---- 结果脚 43s:左竖线 + 渐变底;command(白) + SIGNAL 短码 / live 状态 ----
		if face == null:
			return
		var fr2 := Rect2(7.0 * s, h - foot_h - 6.0 * s, w - 14.0 * s, foot_h)
		draw_rect(fr2, Color(acc.r, acc.g, acc.b, 0.10 * dim), true)
		draw_rect(Rect2(fr2.position, Vector2(2.0 * s, fr2.size.y)),
			Color(acc.r, acc.g, acc.b, 0.9 * dim), true)
		var copy: Dictionary = DB.ui().get("blindcard", {}).get(String(face.id), {})
		var command := String(copy.get("command", face.cn_name)) + roll_note
		var live_status := status_text != "" and not preview
		var span := status_text if live_status else String(copy.get("signal", ""))
		# 2026-08-11 文案重写成完整句后变长 —— 缩字到底仍装不下 13 字, 改两行:
		# command 用 multiline 最多两行(10s), 短码/状态行沉底。裁断句子比挤一点更伤。
		# ⚠⚠ **en 态换 Rajdhani**(2026-08-28):中文字体画拉丁字符走的是 CJK 度量,
		# 一行只剩 ~12 个字符 ⇒ 同一批文案 en 态有 **10 条**被 `max_lines=2` 静默截掉,
		# 而换 `num()` 量只剩 2 条 —— **病在字体选择,不是英文句子太长**,
		# 不该让作者去砍英文。cn 仍用 zh(中文本来就该走 CJK 度量)。
		# 契约锁在 `tests/t_lingo.gd` 第 ⑤ 层(两态各量各的字体)。
		var body: Font = zh if Lingo.lang() != "en" else StageTheme.num("Medium")
		draw_multiline_string(body, Vector2(fr2.position.x + 6.0 * s, fr2.position.y + 13.0 * s),
			command, HORIZONTAL_ALIGNMENT_LEFT, fr2.size.x - 10.0 * s,
			int(10.0 * s), 2, Color(HOT_INK.r, HOT_INK.g, HOT_INK.b, dim))
		draw_string(zh if live_status else med,
			Vector2(fr2.position.x + 6.0 * s, fr2.position.y + fr2.size.y - 5.0 * s),
			span, HORIZONTAL_ALIGNMENT_LEFT, fr2.size.x - 10.0 * s,
			int((9.0 if live_status else 8.0) * s), Color(acc.r, acc.g, acc.b, dim))


## The blind board (盲注公示) — the home screen's stage card, sized for use
## inside the game: same glass frame, same header/name/eq/target/rule flow.
## Shared by the shop header (compact) and the standalone intro card.
class BlindBoard:
	extends Control
	var section_idx := 0
	var target := 0
	var mod = null          # SectionMod or null
	var boon = null         # BlindBoon or null; positive and visually separate
	var prefix := ""        # "下一场" on the shop, "" on the intro card
	# 段中商店态(2026-08-06 商店与盲注解耦): >= 0 时这块板讲的不是「下一场是什么」
	# 而是「这一场还差多少」—— 玩家已经打了半个盲注, 买牌是解题不是下注。
	var score := -1
	var phrases_left := -1
	# 巡演路线行(journey #4, 2026-08-27):整局四场的脸缩略, [{name, state}] ——
	# state 0 已打过(✓+压暗)/ 1 当前段(档位色)/ 2 未来(常规)。
	# 只有商店注入它(Shop.set_route);空数组 = 不画, intro/教学不受影响。
	var route: Array = []
	var _t := 0.0
	var _eq: Control = null        # 均衡器层 —— 板上唯一在动的东西, 只有它每帧重画
	var _eq_rect := Rect2()        # 静态层排版时记下, 均衡器层照着画

	## 2026-08-21 评审:此前整块玻璃(背光 + 程序化玻璃 + 两个字号自适应 while 循环)每帧重画,
	## 而只有均衡器在动。静态部分现在只在 setup() 时重画。
	class EqLayer:
		extends Control
		var board = null
		func _draw() -> void:
			if board != null and board._eq_rect.size.x > 0.0:
				StageCard.eq_band(self, board._eq_rect, StageCard.accent_for(board.section_idx),
					board._t, board.section_idx, 26)

	func _ready() -> void:
		_eq = EqLayer.new()
		_eq.board = self
		_eq.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_eq.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_eq)
		set_process(true)

	func _process(delta: float) -> void:
		_t += delta
		if _eq != null:
			_eq.queue_redraw()

	func setup(p_section: int, p_target: int, p_mod, p_prefix: String,
			p_score: int = -1, p_left: int = -1, p_boon = null) -> void:
		section_idx = p_section
		target = p_target
		mod = p_mod
		boon = p_boon
		prefix = p_prefix
		score = p_score
		phrases_left = p_left
		queue_redraw()

	## 段中商店 = 盲注正在进行, 板子改讲进度
	func in_progress() -> bool:
		return phrases_left >= 0

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var acc := StageCard.accent_for(section_idx)
		var is_wall := GameConfig.is_wall(section_idx)
		# 交接件: 玻璃不带色, 颜色来自灯。局内没有首页那组激光, 所以给板子打一盏
		# 背光 —— 档位色照在玻璃后面, 而不是把玻璃染色。
		draw_texture_rect(PaperCard.glow_tex(),
			Rect2(-w * 0.35, -h * 0.55, w * 1.7, h * 2.1), false,
			Color(acc.r, acc.g, acc.b, 0.30))
		StageCard.draw_card(self, Rect2(0, 0, w, h), acc, 22.0, 14.0, false)

		var pad := 34.0
		var cw := w - pad * 2.0
		var zh := StageTheme.zh()
		var num := StageTheme.num("Bold")
		var med := StageTheme.num("Medium")

		# header: MODE line + the blind's index in the tour
		var head := "MODE: %s" % ("BOSS WALL" if is_wall else "BLIND")
		if in_progress():
			head = Lingo.t("本场进行中 · %s") % head
		elif prefix != "":
			head = "%s · %s" % [prefix, head]
		draw_string(med, Vector2(pad, 48), head, HORIZONTAL_ALIGNMENT_LEFT, cw, 14,
			Color(acc.r, acc.g, acc.b, 0.72))
		draw_string(med, Vector2(pad, 48), "BLIND %02d/%02d" % [section_idx + 1,
			GameConfig.SECTIONS_PER_RUN], HORIZONTAL_ALIGNMENT_RIGHT, cw, 14,
			Color(acc.r, acc.g, acc.b, 0.72))

		# name row: venue + blind tier, the mock's 48px hero line
		var venue := GameConfig.gig_name(section_idx)
		draw_string(zh, Vector2(pad, 94), venue, HORIZONTAL_ALIGNMENT_LEFT, cw, 34,
			Color("ffffff"))
		var tier := Lingo.t("BOSS 墙") if is_wall else GameConfig.blind_name(section_idx)
		var tw := zh.get_string_size(tier, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var chip := Rect2(w - pad - tw - 22.0, 66, tw + 22.0, 30)
		draw_style_box(StageTheme.box(Color(acc.r, acc.g, acc.b, 0.16),
			Color(acc.r, acc.g, acc.b, 0.65), 1, 8), chip)
		draw_string(zh, Vector2(chip.position.x, chip.position.y + 21.0), tier,
			HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, 17, Color("f2fbff"))
		StageCard.rule_line(self, pad, 110, cw, acc)

		# the equaliser band — the card's heartbeat(在 EqLayer 每帧画, 这里只记矩形)
		_eq_rect = Rect2(pad, 118, cw, 44)

		# hero number. 段末商店讲目标分; 段中商店讲**还差多少** —— 那才是这一刻
		# 要做的决策所依赖的数(用户 2026-08-06:「买牌时看着目标买」)。
		var deficit: int = maxi(0, target - score)
		var met := in_progress() and deficit <= 0
		var ttxt := StageTheme.fmt_thousands(deficit if in_progress() else target)
		var tcol := StageTheme.GOLD if met else Color("ffffff")
		if met:
			ttxt = Lingo.t("已达标")
		draw_string(num if not met else zh, Vector2(pad, 202), ttxt,
			HORIZONTAL_ALIGNMENT_LEFT, cw, 42 if not met else 32, tcol)
		var tnw := (num if not met else zh).get_string_size(
			ttxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 42 if not met else 32).x
		if not met:
			draw_string(zh, Vector2(pad + tnw + 10.0, 202),
				Lingo.t("还差") if in_progress() else Lingo.t("目标分"),
				HORIZONTAL_ALIGNMENT_LEFT, cw, 15, StageTheme.DIM)
		if in_progress():
			# the running score sits where the wage chip does on the next-blind board
			draw_string(med, Vector2(pad, 202), Lingo.t("已得 %s / %s")
				% [StageTheme.fmt_thousands(score), StageTheme.fmt_thousands(target)],
				HORIZONTAL_ALIGNMENT_RIGHT, cw, 17, StageTheme.DIM)
		else:
			draw_string(med, Vector2(pad, 202), Lingo.t("奖励 ◆%d") % GameConfig.SECTION_CLEAR_REWARD,
				HORIZONTAL_ALIGNMENT_RIGHT, cw, 17,
				Color(StageTheme.GOLD.r, StageTheme.GOLD.g, StageTheme.GOLD.b, 0.95))

		# footer: play limits on the left, boss rule (or its absence) right
		var limits := Lingo.t("%d 乐句 · %.0f 秒/句") % [GameConfig.PHRASES_PER_SECTION,
			GameConfig.phrase_duration(section_idx)]
		if in_progress():
			limits = Lingo.t("还剩 %d 拍 · %.0f 秒/句") % [phrases_left,
				GameConfig.phrase_duration(section_idx)]
		var limits_color: Color = StageTheme.DIM if not in_progress() else Color(acc.r, acc.g, acc.b, 0.92)
		if boon != null:
			limits = "✦ %s · %s" % [boon.cn_name, String(DB.ui().get("blindcard", {})
				.get(String(boon.id), {}).get("command", boon.fx_text))]
			limits_color = StageCard.boon_accent()
		# ⚠ 脸胶囊**先算后画**, limits 行的可用宽度让给它 —— 两者同一条视觉带,
		# 中文短看不出来, 英文一长就叠(2026-08-19 en 截图抓到 boon 行被胶囊压字)。
		var limits_w := cw
		if mod != null:
			# 脸说明走 ui.json 的中文 command(2026-08-12 截图抓到公示板还在
			# 说英文 fx —— 上一轮文案汉化漏了这两行), 英文 fx 只做兜底
			var ftxt := "⚠ %s · %s" % [mod.cn_name, String(DB.ui().get("blindcard", {})
				.get(String(mod.id), {}).get("command", mod.fx_text))]
			var ffs := 14
			while ffs > 10 and med.get_string_size(ftxt, HORIZONTAL_ALIGNMENT_LEFT, -1, ffs).x > cw - 20.0:
				ffs -= 1
			var fw: float = minf(cw, med.get_string_size(ftxt, HORIZONTAL_ALIGNMENT_LEFT, -1, ffs).x + 22.0)
			var fr := Rect2(w - pad - fw, 216, fw, 30)
			draw_style_box(StageTheme.box(
				Color(StageTheme.PINK.r, StageTheme.PINK.g, StageTheme.PINK.b, 0.14),
				Color(StageTheme.PINK.r, StageTheme.PINK.g, StageTheme.PINK.b, 0.60), 1, 9), fr)
			draw_string(med, Vector2(fr.position.x, fr.position.y + 20.0), ftxt,
				HORIZONTAL_ALIGNMENT_CENTER, fr.size.x, ffs, Color("ffa8c6"))
			limits_w = maxf(0.0, fr.position.x - pad - 10.0)
		var lfs := 15
		while lfs > 10 and zh.get_string_size(limits,
				HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x > limits_w:
			lfs -= 1
		draw_string(zh, Vector2(pad, 232), limits,
			HORIZONTAL_ALIGNMENT_LEFT, limits_w, lfs, limits_color)

		# 巡演路线行(journey #4):商店 = 构筑决策点, versus 的调度解法要求在这里
		# 看得到整局四张脸(开局特写的路线行看完就没了)。已打过 = ✓+压暗 ·
		# 当前 = 档位色(叠一层低 alpha 当辉光)· 未来 = 常规。空数组 = 不画。
		# 坐标/字号在 data/ui.json 的 shop.route_y / route_fs(坐标归 ui.json 铁律)。
		if not route.is_empty():
			var rcfg: Dictionary = DB.ui().get("shop", {})
			var ry := float(rcfg.get("route_y", 264.0))
			var rfs := int(rcfg.get("route_fs", 14))
			var sep := " → "
			var texts: Array = []
			for e in route:
				texts.append(("✓" + String(e["name"])) if int(e["state"]) == 0
					else String(e["name"]))
			# 一行放不下就收字号(中文名短, 英文名长 —— 与 limits 行同一条收法)
			while rfs > 9:
				var wsum := zh.get_string_size(sep,
					HORIZONTAL_ALIGNMENT_LEFT, -1, rfs).x * float(texts.size() - 1)
				for s in texts:
					wsum += zh.get_string_size(String(s),
						HORIZONTAL_ALIGNMENT_LEFT, -1, rfs).x
				if wsum <= cw:
					break
				rfs -= 1
			var rx := pad
			for i in range(texts.size()):
				var seg := String(texts[i])
				var st := int(route[i]["state"])
				var col: Color = StageTheme.rim(0.34) if st == 0 \
					else (Color(acc.r, acc.g, acc.b, 1.0) if st == 1 else StageTheme.rim(0.60))
				if st == 1:
					draw_string(zh, Vector2(rx, ry), seg,
						HORIZONTAL_ALIGNMENT_LEFT, -1, rfs, Color(acc.r, acc.g, acc.b, 0.40))
				draw_string(zh, Vector2(rx, ry), seg, HORIZONTAL_ALIGNMENT_LEFT, -1, rfs, col)
				rx += zh.get_string_size(seg, HORIZONTAL_ALIGNMENT_LEFT, -1, rfs).x
				if i < texts.size() - 1:
					draw_string(zh, Vector2(rx, ry), sep,
						HORIZONTAL_ALIGNMENT_LEFT, -1, rfs, StageTheme.rim(0.25))
					rx += zh.get_string_size(sep, HORIZONTAL_ALIGNMENT_LEFT, -1, rfs).x


## ⚑ 消耗品格(2026-08-29 开轴)。两格, 摆在**手牌区上方那条 66px 空带**
## (y 672..738, 原本只有装饰轨道)——用户提的位置, 而它恰好是最省认知的一处:
## 玩家判断手牌时视线本来就扫过那里, 不像顶栏那样要额外抬眼。
##
## ⚠ **热区必须比视觉大**:视觉 60×60, 但 `size` 给 88 —— 8 秒一拍、
## 认知已占 3.37 秒, 一个点不准的小按钮会直接吃掉玩家的时间预算。
## ⚠ 空格画成虚线轮廓而不是隐藏 —— 「我有几格、空着几格」必须一眼可见,
## 否则玩家不会记得自己还能拿牌(与缓存区恒满 3 格同一条理由)。
class ConsumableSlot:
	extends Button
	signal used(idx: int)
	var idx := 0
	var accent := Color.WHITE
	var label := ""          # 卡的短名(cn/en 走 Lingo.pick, 由调用方填)
	var filled := false
	var armed := true        # 当前语境能不能点(phrase/shop 时机门)
	const VIS := 60.0        # 视觉边长;热区 = size(88), 差额是留给手指的
	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		pressed.connect(func() -> void:
			if filled and armed:
				used.emit(idx))
	## ⚠ 画法跟全屏统一:**暗玻璃底 + 主色描边 + 外发光**(CLAUDE.md 美术方向)。
	## 第一版画的是硬边方框, 渲染出来跟周围的圆角发光件格格不入 —— 「改了视觉
	## 就渲染出来自己看」这条纪律当场兑现。
	func _draw() -> void:
		var c := Vector2(size.x, size.y) * 0.5
		var r := Rect2(c - Vector2(VIS, VIS) * 0.5, Vector2(VIS, VIS))
		var rad := 10.0
		if not filled:
			# 空格:只留一圈极淡的轮廓 —— 「这里有个位置」要看得见, 否则玩家不知道自己能拿牌
			draw_style_box(StageTheme.box(Color(0, 0, 0, 0),
				Color(accent.r, accent.g, accent.b, 0.10), 2, int(rad)), r.grow(-1.0))
			return
		var a := 1.0 if armed else 0.32     # 时机不对压暗, 但仍可见(不是隐藏)
		# ⚠ **不走 `draw_card`** —— 它会贴 glass 素材, 而九宫格在这种小板尺寸下必坏
		# (CLAUDE.md 明写)。这里用程序化圆角 `StageTheme.box`, 与顶栏/商店板同一条路。
		for i in range(3):                                   # 外发光:三层递减
			var g := 1.0 - float(i) / 3.0
			draw_style_box(StageTheme.box(Color(0, 0, 0, 0),
				Color(accent.r, accent.g, accent.b, 0.11 * g * a), 2, int(rad + i * 2)),
				r.grow(float(i) * 2.0))
		draw_style_box(StageTheme.box(Color(0.02, 0.02, 0.05, 0.82 * a),
			Color(accent.r, accent.g, accent.b, 0.85 * a), 2, int(rad)), r)
		var f: Font = StageTheme.zh()
		var fs := 12
		var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		while w > VIS - 10.0 and fs > 9:
			fs -= 1
			w = f.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(f, r.position + Vector2((VIS - w) * 0.5, VIS * 0.5 + fs * 0.36),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(1, 1, 1, a) if armed else Color(accent.r, accent.g, accent.b, a))


class DJKey:
	extends Button
	signal dropped(data: Dictionary)
	var accent := Color.WHITE
	var zh_label := ""
	var kind := "sort"      # "sort" | "discard" | "reshuffle"(洗牌走热键画法, 图标同 shuffle)
	var radius := 46.0      # 洗牌键是 72×72 的紧凑款, 圆环半径跟着尺寸走(2026-08-26)
	var fee := 0
	var active := true
	var accept_drop := false
	var _shake_t := 0.0
	func _init() -> void:
		set_process(false)
		flat = true
		focus_mode = Control.FOCUS_NONE
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		return accept_drop and data is Dictionary \
			and not bool(data.get("discard_blocked", false)) \
			and ["hand", "cache"].has(data.get("zone", ""))
	func _drop_data(_pos: Vector2, data: Variant) -> void:
		dropped.emit(data)
	## dcshake — the key jolts when the press could not be honoured, so a
	## rejected tap is never silent.
	func shake() -> void:
		_shake_t = 0.4
		set_process(true)
		queue_redraw()

	func _process(delta: float) -> void:
		_shake_t = maxf(0.0, _shake_t - delta)
		if _shake_t <= 0.0:
			set_process(false)
		queue_redraw()

	## keyframes 0% 0 → 25% -6 → 50% +5 → 75% -3 → 100% 0
	func _shake_x() -> float:
		if _shake_t <= 0.0:
			return 0.0
		var u: float = 1.0 - _shake_t / 0.4
		var keys := [0.0, -6.0, 5.0, -3.0, 0.0]
		var seg: float = clampf(u * 4.0, 0.0, 3.999)
		var i := int(seg)
		var f: float = seg - float(i)
		return lerpf(float(keys[i]), float(keys[i + 1]), f)

	func _draw() -> void:
		draw_set_transform(Vector2(_shake_x(), 0.0), 0.0, Vector2.ONE)
		# outlined neon ring, not a filled disc: a dark well, a glow halo, a
		# 2px accent ring and a dashed inner ring — matching the mock.
		var cx := size.x * 0.5
		var cy := size.y * 0.5
		var c := Vector2(cx, cy)
		var r := radius
		var a := 1.0 if active else 0.5
		draw_circle(c, r, Color(0.035, 0.045, 0.11, 0.62 * a))
		if kind == "sort":
			# a dial: empty dark well ringed by a dashed track
			draw_arc(c, r + 3.0, 0, TAU, 64, Color(accent.r, accent.g, accent.b, 0.20 * a), 8.0, true)
			draw_arc(c, r, 0, TAU, 64, Color(accent.r, accent.g, accent.b, 0.95 * a), 2.2, true)
			for i in range(24):
				if i % 2 == 1:
					continue
				var a0 := TAU * float(i) / 24.0
				draw_arc(c, r - 9.0, a0, a0 + TAU / 24.0 * 0.75, 4,
					Color(accent.r, accent.g, accent.b, 0.38 * a), 1.3, true)
		else:
			# a hot button: the well is lit from the rim inward, the ring is
			# solid and doubled, and hazard ticks run around the outside
			var gd := r * 1.85
			draw_texture_rect(PaperCard.glow_tex(), Rect2(c - Vector2(gd, gd) * 0.5,
				Vector2(gd, gd)), false, Color(accent.r, accent.g, accent.b, 0.26 * a))
			draw_arc(c, r + 4.0, 0, TAU, 64, Color(accent.r, accent.g, accent.b, 0.24 * a), 10.0, true)
			draw_arc(c, r, 0, TAU, 64, Color(accent.r, accent.g, accent.b, 1.0 * a), 2.8, true)
			draw_arc(c, r - 8.0, 0, TAU, 64, Color(accent.r, accent.g, accent.b, 0.5 * a), 1.4, true)
			for i in range(12):
				var ta := TAU * float(i) / 12.0
				var d := Vector2(cos(ta), sin(ta))
				draw_line(c + d * (r + 6.0), c + d * (r + 12.0),
					Color(accent.r, accent.g, accent.b, 0.45 * a), 1.6, true)

		var ic := Color(accent.r, accent.g, accent.b, a)
		if kind == "sort":
			# ⇅ : up arrow on the left, down arrow on the right
			_arrow(Vector2(cx - 8, cy + 13), Vector2(cx - 8, cy - 13), ic)
			_arrow(Vector2(cx + 8, cy - 13), Vector2(cx + 8, cy + 13), ic)
		elif kind == "reshuffle":
			# 循环箭头(↻)—— 「弃牌堆洗回重发」;不复用弃牌键的交叉箭头:
			# 两个圆键同图标时只剩颜色在做区分, 色弱读不出来。
			var rr := r * 0.38
			draw_arc(c, rr, PI * 0.2, PI * 1.8, 28, ic, 2.4, true)
			var ea := PI * 1.8
			var tip := c + Vector2(cos(ea), sin(ea)) * rr
			var tangent := Vector2(-sin(ea), cos(ea))
			_arrow(tip - tangent * 6.0, tip + tangent * 4.0, ic)
		else:
			# shuffle: two paths that enter flat from the left, cross in the
			# middle and exit right — both heads point the same way. (Two
			# opposed arrows just read as a cross.)
			_shuffle(c, ic)

		# fee badge: dark pill with a gold ring, top-right of the ring
		if kind != "sort" and fee > 0 and active:
			var badge := Rect2(cx + r - 30.0, cy - r - 12.0, 50, 26)
			draw_style_box(StageTheme.box(Color(0.06, 0.05, 0.02, 0.9), StageTheme.GOLD, 1, 13), badge)
			draw_string(StageTheme.num("Bold"), Vector2(badge.position.x, badge.position.y + 19),
				"◆%d" % fee, HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, 15, StageTheme.GOLD)

		# label, glowing in the accent colour
		var lc: Color = Color(accent.r, accent.g, accent.b, a)
		draw_string(StageTheme.zh(), Vector2(0, cy + r + 32), zh_label,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Color(lc.r, lc.g, lc.b, lc.a * 0.45))
		draw_string(StageTheme.zh(), Vector2(0, cy + r + 32), zh_label,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, lc)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	## the shuffle glyph: ⇄ with both heads to the right
	func _shuffle(c: Vector2, col: Color) -> void:
		for dir_v in [-1.0, 1.0]:
			var d: float = dir_v
			var pts := PackedVector2Array([
				c + Vector2(-19, 11 * d), c + Vector2(-11, 11 * d),
				c + Vector2(8, -11 * d), c + Vector2(15, -11 * d)])
			draw_polyline(pts, col, 2.4, true)
			_head(c + Vector2(15, -11 * d), Vector2.RIGHT, col)

	## chevron head at `at`, opening against `dir`
	func _head(at: Vector2, dir: Vector2, col: Color) -> void:
		var n := Vector2(-dir.y, dir.x)
		draw_line(at, at - dir * 7.0 + n * 5.0, col, 2.2, true)
		draw_line(at, at - dir * 7.0 - n * 5.0, col, 2.2, true)

	## thin line with a chevron head at `to`
	func _arrow(from: Vector2, to: Vector2, col: Color) -> void:
		draw_line(from, to, col, 2.2, true)
		var d := (to - from).normalized()
		var n := Vector2(-d.y, d.x)
		draw_line(to, to - d * 7.0 + n * 5.0, col, 2.2, true)
		draw_line(to, to - d * 7.0 - n * 5.0, col, 2.2, true)
