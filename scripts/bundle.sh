#!/bin/bash
# FreePlayer — bundle FreePlayer.app (CMake `bundle` custom target; port of the
# old Makefile bundle rule). Needs ../dist from `pnpm build` and the shell
# binary; regenerates the icon from assets/logo.svg on every bundle.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHELL="$ROOT/shell"
BUILD="$SHELL/build"
DIST="$ROOT/dist"
BIN="${BIN:-$BUILD/FreePlayerShell}"
BUNDLE="$BUILD/FreePlayer.app"

[ -d "$DIST" ] || { echo "==> missing $DIST — run 'pnpm build' first"; exit 2; }
[ -f "$BIN" ] || { echo "==> missing $BIN — run 'cmake --build shell/build' first"; exit 2; }

# App icon: regenerated from the single source of truth (assets/logo.svg)
node "$ROOT/scripts/icons.mjs"

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