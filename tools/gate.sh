#!/usr/bin/env bash
# 加内容之后要过的那道门。
#   tools/gate.sh              完整跑一遍(回归用)
#   tools/gate.sh <face_id>    只验这一张新脸(加了一张脸时用, 十几秒)
#   tools/gate.sh --changed    **增量**:从 git diff 认出改了哪些卡/脸, 只验它们
#
# ## 增量模式的判据(2026-08-13 加, 起因见下)
#
# **改的是「内容」就增量, 改的是「机制」就全量。** 内容 = `data/*.json` 里某几张
# 卡/脸的数值;机制 = `core/**` 与 `tools/` 的共享真相(bot / solver / runloop /
# draft / settle …)—— 后者一改, **每一张**卡和脸的读数都可能变, 增量就是自欺。
# 所以 `--changed` **自己会检测**:碰到机制文件就自动升级成全量并说明理由,
# 不需要人记得。
#
# ⚠ **增量模式必须说清它跳过了什么**(no silent caps):跳过的张数会打印出来。
# 一道「只验了 3 张却看起来像全量绿」的门, 比慢半小时危险得多。
# ⚠ **提交/发布前跑一次全量** —— 增量抓不到「改 A 卡影响 B 卡」的交互。
#
# 起因:2026-08-13 实测 1818s(超预算 3 倍)。分布 **脸 944s(52%) / 卡 611s(34%) /
# 尺子 168s** —— 而每次改动通常只碰几张。⚠ 我原本以为瓶颈只在 kit(roster 从 23
# 涨到 57), 量完才知道**脸的门才是最大那块**:又一次「不猜, 去量」。
#
# 为什么要有它:2026-08-07 一次加 8 张脸 → 18 个坑, 最难查的几个都是多个新东西
# 互相干扰。用户拍板「慢慢加内容, 每次跑求解器/生成器」—— **那就得是一道固定的门,
# 不能靠自觉**。预算 ≤10 分钟(用户定的), 跑完会打印实际用时。
#
# ⚠ 读退出码别隔着管道:`godot ... | tail` 之后的 $? 是 tail 的。下面每一步都直接读。
set -uo pipefail
LOGDIR="${SYNC5_GATE_LOGDIR:-/tmp/sync5-gate}"; mkdir -p "$LOGDIR"
# `timeout` 在 macOS 上来自 coreutils(brew);没有就裸跑 —— 但那样第一种假绿(挂起)就没人兜
if command -v timeout >/dev/null 2>&1; then TIMEOUT="timeout"; else TIMEOUT=""; echo "⚠ 没有 timeout 命令, 单测挂起将无人兜底"; fi
cd "$(dirname "$0")/.."

FACE="${1:-}"
T0=$SECONDS
FAILED=()

# ---- 增量模式:git diff → 改动的卡/脸 id;碰机制文件则升级为全量 ----
CHANGED_JOKERS=""
CHANGED_FACES=""
INCREMENTAL=0

# 机制文件:一改就影响**所有**卡与脸的读数, 增量在这里没有意义。
# ⚠ 宁可多列不可漏列 —— 漏一个的代价是「门绿了但读数是旧的」, 静默且昂贵。
# 2026-08-21 审查:boons/director/ranking 也是结算链或排布的全局输入, 漏在外面 = 改了不跑门
MECH_RE='^(core/|tools/(bot|solver|runloop|draft|report|stat|probe|beat)\.gd|data/(run|economy|sim|boons|director|ranking)\.json|project\.godot)'

# 未跟踪的新文件也算改动(2026-08-21 审查:新建的 core/*.gd 此前对增量门隐身)
changed_files() { git diff --name-only HEAD -- . 2>/dev/null; git diff --cached --name-only HEAD -- . 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; }

# data/*.json 里改动过的 id。
#
# ⚠⚠ **第一版只认 `+` 行上的 `"id"`, 那是个瞎眼的门**(2026-08-13 验出来的):
# 「**新增**一张卡」的 id 行是 `+`, 认得出;而「**改一张已有卡的数值**」改的是数值行,
# 它的 `"id"` 行是**上下文行**(空格前缀)—— 认不出, 于是门判定「没有卡改动」跳过 kit,
# 而那张卡其实改了。**数值迭代正是最常见的改动**(试玩后调平衡), 所以第一版恰好在
# 最重要的用例上失明, 还看起来是绿的。
#
# 现在的做法:顺序扫 diff, 记住「最近看到的 id」(**含上下文行**), 遇到任何改动行
# (`+`/`-`)就把当前 id 记为 touched。
# ⚠ 依赖一条格式约定:**`"id"` 是每个卡/脸对象的第一个键**(写入脚本的 OrderedDict
# 保证)—— 否则改动行可能出现在 id 行之前而归错。
# ⚠ 上下文给足 `-U30`:一张带 effects 的卡约 20 行, 上下文太窄会让 id 行落在 hunk 外。
# ⚠ 跨 hunk 时 `cur` 故意**不清空**:残留只会让它多验一张(保守方向), 清空则可能漏。
ids_touched() {  # ids_touched <file>
	git diff -U30 HEAD -- "$1" 2>/dev/null | awk '
		/^(\+\+\+|---)/ { next }
		/"id"[[:space:]]*:/ {
			match($0, /"id"[[:space:]]*:[[:space:]]*"[^"]+"/);
			s = substr($0, RSTART, RLENGTH);
			gsub(/.*"id"[[:space:]]*:[[:space:]]*"/, "", s); gsub(/"$/, "", s);
			cur = s;
		}
		/^[+-]/ { if (cur != "") touched[cur] = 1 }
		END { for (k in touched) print k }' | sort -u | paste -sd, -
}

