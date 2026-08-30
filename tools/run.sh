#!/usr/bin/env bash
# 长探针的**带锁**启动器 —— 跑着的时候改它读的文件, 结果一律作废。
#
# ⚑ 2026-08-30 立:这条纪律我一天之内靠自觉守了**五次都没守住**
#    (四次改 data/ 让单测/sim 读到半新半旧, 一次改 core/ 让 sim 直接
#     `Stack underflow! (Engine Bug)`)。⇒ 靠记性守不住的纪律要落成机械。
#
#   tools/run.sh sim <log>        后台跑 sim, 期间锁住工作区
#   tools/run.sh unittest <log>   同上, 跑单测
#   tools/run.sh probe <名> <log> 同上, 跑 tools/<名>.gd(任意探针)
#   tools/run.sh --status         看谁在跑、锁了多久
#   tools/run.sh --unlock         强制解锁(进程已死但锁还在时)
#
# 锁的做法:记下启动时刻与被监视目录的**内容指纹**, 结束时比对 ——
# 变了就大字警告并**把日志标记为脏**, 而不是让一份被污染的读数混进结论。
set -uo pipefail
# ⚠ 用 BASH_SOURCE 而不是 $0 —— 某些调用方式下 $0 不是脚本路径, cd 会落到别处,
# 于是 WATCH 的相对路径指向空目录, **指纹恒等于空串的哈希 ⇒ 锁永远不报警**
# (2026-08-30 自验时发现:它已经"守"了好几轮, 一次都没真正比对过)。
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
# ⚠⚠ 2026-08-30:首版放 `.omc/state/`, 而**仓库目录在沙箱里是只读的** ——
# `mkdir` 静默失败, 锁文件从来没建成, **这把尺一直什么都没做**, 而我以为它在守着。
# 是「构造一次它应该报警的情形」才照出来的(见 LESSONS「一把有盲区的尺」)。
# ⇒ 锁放系统临时目录, 按仓库路径取唯一名。
LOCK="${TMPDIR:-/tmp}/sync5-probe-$(echo "$PWD" | shasum | cut -c1-8).lock"
WATCH=(core view tools data)

# ⚠ 2026-08-30 补 `.py`/`.sh`:首版只监视 `*.gd`/`*.json`, 而我在门跑着时改的正是
# `tools/*.py` 与 `gate.sh` —— **锁没报警**。一把有盲区的尺比没有尺更危险,
# 因为它会让人以为已经被守住了。
fingerprint() { find "${WATCH[@]}" -type f \( -name '*.gd' -o -name '*.json' \
	-o -name '*.py' -o -name '*.sh' \) \
	-exec stat -f '%m %z %N' {} + 2>/dev/null | sort | shasum | cut -d' ' -f1; }
# ⚠⚠ 2026-08-30:首版带了 `-newermt '1970-01-01'` —— **BSD find(macOS)不支持它**,
# 整条命令失败、输出空 ⇒ 指纹恒等于**空串的哈希**(da39a3ee...) ⇒ **锁永远不报警**。
# 它就这样"守"了好几轮, 一次都没真正比对过。⇒ 这就是「一把有盲区的尺比没有尺更危险」
# 的实证:我明知在改文件却没停手, 因为"锁会替我抓住"。

case "${1:-}" in
--status)
	[[ -f $LOCK ]] && { echo "锁在:"; cat "$LOCK"; } || echo "无锁"; exit 0 ;;
--unlock) rm -f "$LOCK"; echo "已解锁"; exit 0 ;;
esac

# ⚠ 陈旧锁的识别(2026-08-30 code review):只有正常路径清锁, **被 Ctrl+C 或
# 崩溃打断就残留** —— 我今天为此手动 `--unlock` 过好几次。
# ⇒ 锁里记 PID, 进程已经不在就自动清掉(而不是拒绝下一次运行)。
if [[ -f $LOCK ]]; then
	OLDPID=$(sed -n 's/^pid: //p' "$LOCK" 2>/dev/null)
	if [[ -n "$OLDPID" ]] && kill -0 "$OLDPID" 2>/dev/null; then
		echo "✗ 已有探针在跑(tools/run.sh --status 看详情)"; exit 1
	fi
	echo "⚠ 清掉陈旧的锁(上一次运行被打断, pid ${OLDPID:-?} 已不在)"
	rm -f "$LOCK"
fi
# ⚠ trap:被打断也要清锁, 否则下一次运行会被自己挡住。
trap 'rm -f "$LOCK"' EXIT INT TERM
FP0=$(fingerprint)
{ echo "cmd: $*"; echo "起: $(date '+%F %T')"; echo "pid: $$"; echo "fp: $FP0"; } > "$LOCK"

case "${1:-}" in
# ⚑ `selftest` 保留 —— **新立一把尺之后要构造一次它应该报警的情形**。
# 这把尺首版有三个各自独立的失效点(只读的锁目录 · BSD find 不支持 -newermt ·
# 只监视 .gd/.json), **每一个都让它静默地什么都不做**, 而自验一次全照出来了。
#   ./tools/run.sh selftest /tmp/x.log &   然后 1 秒内改任意被监视的文件, 期待 rc=90
selftest) sleep 3; rc=0 ;;
sim)      godot --headless --path . --script res://tools/sim.gd > "${2:-/tmp/sim.log}" 2>&1; rc=$? ;;
unittest) tools/unittest.sh "${2:-/tmp/tests.log}"; rc=$? ;;
# ⚑ 通用探针(2026-08-30 补):锁此前只覆盖 sim 与 unittest **两个**, 而 tools/ 下有五十多个
# 探针都是长跑 —— 「长探针一律走 run.sh」这条纪律对其余的**根本没法遵守**。
# ⚠ 这正是这把尺自己的第四个盲区:前三个(只读锁目录 / BSD find / 只看 .gd .json)
# 都让它静默失效, 这一个让它**覆盖不到**。用法:
#   tools/run.sh probe coin /tmp/coin.log            → tools/coin.gd
#   SYNC5_KIT_ID=x tools/run.sh probe kit /tmp/k.log → 环境变量照常透传
probe)
	[[ -n "${2:-}" ]] || { echo "用法: tools/run.sh probe <tools 下的脚本名(不含 .gd)> <日志路径>"; rm -f "$LOCK"; exit 2; }
	[[ -f "tools/$2.gd" ]] || { echo "✗ 没有 tools/$2.gd"; rm -f "$LOCK"; exit 2; }
	godot --headless --path . --script "res://tools/$2.gd" > "${3:-/tmp/probe.log}" 2>&1; rc=$? ;;
*)        echo "用法: tools/run.sh {sim|unittest|probe <名字>} <日志路径>"; rm -f "$LOCK"; exit 2 ;;
esac

FP1=$(fingerprint)
rm -f "$LOCK"
if [[ "$FP0" != "$FP1" ]]; then
	printf '\n\033[31m⚠⚠ 工作区在探针跑着的时候被改过 —— 这份读数作废, 重跑。\033[0m\n'
	printf '   (半新半旧的输入会让读数看着正常却是错的;改 core/ 还会直接 Stack underflow)\n'
	exit 90
fi
exit $rc
