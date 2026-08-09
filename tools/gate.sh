#!/usr/bin/env bash
# 加内容之后要过的那道门。
#   tools/gate.sh              完整跑一遍(回归用)
#   tools/gate.sh <face_id>    只验这一张新脸(加了一张脸时用, 十几秒)
#
# 为什么要有它:2026-08-07 一次加 8 张脸 → 18 个坑, 最难查的几个都是多个新东西
# 互相干扰。用户拍板「慢慢加内容, 每次跑求解器/生成器」—— **那就得是一道固定的门,
# 不能靠自觉**。预算 ≤10 分钟(用户定的), 跑完会打印实际用时。
#
# ⚠ 读退出码别隔着管道:`godot ... | tail` 之后的 $? 是 tail 的。下面每一步都直接读。
set -uo pipefail
cd "$(dirname "$0")/.."

FACE="${1:-}"
T0=$SECONDS
FAILED=()

step() {  # step <名字> <命令...>
	local name="$1"; shift
	local t=$SECONDS
	printf '\n\033[1m── %s\033[0m\n' "$name"
	if "$@"; then
		printf '   \033[32m✓ %s\033[0m (%ds)\n' "$name" "$((SECONDS - t))"
	else
		printf '   \033[31m✗ %s\033[0m (%ds)\n' "$name" "$((SECONDS - t))"
		FAILED+=("$name")
	fi
}

tests() {
	# runner.gd 自己不返回非零退出码, 所以判据是输出里的 "0 failed"。
	local out
	out=$(godot --headless --path . --script res://tests/runner.gd 2>&1)
	echo "$out" | grep -E '^=== RESULT' || { echo "$out" | tail -20; return 1; }
	echo "$out" | grep -q ', 0 failed'
}

if [[ -n "$FACE" ]]; then
	# 增量模式:一张新脸只需要证明它自己 + 结构断言没被它带红。
	# ⚠ 参数是**脸的 id**。加了一张新**小丑牌**时用的是另一条:
	#     SYNC5_KIT_ID=<joker_id> godot --headless --path . --script res://tools/kit.gd
	step "测试" tests
	step "覆盖自证 · $FACE" env SYNC5_GATE_FACE="$FACE" godot --headless --path . --script res://tools/gate.gd
else
	step "测试" tests
	step "覆盖自证 + 单调性 + 哨兵" godot --headless --path . --script res://tools/gate.gd
	# ⚠ **+309s**(实测)。贵在 solver 通路那四张规则牌要跑完美玩家(~180s)。
	# 加了一张新小丑牌不必跑全量:`SYNC5_KIT_ID=<id>` 单验(score 5s / coin 16s /
	# solver 56~84s)。要压全量时间就调 kit.gd 的 `N_SOLVER`, 理由写在那边文件头。
	step "小丑牌覆盖自证" godot --headless --path . --script res://tools/kit.gd
	step "流程回归" godot --headless --path . --script res://tools/flow_probe.gd
	step "打点回归" godot --headless --path . --script res://tools/tapeprobe.gd
	step "决策重放" godot --headless --path . --script res://tools/replay.gd
	step "尺子自检" godot --headless --path . --script res://tools/sim.gd
fi

EL=$((SECONDS - T0))
printf '\n\033[1m=== 门:%ds' "$EL"
[[ $EL -gt 600 ]] && printf ' \033[33m(超出 10 分钟预算)\033[0m\033[1m'
printf ' ===\033[0m\n'
if [[ ${#FAILED[@]} -gt 0 ]]; then
	printf '\033[31m不通过:%s\033[0m\n' "${FAILED[*]}"
	exit 1
fi
printf '\033[32m全部通过\033[0m\n'
# ⚠ 没进这道门的两个:tools/pair.gd(求解器=游戏代码, ~3min)和 tools/blind.gd
# (盖牌定价, ~4.6min)。它们守的是**改了求解器/计分**才会破的东西, 而这道门守的是
# **加了内容**。改了 core/pattern.gd / core/settle.gd / tools/solver.gd 要另跑那两个。