if [[ "$FACE" == "--changed" ]]; then
	FACE=""
	FILES=$(changed_files | sort -u)
	if [[ -z "$FILES" ]]; then
		printf '\033[33m[gate] 工作区没有改动 —— 增量无从下手, 按全量跑\033[0m\n'
	elif echo "$FILES" | grep -qE "$MECH_RE"; then
		printf '\033[33m[gate] 改动碰到了**机制**文件, 自动升级为全量:\033[0m\n'
		echo "$FILES" | grep -E "$MECH_RE" | sed 's/^/           /'
		printf '           (机制一改, 每张卡和脸的读数都可能变 —— 增量在这里是自欺)\n'
	else
		CHANGED_JOKERS=$(ids_touched data/jokers.json)
		CHANGED_FACES=$(ids_touched data/faces.json)
		INCREMENTAL=1
		printf '\033[36m[gate] 增量模式\033[0m  卡:%s  脸:%s\n' \
			"${CHANGED_JOKERS:-无}" "${CHANGED_FACES:-无}"
	fi
fi

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
	# 2026-08-21 评审 R7:此前这里只 `grep ', 0 failed'` —— 丢退出码、不数 SCRIPT ERROR / ^ERROR、不看通过数、
	# 没有超时。四判据现在**只有一份**, 在 tools/unittest.sh(CI 也调它), 这里只是转发。
	tools/unittest.sh "$LOGDIR/tests.log"
}

if [[ -n "$FACE" ]]; then
	# 增量模式:一张新脸只需要证明它自己 + 结构断言没被它带红。
	# ⚠ 参数是**脸的 id**。加了一张新**小丑牌**时用的是另一条:
	#     SYNC5_KIT_ID=<joker_id> godot --headless --path . --script res://tools/kit.gd
	step "测试" tests
	step "覆盖自证 · $FACE" env SYNC5_GATE_FACE="$FACE" godot --headless --path . --script res://tools/gate.gd
else
	step "测试" tests
	# 覆盖自证:增量模式下只验改动过的脸/卡。**单调性与哨兵仍然全跑** ——
	# 它们是全局不变量(不针对某张脸), 而且便宜。
	if [[ $INCREMENTAL -eq 1 && -n "$CHANGED_FACES" ]]; then
		step "覆盖自证 · 改动的脸($CHANGED_FACES)" \
			env SYNC5_GATE_FACE="$CHANGED_FACES" godot --headless --path . --script res://tools/gate.gd
		N_POOL=$(grep -c '"tier"' data/faces.json || echo '?')
		printf '   \033[33m⚠ 增量:只验了改动的脸;池里共约 %s 张未全量复验\033[0m\n' "$N_POOL"
	elif [[ $INCREMENTAL -eq 1 ]]; then
		printf '\n\033[36m── 覆盖自证 · 脸\033[0m\n   \033[33m⚠ 跳过:本次没有改动任何脸\033[0m\n'
	else
		step "覆盖自证 + 单调性 + 哨兵" godot --headless --path . --script res://tools/gate.gd
	fi
	# ⚠ **+611s**(2026-08-13 实测, roster 57 张;文件头那个 309s 是 23 张时代的数)。
	# 贵在 solver 通路的规则牌要跑完美玩家。增量只验改动过的卡。
	if [[ $INCREMENTAL -eq 1 && -n "$CHANGED_JOKERS" ]]; then
		step "小丑牌覆盖自证 · 改动的卡($CHANGED_JOKERS)" \
			env SYNC5_KIT_ID="$CHANGED_JOKERS" godot --headless --path . --script res://tools/kit.gd
		N_CARDS=$(grep -c '"proof"' data/jokers.json || echo '?')
		printf '   \033[33m⚠ 增量:只验了改动的卡;池里共 %s 张未全量复验\033[0m\n' "$N_CARDS"
	elif [[ $INCREMENTAL -eq 1 ]]; then
		printf '\n\033[36m── 小丑牌覆盖自证\033[0m\n   \033[33m⚠ 跳过:本次没有改动任何卡\033[0m\n'
	else
		step "小丑牌覆盖自证" godot --headless --path . --script res://tools/kit.gd
	fi
	# 下面四段**增量也跑** —— 它们是全局回归(流程/打点/重放/尺子), 与「改了哪张卡」无关,
	# 合计约 190s。⚠ 尺子自检那条尤其不许省:它是「bot_targets 还没失效」的唯一警报。
	step "流程回归" godot --headless --path . --script res://tools/flow_probe.gd
	step "打点回归" godot --headless --path . --script res://tools/tapeprobe.gd
	step "决策重放" godot --headless --path . --script res://tools/replay.gd
	step "尺子自检" godot --headless --path . --script res://tools/sim.gd
	if [[ $INCREMENTAL -eq 1 ]]; then
		printf '\n\033[33m⚠ 这是**增量**门:单调性/哨兵未跑, 未改动的卡与脸未复验。\n'
		printf '   提交或发布前跑一次 `./tools/gate.sh`(全量)—— 增量抓不到跨卡交互。\033[0m\n'
	fi
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
