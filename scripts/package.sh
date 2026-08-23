#!/bin/bash
# FreePlayer — build a release: .app bundle → auto-named zip + dmg.
#   npm run dist
#   Output: shell/release/FreePlayer-<version>-mac-arm64-<timestamp>.[zip|dmg]
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "[dist] bundling FreePlayer.app..."
bash "$ROOT/scripts/bundle.sh"

APP="$ROOT/shell/build/FreePlayer.app"
OUT="$ROOT/shell/release"
mkdir -p "$OUT"

# Auto-rename: version from package.json + build timestamp
VER=$(node -p "require('./package.json').version")
STAMP=$(date +%Y%m%d-%H%M)
BASE="FreePlayer-$VER-mac-arm64-$STAMP"

echo "[dist] zip..."
ditto -c -k --keepParent "$APP" "$OUT/$BASE.zip"
echo "[dist] dmg..."
diskutil image create from "$APP" "$OUT/$BASE.dmg" --format UDZO --volname FreePlayer >/dev/null

echo ""
echo "==> outputs:"
ls -lh "$OUT/$BASE.zip" "$OUT/$BASE.dmg"