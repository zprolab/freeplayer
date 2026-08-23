#!/bin/bash
# FreePlayer — install the app bundle
#   npm run install            → /Applications
#   npm run install ~/Desktop   → ~/Desktop
# Builds FreePlayer.app on demand (via scripts/bundle.sh), then copies it in.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-/Applications}"
APP="$ROOT/shell/build/FreePlayer.app"

echo "[install] bundling FreePlayer.app..."
bash "$ROOT/scripts/bundle.sh"

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