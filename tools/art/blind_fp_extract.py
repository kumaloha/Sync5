#!/usr/bin/env python3
"""盲注机制指纹抽取:assets/docs/design/blind_card_ui.html 的 29 个 <symbol>
→ assets/blinds/fp_<id>.svg(烤定色,Godot 原生导入当纹理)。

来源是已批准的目录(README「Final Blind signal deck」),这里只做机械转换:
  - currentColor → 压力品红 #ff328d / boon 金 #ffd36e(doubleset/spotlight/afterglow/encore)
  - class="signal-hot" → stroke="#f8f5ff"(独立 svg 里没有那条 CSS,必须落成属性)
重新生成:python3 tools/art/blind_fp_extract.py(仓库根目录跑)。
"""
import re
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "assets/docs/design/blind_card_ui.html"
OUT = ROOT / "assets/blinds"
BOONS = {"doubleset", "spotlight", "afterglow", "encore"}
PRESSURE, BOON, HOT = "#ff328d", "#ffd36e", "#f8f5ff"

html = SRC.read_text(encoding="utf-8")
symbols = re.findall(r'<symbol id="s5-([a-z]+)" viewBox="0 0 100 100">(.*?)</symbol>',
                     html, re.S)
assert len(symbols) == 29, f"expected 29 symbols, got {len(symbols)}"
OUT.mkdir(parents=True, exist_ok=True)
for fid, body in symbols:
    color = BOON if fid in BOONS else PRESSURE
    b = body.replace('class="signal-hot"', f'stroke="{HOT}"')
    b = b.replace("currentColor", color)
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" '
           f'viewBox="0 0 100 100">{b}</svg>\n')
    (OUT / f"fp_{fid}.svg").write_text(svg, encoding="utf-8")
    print(f"fp_{fid}.svg")
print(f"→ {OUT} ({len(symbols)} files)")
