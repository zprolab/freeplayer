#!/bin/bash
# FreePlayer — regenerate the app icon (.icns) from the source SVG.
#   shell/logo.svg  is the single source of truth (exported from Pixelmator).
#   make -C shell logo   →  rebuild shell/FreePlayer.icns from it
# The bundle target depends on this rule, so `make bundle` always ships a
# fresh icon whenever the SVG changes.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVG="$ROOT/logo.svg"
OUT="$ROOT/FreePlayer.icns"

[ -f "$SVG" ] || { echo "==> missing $SVG" >&2; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# QuickLook renders the SVG to PNG at the icns source size (1024)
qlmanage -t -s 1024 -o "$TMP" "$SVG" >/dev/null 2>&1
SRC="$TMP/logo.svg.png"
[ -f "$SRC" ] || { echo "==> SVG render failed (qlmanage)" >&2; exit 1; }

mkdir -p "$TMP/icon.iconset"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" "$SRC" --out "$TMP/icon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z "$((s*2))" "$((s*2))" "$SRC" --out "$TMP/icon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/icon.iconset" -o "$OUT"
echo "==> $OUT regenerated from logo.svg"
