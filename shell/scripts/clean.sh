#!/bin/bash
# FreePlayer — clean build artifacts
#   npm run clean
# Removes dist/, shell/build/ and shell/release/ (source untouched).
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

echo "[clean] removing dist/"
rm -rf "$ROOT/dist"
echo "[clean] removing shell/build/"
rm -rf "$ROOT/shell/build"
echo "[clean] removing shell/release/"
rm -rf "$ROOT/shell/release"
echo "==> clean done"
