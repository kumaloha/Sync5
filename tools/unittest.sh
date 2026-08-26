#!/usr/bin/env bash
# 全量单测 + 四判据(LESSONS「绿是假的」八种里前四种的门)。
#   exit 0 ∧ ", 0 failed" ∧ SCRIPT ERROR=0 ∧ ^ERROR=0 ∧ passed ≥ 地板
# 这是**唯一一份**判据:tools/gate.sh 的 tests() 与 .github/workflows/tests.yml 都调它
# (2026-08-21 外部审查要 CI;两处各写一份判据就是这个项目踩了 N 次的形状)。
#
# 用法:tools/unittest.sh [日志路径]      退出码 = 门的结论
set -u
cd "$(dirname "$0")/.."
LOG="${1:-${SYNC5_TEST_LOG:-/tmp/sync5_tests.log}}"
# 通过数地板:少于基线 = 有域被掐断。只许涨不许掉 —— **除非域是真删了**:
# 2026-08-24 局外 build 删除带走 t_character/t_ticket/t_asset 三域 + 若干断言块,
# 2479 → 2125,地板随之 2400 → 2100(全量实测 2125 之下留 25 的余量)。
FLOOR="${SYNC5_PASS_FLOOR:-2100}"
if command -v timeout >/dev/null 2>&1; then T="timeout 3600"; else T=""; fi
$T godot --headless --path . --script res://tests/runner.gd > "$LOG" 2>&1
ec=$?
grep -E '^=== RESULT' "$LOG" || { echo "   (no RESULT line — runner died or hung; tail:)"; tail -20 "$LOG"; exit 1; }
[[ $ec -ne 0 ]] && { echo "   runner exit code $ec"; exit 1; }
grep -q ', 0 failed' "$LOG" || { grep -n 'FAIL' "$LOG" | head -20; exit 1; }
se=$(grep -c 'SCRIPT ERROR' "$LOG" || true)
# ^ERROR 白名单(2026-08-21 审查点名,逐条有账):
#   · 退出时 Canvas/TextServer 的 RID 泄漏报告 —— 引擎在 headless 退出路径自己的账, 与测试无关
#   · `[Tape] … 保留字` ×3 —— tests/t_tape.gd 故意触发的(payload 撞保留字必须报错, 用例就是验这个)
# ⚠ 白名单只许按**具体文案**加, 不许按前缀放行;新增一条要在这里写明是谁、为什么。
ee=$(grep '^ERROR' "$LOG" | grep -Ev 'RID allocations of type|ObjectDB instances leaked|resources still in use at exit|rid_owner\.h|TextServer|\[Tape\] .*保留字' | grep -c . || true)
if [[ "$se" -ne 0 || "$ee" -ne 0 ]]; then
	echo "   SCRIPT ERROR=$se ^ERROR(非白名单)=$ee (see $LOG)"; grep -n 'SCRIPT ERROR\|^ERROR' "$LOG" | head -20; exit 1
fi
passed=$(grep -E '^=== RESULT' "$LOG" | sed -E 's/.*RESULT: ([0-9]+) passed.*/\1/')
[[ "$passed" -lt "$FLOOR" ]] && { echo "   passed=$passed < floor=$FLOOR(有域被掐断?)"; exit 1; }
echo "   passed=$passed · SCRIPT ERROR=0 · ^ERROR=0 · exit 0"
