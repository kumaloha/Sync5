extends RefCounted

## Stat(tools/stat.gd)的 bit-identical 契约 —— 这是「新旧实现同输入逐位相等」的
## 主仪器(2026-08-09 收口 tools/{addit,blind,coin,gate,lam,model,price,warm}.gd
## 里各抄一份的 _mean/_var/_paired)。下面 _ref_* 是**原实现原样照抄**的参照组,
## 断言用 `==`(不用 is_equal_approx)—— 浮点累加顺序一变就会露馅, 那正是要抓的。

func run(t) -> void:
	var cases: Array = []
	cases.append([])                      # 空数组
	cases.append([0.0])                   # 单元素
	cases.append([42.0])                  # 单元素(非零)
	cases.append([-3.0, 5.0])             # 含负数, 双元素
	cases.append([-1e12, 1e12, 3.5])      # 很大的数
	cases.append([1, 2, 3, 4, 5])         # int 元素(混合类型, 靠 float() 转)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260809
	for trial in range(6):
		var n: int = rng.randi_range(2, 200)
		var arr: Array = []
		for i in range(n):
			arr.append(rng.randf_range(-1000.0, 1000.0))
		cases.append(arr)

	for c in cases:
		t.eq(Stat.mean(c), _ref_mean(c), "mean bit-identical, n=%d" % c.size())
		t.eq(Stat.variance(c), _ref_var(c), "variance bit-identical, n=%d" % c.size())

	# _paired:逐对用例覆盖等长/不等长(mini 截断)、空数组
	var pairs: Array = [
		[[], []],
		[[1.0], [2.0]],
		[[-3.0, 5.0], [1.0, -2.0]],
		[[1.0, 2.0, 3.0], [4.0, 5.0]],          # a 比 b 长 -> 截到 b.size()
		[[4.0, 5.0], [1.0, 2.0, 3.0]],          # b 比 a 长 -> 截到 a.size()
	]
	for trial in range(4):
		var n: int = rng.randi_range(3, 150)
		var a: Array = []
		var b: Array = []
		for i in range(n):
			a.append(rng.randf_range(-500.0, 500.0))
			b.append(rng.randf_range(-500.0, 500.0))
		pairs.append([a, b])

	for p in pairs:
		var got: Dictionary = Stat.paired(p[0], p[1])
		var want: Dictionary = _ref_paired(p[0], p[1])
		t.eq(got["d"], want["d"], "paired.d bit-identical, na=%d nb=%d" % [p[0].size(), p[1].size()])
		t.eq(got["se"], want["se"], "paired.se bit-identical, na=%d nb=%d" % [p[0].size(), p[1].size()])


## --- 参照组:原样照抄自 tools/addit.gd(改前的 8 份逐字相同) ---

func _ref_mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())


func _ref_var(a: Array) -> float:
	if a.size() < 2:
		return 0.0
	var m := _ref_mean(a)
	var s := 0.0
	for v in a:
		s += (float(v) - m) * (float(v) - m)
	return s / float(a.size() - 1)


func _ref_paired(a: Array, b: Array) -> Dictionary:
	var n: int = mini(a.size(), b.size())
	var diffs: Array = []
	for i in range(n):
		diffs.append(float(b[i]) - float(a[i]))
	return {"d": _ref_mean(diffs), "se": sqrt(_ref_var(diffs) / maxf(1.0, float(n)))}
