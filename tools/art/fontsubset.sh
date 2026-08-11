#!/bin/sh
# 重建 Web 用中文字体子集 assets/fonts/NotoSansSC-Sync5.ttf(2026-08-12)。
# 什么时候跑:文案(data/*.json / 代码字符串 / 两份美术 manifest)加了此前
# 没用过的字 —— Web 版那些字会豆腐块,桌面版不受影响(系统字兜底见
# view/theme.gd::zh())。
# 依赖:python3 + fonttools(pip install --user fonttools);
# 全量字体源不入库(17.7MB),缺了按下面 URL 重下(OFL 授权)。
set -e
cd "$(dirname "$0")/../.."
SRC="${SYNC5_FONT_SRC:-/tmp/NotoSansSC.ttf}"
if [ ! -f "$SRC" ]; then
  echo "缺全量字体源 $SRC —— 先下载(OFL):"
  echo "  curl -L -o $SRC 'https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf'"
  exit 1
fi
CORPUS="$(mktemp)"
python3 - "$CORPUS" << 'EOF'
import glob, sys
chars = set()
for pat in ['view/*.gd', 'core/*.gd', 'tools/**/*.gd', 'tests/*.gd', 'data/*.json',
            'assets/jokers/manifest.json', 'assets/characters/manifest.json']:
    for p in glob.glob(pat, recursive=True):
        chars.update(open(p, encoding='utf-8').read())
base = ''.join(chr(c) for c in range(0x20, 0x7F))
extra = ',。、;:?!「」『』()《》——……·×÷±%℃丨~*◆◈♪♩♫♥♠♣♦★☆⚡✦✧▸▲▼←→↑↓'
out = ''.join(sorted(set(base + extra) | chars))
open(sys.argv[1], 'w', encoding='utf-8').write(out)
print('语料字符', len(set(out)))
EOF
python3 -m fontTools.subset "$SRC" --text-file="$CORPUS" \
  --output-file=assets/fonts/NotoSansSC-Sync5.ttf \
  --layout-features='*' --no-hinting
# 第二件套:SC 缺的装饰符(▸◈⚡✦✧ 等)住在 Symbols 2 里
SRC2="${SYNC5_FONT_SYM2:-/tmp/NotoSym2.ttf}"
if [ -f "$SRC2" ]; then
  python3 -m fontTools.subset "$SRC2" --text-file="$CORPUS" \
    --output-file=assets/fonts/NotoSymbols2-Sync5.ttf --no-hinting
else
  echo "(跳过符号字体:缺 $SRC2 —— 需要时下载:"
  echo "  curl -L -o $SRC2 'https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssymbols2/NotoSansSymbols2-Regular.ttf')"
fi
rm -f "$CORPUS"
stat -f "子集大小 %z bytes" assets/fonts/NotoSansSC-Sync5.ttf assets/fonts/NotoSymbols2-Sync5.ttf 2>/dev/null
echo "⚠ 之后要跑一次: godot --headless --path . --import"
