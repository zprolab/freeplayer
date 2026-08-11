#!/bin/bash
# FreePlayer — compose the 1024px icon master from the Icon Composer project.
# Source of truth: shell/FreePlayer.icon/ (icon.json + Assets/fp_nbg.png).
# The icon.json recipe: system-dark fill, glyph @0.85 scale + (22, 0.4)pt
# offset, neutral shadow @0.5, translucency 0.5.
# Requires python3 + Pillow (local machine; the committed FreePlayer-1024.png
# is what CI/bundles consume, so this only needs to run when the icon changes).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICON="$ROOT/FreePlayer.icon"
OUT="$ROOT/FreePlayer-1024.png"

[ -f "$ICON/Assets/fp_nbg.png" ] || { echo "==> missing $ICON/Assets/fp_nbg.png" >&2; exit 2; }

python3 - "$ICON/Assets/fp_nbg.png" "$OUT" <<'PYEOF'
import sys
from PIL import Image, ImageFilter

src, out = sys.argv[1], sys.argv[2]
glyph = Image.open(src).convert('RGBA')

SIZE = 1024
canvas = Image.new('RGBA', (SIZE, SIZE), (31, 31, 35, 255))  # #1f1f23

# icon.json: scale 0.85, translation (22.015625, 0.425) pt, neutral shadow @0.5
g = glyph.resize((int(SIZE * 0.85), int(SIZE * 0.85)), Image.LANCZOS)
gx = (SIZE - g.width) // 2 + 22
gy = (SIZE - g.height) // 2

shadow = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
shadow.alpha_composite(g, (gx, gy + 10))
shadow = shadow.filter(ImageFilter.GaussianBlur(14))
mask = shadow.split()[3].point(lambda a: int(a * 0.5))
shadow.putalpha(mask)
canvas.alpha_composite(shadow)

canvas.alpha_composite(g, (gx, gy))
canvas.convert('RGB').save(out)
print(f"==> {out} composed ({SIZE}x{SIZE})")
PYEOF
