class_name StageTheme
extends RefCounted

## Neon-stage palette + fonts + stylebox helpers (locked art direction, style A).
## Paper playing cards on a dark neon stage; jokers stay dark/neon.

# --- stage ---
# 2026-08-06 背景**归黑**(用户两轮:先「压暗」后「做成黑色吧」)。
# 旧值 101430/181f48/232b62 是海军蓝, 把整个舞台抬灰;中间稿 05060f 仍带蓝。
# 现在底色 = 黑, 梯子只留极微的一点抬升(避免纯平)。**画面里的光全部由光效层
# 承担**(激光/探照灯/光斑/柔光/霓虹边), 底色不再贡献任何亮度 —— 这和五张玻璃卡
# 参考图一致: 卡躺在纯黑上, 霓虹才炸得出来。
static var BG0: Color = _c("bg0")
static var BG2: Color = _c("bg2")
static var INK: Color = _c("ink")
static var DIM: Color = _c("dim")
static var LINE: Color = _c("line")
# 主色以 assets/reference/ 的规格为准(2026-08-06 用户:「没有赛博朋克的感觉…
# 这个蓝和你现在的蓝不一样」—— 逐个对了一遍, 五个常量全都比规格浅一档,
# 每个"差一点"加起来就是"不像"。spec = Neon Rain Card Game.dc.html 的出现频次表)。
# 2026-08-06 二次校色:用户「这真的是一个红色吗」——把五张玻璃卡参考图的**辉光带**
# (未被烧白、未被体色压暗的区域)逐张采样, 归一到 v=1。上一轮只对了色值大小,
# **色相与饱和度没对**:五个颜色的饱和度全线偏低 0.07-0.11, RED 的色相更是差了 9°
# (我们 354° 是珊瑚粉红, 参考 1° 是纯正猩红)。
# 实测 (色相, 饱和): pink .926/.76-.97 · purple .713/.66-.89 · green .484/.91-1.0
#                    gold .085/.84-.98 · red .003/.78-.99
static var CYAN: Color = _c("cyan")    # h.486 s.88
static var VIOLET: Color = _c("violet")  # h.713 s.74
static var PINK: Color = _c("pink")    # h.926 s.80
static var AMBER: Color = _c("amber")   # h.088 s.83
static var GOLD: Color = _c("gold")
# 盲注档位色(交接件列的主题色): 蓝 → 橙 → 红, 逐档升温
static var SLATE: Color = _c("slate")   # 中性冷灰蓝: 全局 chrome(顶栏)用, 不跟关卡变色
# 档位蓝 = **电光蓝**, 采自 ref_wetfloor_club.png 的 BASS 卡(最亮饱和像素
# #23cdff, 色相 197°)。旧值 5fa8ff 是 217° 的灰蓝 —— 赛博朋克感就是被它杀掉的。
static var BLUE: Color = _c("blue")
static var RED: Color = _c("red")     # h.003 s.80 —— 纯红, 不是 354° 的珊瑚粉

# --- neon GLASS cards (spec: docs/mockups/整副卡牌.dc.html · 1a 玻璃底 × 2a 传统点阵) ---
static var GLASS_BODY: Color = _c("glass_body")   # flat blend for the stylebox
static var SUIT_RED: Color = _c("suit_red")                       # ♥ ♦
static var SUIT_BLK: Color = _c("suit_blk")                       # ♠ ♣
static var FRAME_RED: Color = _c("frame_red")
static var FRAME_BLK: Color = _c("frame_blk")
static var MARKED: Color = _c("marked")                         # 待弃 highlight
static var CARD_INK: Color = _c("card_ink")                       # rank glyphs
static var CACHE_ACCENT: Color = _c("cache_accent")                   # cache slots read violet

## 色板从 data/theme.json 读(2026-09-06 搬家, 镜像与 Godot 同一份);字符串 = #rrggbb, 数组 = [r,g,b,a]。
static func _c(key: String) -> Color:
	var v = DB.theme().get(key)
	if v is String:
		return Color(String(v))
	if v is Array and v.size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]) if v.size() > 3 else 1.0)
	push_error("[StageTheme] theme.json 缺色 '%s'" % key)
	return Color.MAGENTA


static func frame_color(card: Card) -> Color:
	return FRAME_RED if card.is_red() else FRAME_BLK

# kept so older call sites still compile

static var _fonts := {}

## Web 没有系统字体 —— 兜底链两件套(2026-08-12,均按全仓语料子集化,OFL):
## Noto Sans SC(中文,800KB/1588 字)+ Noto Sans Symbols 2(▸◈⚡✦✧ 这类
## SC 没有的装饰符)。桌面照旧先走系统字,行为不变。
## ⚠ 文案新增了此前没用过的字要重跑子集:tools/art/fontsubset.sh
static func _bundled_fallbacks() -> Array[Font]:
	if not _fonts.has("_fb"):
		var out: Array[Font] = []
		for p in ["res://assets/fonts/NotoSansSC-Sync5.ttf",
				"res://assets/fonts/NotoSymbols2-Sync5.ttf"]:
			if ResourceLoader.exists(p):
				out.append(load(p))
		_fonts["_fb"] = out
	return _fonts["_fb"]


static func num(weight: String = "SemiBold") -> Font:
	# Rajdhani ships Medium/SemiBold/Bold here; anything else maps to Medium.
	var w := weight
	if not ["Medium", "SemiBold", "Bold"].has(w):
		w = "Medium"
	var key := "num_" + w
	if not _fonts.has(key):
		var f: FontFile = load("res://assets/fonts/Rajdhani-%s.ttf" % w)
		# num/med 排过混排中文(「奖励 ◆3」「BOSS 规则」)——桌面靠系统字
		# 静默兜底,Web 上没这条路,不挂链子就是成片豆腐(实测)。
		f.fallbacks = _bundled_fallbacks()
		_fonts[key] = f
	return _fonts[key]


static func zh() -> Font:
	if not _fonts.has("zh"):
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["PingFang SC", "Noto Sans SC", "Hiragino Sans GB", "sans-serif"])
		f.fallbacks = _bundled_fallbacks()
		_fonts["zh"] = f
	return _fonts["zh"]

static func suit_color(card: Card) -> Color:
	return SUIT_RED if card.is_red() else SUIT_BLK

static func label(text: String, font: Font, size: int, color: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l

## Cyan chrome tint for panel captions — grey text was what made the info bar
## read as a different app.
static func rim(a: float) -> Color:
	return Color(CYAN.r, CYAN.g, CYAN.b, a)


## 12,345-style thousands grouping — 万-scale targets are unreadable raw.
static func fmt_thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out

static func box(bg: Color, border: Color, border_w: int, radius: int,
		glow: Color = Color(0, 0, 0, 0), glow_size: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.set_corner_radius_all(radius)
	if glow_size > 0:
		sb.shadow_color = glow
		sb.shadow_size = glow_size
	return sb

static func vgradient(top: Color, bottom: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, top)
	g.set_color(1, bottom)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 8
	t.height = 512
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	return t

static func radial(color: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 256
	t.height = 256
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t
