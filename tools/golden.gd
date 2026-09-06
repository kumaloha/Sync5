extends SceneTree

## 金样生成器(docs/design/mirror.md §6)—— Godot 侧算出「期望」, 写成 lua/golden/<族>.lua,
## Lua 镜像用 lua/check.lua 重放比对。**生成物手改无效**;改了 core/ 就重跑本脚本。
##   godot --headless --path . --script res://tools/golden.gd            # 全部五族
##   SYNC5_GOLDEN=rng,pattern godot --headless --path . --script res://tools/golden.gd
## ⚠ 浮点一律写成 H"<f64hex>"(IEEE 位串), 不写十进制 —— 两边 printf 的最后一位不可信。

const OUT_DIR := "res://lua/golden"

func _initialize() -> void:
	var only := OS.get_environment("SYNC5_GOLDEN")
	var fams := {
		"rng": Callable(self, "_fam_rng"),
	}
	var n := 0
	for name in fams:
		if only != "" and not only.split(",").has(name):
			continue
		var body: String = fams[name].call()
		_write("%s/%s.lua" % [OUT_DIR, name], body)
		n += 1
	print("golden: wrote %d families" % n)
	quit(0)


func _write(path: String, body: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("golden: cannot write " + path)
		quit(1)
		return
	f.store_string("-- 由 tools/golden.gd 生成 —— 仪器输出, 手改无效(docs/design/mirror.md §6)\n")
	f.store_string(body)
	f.close()
	print("  wrote ", path, " (", body.length(), " chars)")


# ---------------------------------------------------------------- Lua 序列化

static func f64hex(x: float) -> String:
	var b := PackedFloat64Array([x]).to_byte_array()
	var s := ""
	for i in range(7, -1, -1):
		s += "%02x" % b[i]
	return s


static func state_hex(st: int) -> String:
	return "%08x%08x" % [(st >> 32) & 0xFFFFFFFF, st & 0xFFFFFFFF]


static func lstr(s: String) -> String:
	var out := "\""
	for ch in s:
		match ch:
			"\\": out += "\\\\"
			"\"": out += "\\\""
			"\n": out += "\\n"
			"\r": out += "\\r"
			"\t": out += "\\t"
			_: out += ch
	return out + "\""


## 任意 Variant → Lua 字面量。int → 十进制, float → H"hex", null → nil, Object → 走它的 to_golden()(若有)。
static func lua(v) -> String:
	match typeof(v):
		TYPE_NIL: return "nil"
		TYPE_BOOL: return "true" if v else "false"
		TYPE_INT: return "%d" % v
		TYPE_FLOAT: return "H\"%s\"" % f64hex(v)
		TYPE_STRING, TYPE_STRING_NAME: return lstr(String(v))
		TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			var parts: Array = []
			for e in v:
				parts.append(lua(e))
			return "{" + ",".join(parts) + "}"
		TYPE_DICTIONARY:
			var parts: Array = []
			for k in v:
				var ks: String
				if typeof(k) == TYPE_INT:
					ks = "[%d]" % k
				else:
					ks = "[%s]" % lstr(String(k))
				parts.append(ks + "=" + lua(v[k]))
			return "{" + ",".join(parts) + "}"
		TYPE_OBJECT:
			if v.has_method("to_golden"):
				return lua(v.to_golden())
			return lstr(str(v))
		_:
			return lstr(str(v))


# ---------------------------------------------------------------- rng 族

## 若干种子 × 混合调用序列;每一步的返回值都是期望。第 54 步记状态、第 104 步写回, 验 setter。
func _fam_rng() -> String:
	var seeds := [0, 1, -1, 2147483648, 4294967301, 700000, 9007199254740991, -123456789012, 90000, 41000,
		12345, 2026, 777, 31337, 65536, 4294967295, 8675309, 999999937, 3, 42]
	var cases: Array = []
	for s in seeds:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var ops: Array = []
		var saved := 0
		for k in range(200):
			match k % 5:
				0: ops.append(["i", rng.randi()])
				1: ops.append(["r", 0, k + 1, rng.randi_range(0, k + 1)])
				2: ops.append(["r", -7, 7, rng.randi_range(-7, 7)])
				3: ops.append(["f", rng.randf()])
				4:
					ops.append(["s", state_hex(rng.state)])
					if k == 54:
						saved = rng.state
					if k == 104:
						rng.state = saved
						ops.append(["S", state_hex(saved)])
		cases.append({"seed": s, "ops": ops})
	return "return " + lua(cases) + "\n"
