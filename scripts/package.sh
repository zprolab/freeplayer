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
# Stage the .app in a folder first: `diskutil image create from` treats its
# argument as the volume root, so pointing it at the .app would spread the
# bundle's Contents/ across the volume instead of the .app icon.
STAGE="$OUT/.stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
diskutil image create from "$STAGE" "$OUT/$BASE.dmg" --format UDZO --volname FreePlayer >/dev/null
rm -rf "$STAGE"

echo ""
echo "==> outputs:"
ls -lh "$OUT/$BASE.zip" "$OUT/$BASE.dmg"