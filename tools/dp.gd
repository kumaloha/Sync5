class_name DP
extends RefCounted

## ⏸ **重构:本轮整块不动**(见 [TODO.md](../TODO.md) 的 R6)。
## 这五份(`formal`/`dp`/`dpcheck`/`dpdiag`/`udp`)的骨架与统计要收进 `Stat`/`Probe`,
## **解锁条件是 S3 结案** —— `dpdiag`/`dpcheck` 是 S3(通关率低估 8.4pp, 主因未定位)
## **正在用的**诊断仪器,而 S3 的下一步大概率还要改它们。
## **在仪器还在用的时候改仪器**是本项目吃过亏的形状 —— 别顺手「合并一下」。

## **求解器的未来价值表**(规格 = `design/solving.md` 第三部分)。
##
## 目标(用户 2026-08-08):「**每段都达标的情况下的最大化平均分**」
##
##     max E[总分]   s.t. 每段 ρ_n ≥ T_n
##
## ⚑ **约束不需要显式写** —— 没达标 run 就结束了, 后面的分拿不到。
## 只要回报定义成「从现在到 **run 结束** 的期望总分」, 约束就编码在边界条件里。
##
## 状态 `(n 段号, g 缺口, r 剩余拍, b 构筑档)`, 约 2 万个, 两张表共约 320 KB。
##
## ⚠ **用「缺口」不用「累计得分」**:累计分会一路涨、上不封顶;缺口每段独立且有界,
## 因为转移里的 `max(0, g−s)` 把它钉死在 `T_n` 以内。**这是设计能成立的关键。**
## ⚠ **布尔「是否达标」不够** —— 还差 100 分和还差 5000 分, 剩 3 拍时打法完全不同。
##
## ⚠⚠ **本表不做决策, 它只提供价值。** 转移里没有 `max`, 因为拍内动作依赖**手牌**
## (52 张的组合, 进不了状态)。求解器拿它在真实手牌上做 argmax:
##
##     a* = argmax_a [ score(a) + V(n, max(0, g − score(a)), r−1, b) ]

const BINS := 60          # 缺口离散档数。⚠ 240 是过剩的:一拍打几百分, 一拍就跨几十档。


var _v: Array = []        # _v[n][b][r] -> Array(BINS+1)  期望总分
var _p: Array = []        # _p[n][b][r] -> Array(BINS+1)  通关概率
var _targets: Array = []  # 每段目标分
var _steps: Array = []    # 每段的离散化粒度 = T_n / BINS
var _n_sec := 0
var _k := 0
var _bands := 0


