#!/bin/bash
# FreePlayer — regenerate the app icon (.icns) from the 1024px master.
#   shell/FreePlayer-1024.png  is the composed master (from the Icon Composer
#     project via scripts/logo-compose.sh — see shell/FreePlayer.icon/).
#   make -C shell logo   →  rebuild shell/FreePlayer.icns from it
# The bundle target depends on this rule, so `make bundle` always ships a
# fresh icon whenever the master changes.
# CI-safe: only sips + iconutil (both ship with macOS).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/FreePlayer-1024.png"
OUT="$ROOT/FreePlayer.icns"

[ -f "$SRC" ] || { echo "==> missing $SRC (run scripts/logo-compose.sh)" >&2; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/icon.iconset"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" "$SRC" --out "$TMP/icon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z "$((s*2))" "$((s*2))" "$SRC" --out "$TMP/icon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/icon.iconset" -o "$OUT"
echo "==> $OUT regenerated from $SRC"
