#!/bin/bash
# FreePlayer — build the iPad or standalone iPhone app via XcodeGen + xcodebuild.
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
TARGET="FreePlayer"
while [ $# -gt 0 ]; do
  case "$1" in
    --device) DEVICE="$2"; shift 2 ;;
    --team)   TEAM="$2";   shift 2 ;;
    --iphone) TARGET="FreePlayer-iPhone"; SIM_DEST="${SIM_DEST_IPHONE:-platform=iOS Simulator,name=iPhone 17}"; shift ;;
    --ipa)    MAKE_IPA=1;  shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# ── 1. web assets (the Xcode pre-build script rsyncs dist/ into the bundle) ──
if [ ! -f "$DIST/index.html" ]; then
  echo "[ios] vite build..."
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

# ── 4. build ──
if [ -n "$DEVICE" ]; then
  DEST="platform=iOS,id=$DEVICE"
  SIGN_ARGS=""
  if [ -n "$TEAM" ]; then
    SIGN_ARGS="DEVELOPMENT_TEAM=$TEAM CODE_SIGN_STYLE=Automatic"
  fi
  echo "[ipad] building for device $DEVICE${TEAM:+ (team $TEAM)}..."
  # shellcheck disable=SC2086
  (cd "$SHELL" && xcodebuild -project FreePlayer.xcodeproj -scheme "$TARGET" \
    -configuration Debug -destination "$DEST" -allowProvisioningUpdates \
    $SIGN_ARGS build)
else
  echo "[ipad] building for simulator ($SIM_DEST)..."
  (cd "$SHELL" && xcodebuild -project FreePlayer.xcodeproj -scheme "$TARGET" \
    -configuration Debug -destination "$SIM_DEST" build)
fi

# ── 4. locate the product ──
if [ -n "$DEVICE" ]; then
  APP=$(find "$HOME/Library/Developer/Xcode/DerivedData/FreePlayer-"* \
    -path "*Debug-iphoneos/${TARGET}.app" -type d 2>/dev/null | head -1)
else
  APP=$(find "$HOME/Library/Developer/Xcode/DerivedData/FreePlayer-"* \
    -path "*Debug-iphonesimulator/${TARGET}.app" -type d 2>/dev/null | head -1)
fi
[ -n "$APP" ] || { echo "==> built app not found" >&2; exit 3; }
echo "==> $APP"

if [ "$MAKE_IPA" = 1 ]; then
  PKG=$(mktemp -d)
  mkdir -p "$PKG/Payload"
  cp -R "$APP" "$PKG/Payload/"
  # Same output location + naming convention as the macOS release
  # (shell/release/FreePlayer-<ver>-<platform>-<timestamp>.*)
  OUT="$ROOT/shell/release"
  mkdir -p "$OUT"
  VER=$(node -p "require('$ROOT/package.json').version")
  STAMP=$(date +%Y%m%d-%H%M)
  if [ -n "$DEVICE" ]; then
    PLATFORM="ios-arm64"           # signed device build
  else
    PLATFORM="ios-simulator"       # unsigned simulator build (CI)
  fi
  IPA="$OUT/$TARGET-$VER-$PLATFORM-$STAMP.ipa"
  (cd "$PKG" && zip -qr "$IPA" Payload)
  rm -rf "$PKG"
  echo "==> $IPA"
fi