## 建表。
##
## suffix:  `suffix[n][b][r]` = 「第 n 段、构筑档 b、**还剩 r 拍**时, 后续 r 拍**总分**」的样本数组
## trans:   `trans[n][b]`     = Array(bands) 段末从档 b 转到各档的概率
## targets: 每段目标分
##
## ⚠⚠ **段内不做卷积。** 第一版从单拍分布卷积出多拍分布 —— **卷积就是在假设各拍独立**,
## 而实测那个假设是错的:通关率被系统性低估 8.5 个百分点, 且**加样本加档数都修不掉**
## (400 局 4 档时 z 反而涨到 −3.63 —— 那是真效应的签名, 不是噪声)。
## 机制上也说得通:**打出好牌型会消耗掉好牌, 下一拍手牌变差** —— 各拍是**负相关**的,
## 所以实际方差比独立假设小、分布更集中, 在「目标偏松」的区域就表现为 DP 低估。
##
## ⚑ **负相关不是统计瑕疵, 它就是决策内容本身** ——「这一拍打光好牌, 下一拍就差」
## 正是「留余力」的物理基础之一。假设独立等于看不见要解决的那个东西。
##
## 现在直接录**联合**的:「剩 r 拍还能打多少」。这个分布**天然包含拍间的一切相关**,
## 因为它是观测出来的, 不是推出来的。
## **教训:假设不只藏在参数里, 也藏在公式的形状里。卷积长得像数学, 但它是个假设。**
##
## ⚠ 段与段之间的链式转移**保留**(design/solving.md 第三部分)—— 那部分没有独立假设, 是精确的路径展开。
static func build(suffix: Array, trans: Array, targets: Array, k_beats: int) -> DP:
	var d := DP.new()
	d._n_sec = targets.size()
	d._k = k_beats
	d._bands = (suffix[0] as Array).size()
	d._targets = targets.duplicate()
	for n in range(d._n_sec):
		d._steps.append(maxf(1.0, float(targets[n]) / float(BINS)))
	for n in range(d._n_sec):
		var vb: Array = []
		var pb: Array = []
		for b in range(d._bands):
			var vr: Array = []
			var pr: Array = []
			for r in range(k_beats + 1):
				vr.append(_zeros())
				pr.append(_zeros())
			vb.append(vr)
			pb.append(pr)
		d._v.append(vb)
		d._p.append(pb)

	# ⚠ 段号**递减** —— 第 n 段要用第 n+1 段开局的值。
	for n in range(d._n_sec - 1, -1, -1):
		var step: float = d._steps[n]
		for b in range(d._bands):
			# 后续段的价值(达标才拿得到)
			var w_v := 0.0
			var w_p := 0.0
			if n == d._n_sec - 1:
				w_p = 1.0                      # 最后一段达标 = 通关
			else:
				var row: Array = trans[n][b]
				for b2 in range(d._bands):
					w_v += float(row[b2]) * float(d._v[n + 1][b2][k_beats][BINS])
					w_p += float(row[b2]) * float(d._p[n + 1][b2][k_beats][BINS])
			for r in range(k_beats + 1):
				var vcur: Array = d._v[n][b][r]
				var pcur: Array = d._p[n][b][r]
				if r == 0:
					# 剩 0 拍:g=0 才算达标
					for i in range(BINS + 1):
						vcur[i] = w_v if i == 0 else 0.0
						pcur[i] = w_p if i == 0 else 0.0
					continue
				var samples: Array = suffix[n][b][r]
				var mean_s := _mean(samples)
				for i in range(BINS + 1):
					var gap: float = float(i) * step
					# ⚠ 直接查经验分布 —— 不卷积, 所以不假设独立。
					var ok: float = _tail(samples, gap)
					# 分数**全额**拿到(目标是总分), 后续段的价值**只有达标才拿到**。
					vcur[i] = mean_s + ok * w_v
					pcur[i] = ok * w_p
	return d


## Pr[样本 >= gap]。⚠ 用经验分布, 不拟合 —— 实测提示分数分布可能重尾,
## 而正态近似恰好在重尾处错得最厉害, 那正是「差一点能不能翻盘」的关键区域。
static func _tail(samples: Array, gap: float) -> float:
	if samples.is_empty():
		return 0.0
	if gap <= 0.0:
		return 1.0
	var c := 0.0
	for v in samples:
		if float(v) >= gap:
			c += 1.0
	return c / float(samples.size())


static func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())


## 查表:还差 gap 分、剩 r 拍、第 n 段、构筑档 b —— 从这里到 run 结束的期望总分。
func v(n: int, gap: float, r: int, b: int) -> float:
	return float((_v[_cn(n)][_cb(b)][clampi(r, 0, _k)] as Array)[_gi(n, gap)])


## 同上, 但回报是「四段全过」。
func p(n: int, gap: float, r: int, b: int) -> float:
	return float((_p[_cn(n)][_cb(b)][clampi(r, 0, _k)] as Array)[_gi(n, gap)])


## 反解:第 n 段要让通关概率等于 target_p, 目标分该定多少。
## ⚠ **必须从后往前逐段调用**(design/solving.md 第三部分)——`T_{n+1}` 在第 n 段的边界条件里,
## 乱序反解会拿到一张过期的表。
func solve_target(n: int, target_p: float, b: int) -> float:
	var arr: Array = _p[_cn(n)][_cb(b)][_k]
	# P 关于缺口单调不增 —— 从小到大找第一个跌破 target_p 的档
	for i in range(BINS + 1):
		if float(arr[i]) <= target_p:
			return float(i) * _steps[_cn(n)]
	return float(BINS) * _steps[_cn(n)]


func _gi(n: int, gap: float) -> int:
	return clampi(int(round(maxf(0.0, gap) / _steps[_cn(n)])), 0, BINS)


func _cn(n: int) -> int:
	return clampi(n, 0, _n_sec - 1)


func _cb(b: int) -> int:
	return clampi(b, 0, _bands - 1)


static func _zeros() -> Array:
	var a: Array = []
	a.resize(BINS + 1)
	for i in range(BINS + 1):
		a[i] = 0.0
	return a
