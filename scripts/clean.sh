#!/bin/bash
# FreePlayer — clean build artifacts
#   pnpm run clean         removes dist/, shell/build/, shell/release/ and the
#                          generated icon rasters (source untouched)
#   pnpm run clean:all     also removes every untracked/ignored file (node_modules, .DS_Store…),
#                          back to fresh-clone state, keeping .superpowers/ and docs/
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ "$1" = "--all" ] || [ "$1" = "all" ]; then
  echo "[clean] removing all untracked and ignored files (keeping .superpowers/ and docs/)"
  git -C "$ROOT" clean -fdx -e .superpowers -e docs -e docs/superpowers
  echo "==> clean:all done (run 'pnpm install' to restore node_modules)"
  exit 0
fi

echo "[clean] removing dist/"
rm -rf "$ROOT/dist"
echo "[clean] removing shell/build/"
rm -rf "$ROOT/shell/build"
echo "[clean] removing shell/release/"
rm -rf "$ROOT/shell/release"
echo "[clean] removing generated icon rasters (FreePlayer-1024.png, FreePlayer.icns)"
rm -f "$ROOT/shell/FreePlayer-1024.png" "$ROOT/shell/FreePlayer.icns"
echo "==> clean done"
