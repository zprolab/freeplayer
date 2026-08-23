#!/bin/bash
# FreePlayer — build the iPad app via XcodeGen + xcodebuild.
# Self-contained: ensures ./dist (vite build), regenerates the Xcode project
# from shell/project.yml, then builds. Defaults to the simulator (no signing);
# for a signed device build pass the iPad's UDID (and your team ID):
#   bash scripts/build-ipad.sh --device <UDID> --team <TEAMID> [--ipa]
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHELL="$ROOT/shell"
DIST="$ROOT/dist"
SIM_DEST="${SIM_DEST:-platform=iOS Simulator,name=iPad Pro 13-inch (M5)}"

DEVICE=""
TEAM=""
MAKE_IPA=0
while [ $# -gt 0 ]; do
  case "$1" in
    --device) DEVICE="$2"; shift 2 ;;
    --team)   TEAM="$2";   shift 2 ;;
    --ipa)    MAKE_IPA=1;  shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# ── 1. web assets (the Xcode pre-build script rsyncs dist/ into the bundle) ──
if [ ! -d "$DIST" ]; then
  echo "[ipad] vite build..."
  (cd "$ROOT" && node_modules/.bin/vite build)
fi

# ── 2. Xcode project ──
echo "[ipad] xcodegen generate..."
(cd "$SHELL" && xcodegen generate)

# ── 3. build ──
if [ -n "$DEVICE" ]; then
  DEST="platform=iOS,id=$DEVICE"
  SIGN_ARGS=""
  if [ -n "$TEAM" ]; then
    SIGN_ARGS="DEVELOPMENT_TEAM=$TEAM CODE_SIGN_STYLE=Automatic"
  fi
  echo "[ipad] building for device $DEVICE${TEAM:+ (team $TEAM)}..."
  # shellcheck disable=SC2086
  (cd "$SHELL" && xcodebuild -project FreePlayer.xcodeproj -scheme FreePlayer \
    -configuration Debug -destination "$DEST" -allowProvisioningUpdates \
    $SIGN_ARGS build)
else
  echo "[ipad] building for simulator ($SIM_DEST)..."
  (cd "$SHELL" && xcodebuild -project FreePlayer.xcodeproj -scheme FreePlayer \
    -configuration Debug -destination "$SIM_DEST" build)
fi

# ── 4. locate the product ──
if [ -n "$DEVICE" ]; then
  APP=$(find "$HOME/Library/Developer/Xcode/DerivedData/FreePlayer-"* \
    -path "*Debug-iphoneos/FreePlayer.app" -type d 2>/dev/null | head -1)
else
  APP=$(find "$HOME/Library/Developer/Xcode/DerivedData/FreePlayer-"* \
    -path "*Debug-iphonesimulator/FreePlayer.app" -type d 2>/dev/null | head -1)
fi
[ -n "$APP" ] || { echo "==> built app not found" >&2; exit 3; }
echo "==> $APP"

if [ "$MAKE_IPA" = 1 ] && [ -n "$DEVICE" ]; then
  PKG=$(mktemp -d)
  mkdir -p "$PKG/Payload"
  cp -R "$APP" "$PKG/Payload/"
  IPA="$ROOT/FreePlayer-$(date +%Y%m%d-%H%M%S).ipa"
  (cd "$PKG" && zip -qr "$IPA" Payload)
  rm -rf "$PKG"
  echo "==> $IPA"
fi
