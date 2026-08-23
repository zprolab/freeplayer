#!/bin/bash
# FreePlayer — build the iPad app via XcodeGen + xcodebuild.
# Three modes:
#   default          simulator build (unsigned)
#   --device <UDID>                  physical-device build, signed if --team given
#   --generic-ipa                    arm64 device build, UNSIGNED (for jailbroken
#                                    devices / sideloading), always packs an .ipa
# Self-contained: ensures ./dist (vite build), regenerates the Xcode project
# from shell/project.yml, then builds.
#   bash scripts/build-ipad.sh [--device <UDID> [--team <TEAMID>]] [--ipa]
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHELL="$ROOT/shell"
DIST="$ROOT/dist"
SIM_DEST="${SIM_DEST:-platform=iOS Simulator,name=iPad Pro 13-inch (M5)}"

DEVICE=""
TEAM=""
MAKE_IPA=0
GENERIC_IPA=0
while [ $# -gt 0 ]; do
  case "$1" in
    --device)     DEVICE="$2"; shift 2 ;;
    --team)       TEAM="$2";   shift 2 ;;
    --ipa)        MAKE_IPA=1;  shift ;;
    --generic-ipa) GENERIC_IPA=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# ── 1. web assets (the Xcode pre-build script rsyncs dist/ into the bundle) ──
if [ ! -d "$DIST" ]; then
  echo "[ipad] vite build..."
  (cd "$ROOT" && node_modules/.bin/vite build)
fi

# ── 2. icons (regenerate AppIcon + icns from assets/logo.svg) ──
echo "[ipad] icons..."
(cd "$ROOT" && node scripts/icons.mjs)

# ── 3. build version: <pkg.version> on tag builds, else <version>-<git-hash> ──
VER=$(node -p "require('$ROOT/package.json').version")
if git -C "$ROOT" describe --tags --exact-match >/dev/null 2>&1; then
  FP_BUILD_VERSION="$VER"
else
  HASH=$(git -C "$ROOT" rev-parse --short HEAD)
  FP_BUILD_VERSION="$VER-$HASH"
fi
echo "[ipad] build version: $FP_BUILD_VERSION"
export FP_BUILD_VERSION

# ── 4. Xcode project ──
echo "[ipad] xcodegen generate..."
(cd "$SHELL" && xcodegen generate)

# ── 5. build ──
if [ -n "$DEVICE" ]; then
  DEST="platform=iOS,id=$DEVICE"
  SIGN_ARGS=""
  if [ -n "$TEAM" ]; then
    SIGN_ARGS="DEVELOPMENT_TEAM=$TEAM CODE_SIGN_STYLE=Automatic"
  fi
  echo "[ipad] building for device $DEVICE${TEAM:+ (team $TEAM)}... [Debug-iphoneos]"
  # shellcheck disable=SC2086
  (cd "$SHELL" && xcodebuild -project FreePlayer.xcodeproj -scheme FreePlayer \
    -configuration Debug -destination "$DEST" -allowProvisioningUpdates \
    $SIGN_ARGS build)
elif [ "$GENERIC_IPA" = 1 ]; then
  echo "[ipad] building unsigned device (arm64) for jailbroken device... [Debug-iphoneos]"
  (cd "$SHELL" && xcodebuild -project FreePlayer.xcodeproj -scheme FreePlayer \
    -configuration Debug -destination 'generic/platform=iOS' \
    CODE_SIGNING_ALLOWED=NO build)
else
  echo "[ipad] building for simulator ($SIM_DEST)... [Debug-iphonesimulator]"
  (cd "$SHELL" && xcodebuild -project FreePlayer.xcodeproj -scheme FreePlayer \
    -configuration Debug -destination "$SIM_DEST" build)
fi

# ── 6. locate the product ──
if [ -n "$DEVICE" ] || [ "$GENERIC_IPA" = 1 ]; then
  APP=$(find "$HOME/Library/Developer/Xcode/DerivedData/FreePlayer-"* \
    -path "*Debug-iphoneos/FreePlayer.app" -type d 2>/dev/null | head -1)
else
  APP=$(find "$HOME/Library/Developer/Xcode/DerivedData/FreePlayer-"* \
    -path "*Debug-iphonesimulator/FreePlayer.app" -type d 2>/dev/null | head -1)
fi
[ -n "$APP" ] || { echo "==> built app not found" >&2; exit 3; }
echo "==> $APP"

# ── 7. pack an .ipa when requested (--ipa, or always for --generic-ipa) ──
PACK_IPA=0
[ "$MAKE_IPA" = 1 ] && PACK_IPA=1
[ "$GENERIC_IPA" = 1 ] && PACK_IPA=1
if [ "$PACK_IPA" = 1 ]; then
  PKG=$(mktemp -d)
  mkdir -p "$PKG/Payload"
  cp -R "$APP" "$PKG/Payload/"
  OUT="$ROOT/shell/release"
  mkdir -p "$OUT"
  STAMP=$(date +%Y%m%d-%H%M)
  if [ "$GENERIC_IPA" = 1 ]; then
    PLATFORM="ios-arm64-unsigned"   # jailbreak/side-load unsigned build
  elif [ -n "$DEVICE" ]; then
    PLATFORM="ios-arm64"            # signed device build
  else
    PLATFORM="ios-simulator"        # unsigned simulator build
  fi
  IPA="$OUT/FreePlayer-$VER-$PLATFORM-$STAMP.ipa"
  (cd "$PKG" && zip -qr "$IPA" Payload)
  rm -rf "$PKG"
  echo "==> $IPA"
fi
