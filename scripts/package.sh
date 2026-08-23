#!/bin/bash
# FreePlayer shell — packaging pipeline
#   vite build -> .app bundle -> auto-named zip + dmg
#   Output: shell/release/FreePlayer-<version>-mac-arm64-<timestamp>.[zip|dmg]
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "[pack] vite build..."
node_modules/.bin/vite build

echo "[pack] bundling FreePlayer.app..."
# configure on demand — shell/build may not exist after a clean
[ -f "$ROOT/shell/build/build.ninja" ] || cmake -S "$ROOT/shell" -B "$ROOT/shell/build" -G Ninja
cmake --build "$ROOT/shell/build" --target bundle

APP="$ROOT/shell/build/FreePlayer.app"
OUT="$ROOT/shell/release"
mkdir -p "$OUT"

# Auto-rename: version from package.json + build timestamp
VER=$(node -p "require('./package.json').version")
STAMP=$(date +%Y%m%d-%H%M)
BASE="FreePlayer-$VER-mac-arm64-$STAMP"

echo "[pack] zip..."
ditto -c -k --keepParent "$APP" "$OUT/$BASE.zip"
echo "[pack] dmg..."
# diskutil image create from is the modern replacement for hdiutil create
diskutil image create from "$APP" "$OUT/$BASE.dmg" --format UDZO --volname FreePlayer >/dev/null

echo ""
echo "==> outputs:"
ls -lh "$OUT/$BASE.zip" "$OUT/$BASE.dmg"
