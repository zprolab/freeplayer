#!/bin/bash
# FreePlayer — install the app bundle
#   npm run install            → /Applications
#   npm run install ~/Desktop   → ~/Desktop
# Builds dist + FreePlayer.app on demand, then copies the bundle in.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-/Applications}"
APP="$ROOT/shell/build/FreePlayer.app"

if [ ! -d "$ROOT/dist" ]; then
  echo "[install] vite build..."
  (cd "$ROOT" && node_modules/.bin/vite build)
fi
if [ ! -d "$APP" ]; then
  echo "[install] bundling FreePlayer.app..."
  # configure on demand — shell/build may not exist after a clean
  [ -f "$ROOT/shell/build/build.ninja" ] || cmake -S "$ROOT/shell" -B "$ROOT/shell/build" -G Ninja
  cmake --build "$ROOT/shell/build" --target bundle
fi

if [ ! -d "$TARGET" ]; then
  echo "==> target directory missing: $TARGET" >&2
  exit 1
fi

# A running instance blocks replacement — ask the user to quit it first.
if pgrep -x FreePlayer >/dev/null 2>&1; then
  echo "==> FreePlayer is running — quit it before installing." >&2
  exit 1
fi

echo "[install] installing to $TARGET/FreePlayer.app"
rm -rf "$TARGET/FreePlayer.app"
ditto "$APP" "$TARGET/FreePlayer.app"
codesign --force --sign - "$TARGET/FreePlayer.app" >/dev/null 2>&1 || true
echo "==> installed: $TARGET/FreePlayer.app"
