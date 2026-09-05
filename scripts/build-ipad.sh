#!/bin/bash
# FreePlayer — build the iPad or standalone iPhone app via XcodeGen + xcodebuild.
#
# Platform flags:
#   --ipad          build the iPad target   (default)
#   --iphone        build the iPhone target
#
# Simulator flags (mutually exclusive; default: --no-simulator):
#   --simulator     build for simulator (unsigned)
#   --no-simulator  build for physical device
#
# Device flags (only valid with --no-simulator):
#   --device <UDID> physical-device UDID; enables signed build when --team given
#   --team   <ID>   Apple Developer team ID for code signing
#
# Packaging:
#   --ipa                  pack the built .app into an .ipa in shell/release/
#
# Configuration:
#   --configuration <name> xcodebuild configuration; defaults to Debug for
#                          --simulator and Release for device builds
#
# Examples:
#   bash scripts/build-ipad.sh --iphone --simulator
#   bash scripts/build-ipad.sh --ipad --no-simulator --device XXX --team YYY --ipa
#   bash scripts/build-ipad.sh --iphone --ipa   # unsigned device ipa
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHELL="$ROOT/shell"
DIST="$ROOT/dist"

# ── defaults ──
TARGET="FreePlayer"          # iPad
USE_SIMULATOR=0              # default: no-simulator (device)
DEVICE=""
TEAM=""
MAKE_IPA=0
CONFIGURATION=""             # empty → Debug for simulator, Release for device

# ── parse args ──
while [ $# -gt 0 ]; do
  case "$1" in
    --ipad)          TARGET="FreePlayer";     shift ;;
    --iphone)        TARGET="FreePlayer-iPhone"; shift ;;
    --simulator)     USE_SIMULATOR=1;         shift ;;
    --no-simulator)  USE_SIMULATOR=0;         shift ;;
    --device)        DEVICE="$2"; shift 2 ;;
    --team)          TEAM="$2";   shift 2 ;;
    --ipa)           MAKE_IPA=1;  shift ;;
    --configuration) CONFIGURATION="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Shipped device artifacts default to Release; simulator compile checks to Debug.
if [ -z "$CONFIGURATION" ]; then
  if [ "$USE_SIMULATOR" = 1 ]; then CONFIGURATION="Debug"; else CONFIGURATION="Release"; fi
fi

# ── resolve destination ──
if [ "$USE_SIMULATOR" = 1 ]; then
  case "$TARGET" in
    FreePlayer)        SIM_DEST="${SIM_DEST:-platform=iOS Simulator,name=iPad Pro 13-inch (M5)}" ;;
    FreePlayer-iPhone) SIM_DEST="${SIM_DEST:-platform=iOS Simulator,name=iPhone 17}" ;;
  esac
  DEST="$SIM_DEST"
else
  if [ -n "$DEVICE" ]; then
    DEST="platform=iOS,id=$DEVICE"
  else
    DEST="generic/platform=iOS"
  fi
fi

# ── 1. web assets (the Xcode pre-build script rsyncs dist/ into the bundle) ──
if [ ! -f "$DIST/index.html" ]; then
  echo "[ios] vite build..."
  (cd "$ROOT" && node_modules/.bin/vite build)
fi

# ── 2. icons (regenerate AppIcon + icns from assets/logo.svg) ──
echo "[ios] icons..."
(cd "$ROOT" && node scripts/icons.mjs)

# ── 3. build version: <pkg.version> on tag builds, else <version>-<git-hash> ──
VER=$(node -p "require('$ROOT/package.json').version")
if git -C "$ROOT" describe --tags --exact-match >/dev/null 2>&1; then
  FP_BUILD_VERSION="$VER"
else
  HASH=$(git -C "$ROOT" rev-parse --short HEAD)
  FP_BUILD_VERSION="$VER-$HASH"
fi
echo "[ios] build version: $FP_BUILD_VERSION"
export FP_BUILD_VERSION

# ── 4. Xcode project ──
echo "[ios] xcodegen generate..."
(cd "$SHELL" && xcodegen generate)

# ── 5. build ──
if [ "$USE_SIMULATOR" = 1 ]; then
  echo "[ios] building $TARGET for simulator ($DEST, $CONFIGURATION)..."
  (cd "$SHELL" && xcodebuild -project FreePlayer.xcodeproj -scheme "$TARGET" \
    -configuration "$CONFIGURATION" -destination "$DEST" build)
elif [ -n "$DEVICE" ]; then
  SIGN_ARGS=""
  if [ -n "$TEAM" ]; then
    SIGN_ARGS="DEVELOPMENT_TEAM=$TEAM CODE_SIGN_STYLE=Automatic"
  fi
  echo "[ios] building $TARGET for device $DEVICE${TEAM:+ (team $TEAM)} ($CONFIGURATION)..."
  # shellcheck disable=SC2086
  (cd "$SHELL" && xcodebuild -project FreePlayer.xcodeproj -scheme "$TARGET" \
    -configuration "$CONFIGURATION" -destination "$DEST" -allowProvisioningUpdates \
    $SIGN_ARGS build)
else
  echo "[ios] building $TARGET for generic device (unsigned, $CONFIGURATION)..."
  (cd "$SHELL" && xcodebuild -project FreePlayer.xcodeproj -scheme "$TARGET" \
    -configuration "$CONFIGURATION" -destination "$DEST" \
    CODE_SIGNING_ALLOWED=NO build)
fi

# ── 6. locate the product ──
if [ "$USE_SIMULATOR" = 1 ]; then
  PRODUCT_DIR="$CONFIGURATION-iphonesimulator"
else
  PRODUCT_DIR="$CONFIGURATION-iphoneos"
fi
APP=$(find "$HOME/Library/Developer/Xcode/DerivedData/FreePlayer-"* \
  -path "*$PRODUCT_DIR/${TARGET}.app" -type d 2>/dev/null | head -1)
[ -n "$APP" ] || { echo "==> built app not found" >&2; exit 3; }
echo "==> $APP"

# ── 7. pack an .ipa when requested (--ipa) ──
if [ "$MAKE_IPA" = 1 ]; then
  PKG=$(mktemp -d)
  mkdir -p "$PKG/Payload"
  cp -R "$APP" "$PKG/Payload/"
  OUT="$ROOT/shell/release"
  mkdir -p "$OUT"
  STAMP=$(date +%Y%m%d-%H%M)
  if [ "$USE_SIMULATOR" = 0 ] && [ -n "$DEVICE" ] && [ -n "$TEAM" ]; then
    PLATFORM="ios-arm64"            # signed device build
  elif [ "$USE_SIMULATOR" = 0 ]; then
    PLATFORM="ios-arm64-unsigned"   # unsigned device build
  else
    PLATFORM="ios-simulator"        # simulator build
  fi
  IPA="$OUT/$TARGET-$VER-$PLATFORM-$STAMP.ipa"
  (cd "$PKG" && zip -qr "$IPA" Payload)
  rm -rf "$PKG"
  echo "==> $IPA"
fi
