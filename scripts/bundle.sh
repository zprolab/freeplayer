#!/bin/bash
# FreePlayer — build FreePlayer.app in shell/build/.
# Self-contained: ensures ./dist (vite build), the shell binary (cmake build)
# and the icon are all current before packing the .app. Shared by `npm run
# bundle` and the CMake `bundle` target.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHELL="$ROOT/shell"
BUILD="$SHELL/build"
DIST="$ROOT/dist"
BIN="${BIN:-$BUILD/FreePlayerShell}"
BUNDLE="$BUILD/FreePlayer.app"

# ── 1. web assets ──
if [ ! -d "$DIST" ]; then
  echo "[bundle] vite build..."
  (cd "$ROOT" && node_modules/.bin/vite build)
fi

# ── 2. shell binary ──
if [ ! -d "$BUILD" ] || [ ! -f "$BUILD/build.ninja" ]; then
  echo "[bundle] configuring cmake..."
  cmake -S "$SHELL" -B "$BUILD" -G Ninja
fi
if [ ! -f "$BIN" ]; then
  echo "[bundle] building shell binary..."
  cmake --build "$BUILD"
fi
[ -f "$BIN" ] || { echo "==> missing $BIN"; exit 2; }

# ── 3. app icon (from the single source of truth assets/logo.svg) ──
node "$ROOT/scripts/icons.mjs"

# ── 4. pack the bundle ──
echo "[bundle] packing $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources/web"
cp "$BIN" "$BUNDLE/Contents/MacOS/FreePlayer"
cp -R "$DIST"/. "$BUNDLE/Contents/Resources/web/"
cp "$SHELL/FreePlayer.icns" "$BUNDLE/Contents/Resources/FreePlayer.icns"
cp "$ROOT/LICENSE" "$BUNDLE/Contents/Resources/LICENSE"
cp "$SHELL/Info.plist" "$BUNDLE/Contents/Info.plist"
# hardened runtime for release bundles (ad-hoc identity)
codesign --force --sign - --options runtime "$BUNDLE"
echo "==> $BUNDLE ready"