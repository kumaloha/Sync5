class_name Stat
extends RefCounted

## 探针共用的统计函数(2026-08-09 收口 —— `_mean`/`_var`/`_paired` 曾在
## tools/{addit,blind,coin,gate,lam,model,price,warm}.gd 里各抄一份)。
## 纯函数替换,语义逐字照抄原实现,不许改动。
## ⚠ tools/{formal,dp,dpcheck,dpdiag,udp}.gd 是 S3 诊断仪器使用中,不动。


static func mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())


static func variance(a: Array) -> float:
	if a.size() < 2:
		return 0.0
	var m := mean(a)
	var s := 0.0
	for v in a:
		s += (float(v) - m) * (float(v) - m)
	return s / float(a.size() - 1)


static func paired(a: Array, b: Array) -> Dictionary:
	var n: int = mini(a.size(), b.size())
	var diffs: Array = []
	for i in range(n):
		diffs.append(float(b[i]) - float(a[i]))
	return {"d": mean(diffs), "se": sqrt(variance(diffs) / maxf(1.0, float(n)))}
