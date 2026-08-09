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
const BG0 := Color("000000")
const BG1 := Color("030308")
const BG2 := Color("07070f")
const INK := Color("eef1fb")
const DIM := Color("9aa2c8")
const FAINT := Color("5e669a")
const LINE := Color(0.63, 0.71, 1.0, 0.22)
# 主色以 assets/reference/ 的规格为准(2026-08-06 用户:「没有赛博朋克的感觉…
# 这个蓝和你现在的蓝不一样」—— 逐个对了一遍, 五个常量全都比规格浅一档,
# 每个"差一点"加起来就是"不像"。spec = Neon Rain Card Game.dc.html 的出现频次表)。
# 2026-08-06 二次校色:用户「这真的是一个红色吗」——把五张玻璃卡参考图的**辉光带**
# (未被烧白、未被体色压暗的区域)逐张采样, 归一到 v=1。上一轮只对了色值大小,
# **色相与饱和度没对**:五个颜色的饱和度全线偏低 0.07-0.11, RED 的色相更是差了 9°
# (我们 354° 是珊瑚粉红, 参考 1° 是纯正猩红)。
# 实测 (色相, 饱和): pink .926/.76-.97 · purple .713/.66-.89 · green .484/.91-1.0
#                    gold .085/.84-.98 · red .003/.78-.99
const CYAN := Color("1effec")    # h.486 s.88
const VIOLET := Color("7642ff")  # h.713 s.74
const PINK := Color("ff328d")    # h.926 s.80
const AMBER := Color("ff9b2b")   # h.088 s.83
const GOLD := Color("ffd36e")
# 盲注档位色(交接件列的主题色): 蓝 → 橙 → 红, 逐档升温
const SLATE := Color("7b88ab")   # 中性冷灰蓝: 全局 chrome(顶栏)用, 不跟关卡变色
# 档位蓝 = **电光蓝**, 采自 ref_wetfloor_club.png 的 BASS 卡(最亮饱和像素
# #23cdff, 色相 197°)。旧值 5fa8ff 是 217° 的灰蓝 —— 赛博朋克感就是被它杀掉的。
const BLUE := Color("23cdff")
const RED := Color("ff3632")     # h.003 s.80 —— 纯红, 不是 354° 的珊瑚粉
const SURFACE := Color("232b58")
const SURFACE_DARK := Color("1b2247")

# --- neon GLASS cards (spec: resources/整副卡牌.dc.html · 1a 玻璃底 × 2a 传统点阵) ---
const GLASS_TOP := Color(30.0 / 255, 12.0 / 255, 32.0 / 255, 0.72)
const GLASS_BOT := Color(10.0 / 255, 6.0 / 255, 20.0 / 255, 0.82)
const GLASS_BODY := Color(0.078, 0.035, 0.102, 0.80)   # flat blend for the stylebox
const SUIT_RED := Color("ff6aa9")                       # ♥ ♦
const SUIT_BLK := Color("9fe9ff")                       # ♠ ♣
const FRAME_RED := Color(1.0, 79.0 / 255, 163.0 / 255, 0.85)
const FRAME_BLK := Color(53.0 / 255, 232.0 / 255, 224.0 / 255, 0.75)
const MARKED := Color("ffb347")                         # 待弃 highlight
const CARD_INK := Color("fdf4ff")                       # rank glyphs
const CACHE_ACCENT := Color("a56bff")                   # cache slots read violet

static func frame_color(card: Card) -> Color:
	return FRAME_RED if card.is_red() else FRAME_BLK

# kept so older call sites still compile
const PAPER0 := GLASS_BODY
const PAPER_EDGE := FRAME_BLK
const PAPER_INNER := Color(0.63, 0.71, 1.0, 0.22)

static var _fonts := {}

static func num(weight: String = "SemiBold") -> Font:
	# Rajdhani ships Medium/SemiBold/Bold here; anything else maps to Medium.
	var w := weight
	if not ["Medium", "SemiBold", "Bold"].has(w):
		w = "Medium"
	var key := "num_" + w
	if not _fonts.has(key):
		_fonts[key] = load("res://assets/fonts/Rajdhani-%s.ttf" % w)
	return _fonts[key]

static func zh() -> Font:
	if not _fonts.has("zh"):
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["PingFang SC", "Noto Sans SC", "Hiragino Sans GB", "sans-serif"])
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
