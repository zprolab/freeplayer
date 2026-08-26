#!/bin/bash
# FreePlayer — run automated tests in the iOS Simulator.
#
# Usage:
#   bash scripts/test-simulator.sh              # run all tests (unit + UI)
#   bash scripts/test-simulator.sh unit          # unit tests only
#   bash scripts/test-simulator.sh ui            # UI tests only
#   bash scripts/test-simulator.sh --device "iPad Pro 13-inch (M5)"
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHELL="$ROOT/shell"
DIST="$ROOT/dist"

# ── parse args ──
TEST_TYPE="all"
DEVICE="iPad Pro 13-inch (M5)"

while [ $# -gt 0 ]; do
  case "$1" in
    unit)   TEST_TYPE="unit";   shift ;;
    ui)     TEST_TYPE="ui";     shift ;;
    --device) DEVICE="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

echo "╔══════════════════════════════════════════╗"
echo "║  FreePlayer — Simulator Test Runner      ║"
echo "╠══════════════════════════════════════════╣"
echo "║  Type:  $TEST_TYPE"
echo "║  Device: $DEVICE"
echo "╚══════════════════════════════════════════╝"

# ── 1. ensure web assets exist ──
if [ ! -f "$DIST/index.html" ]; then
  echo "[1/5] Building web assets..."
  (cd "$ROOT" && node_modules/.bin/vite build)
else
  echo "[1/5] Web assets already built."
fi

# ── 2. generate icons ──
echo "[2/5] Generating icons..."
(cd "$ROOT" && node scripts/icons.mjs)

# ── 3. generate Xcode project ──
echo "[3/5] Generating Xcode project..."
VER=$(node -p "require('$ROOT/package.json').version")
HASH=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo "dev")
export FP_BUILD_VERSION="$VER-$HASH"
(cd "$SHELL" && xcodegen generate)

# ── 4. clean derived data (fixes stale XCTest framework issues) ──
echo "[4/5] Cleaning derived data..."
rm -rf ~/Library/Developer/Xcode/DerivedData/FreePlayer-*

# ── 5. build + test ──
DEST="platform=iOS Simulator,name=$DEVICE"

case "$TEST_TYPE" in
  unit)
    echo "[5/5] Building & running unit tests..."
    (cd "$SHELL" && xcodebuild build-for-testing \
      -project FreePlayer.xcodeproj \
      -scheme FreePlayerTests \
      -configuration Debug \
      -destination "$DEST" \
      CODE_SIGNING_ALLOWED=NO \
      2>&1 | tail -30)
    (cd "$SHELL" && xcodebuild test-without-building \
      -project FreePlayer.xcodeproj \
      -scheme FreePlayerTests \
      -configuration Debug \
      -destination "$DEST" \
      -only-testing:FreePlayerTests \
      2>&1 | tail -50)
    ;;
  ui)
    echo "[5/5] Building & running UI tests..."
    (cd "$SHELL" && xcodebuild build-for-testing \
      -project FreePlayer.xcodeproj \
      -scheme FreePlayerUITests \
      -configuration Debug \
      -destination "$DEST" \
      CODE_SIGNING_ALLOWED=NO \
      2>&1 | tail -30)
    (cd "$SHELL" && xcodebuild test-without-building \
      -project FreePlayer.xcodeproj \
      -scheme FreePlayerUITests \
      -configuration Debug \
      -destination "$DEST" \
      -only-testing:FreePlayerUITests \
      2>&1 | tail -50)
    ;;
  all)
    echo "[5/5] Building & running all tests..."
    (cd "$SHELL" && xcodebuild build-for-testing \
      -project FreePlayer.xcodeproj \
      -scheme FreePlayer \
      -configuration Debug \
      -destination "$DEST" \
      CODE_SIGNING_ALLOWED=NO \
      2>&1 | tail -30)
    (cd "$SHELL" && xcodebuild test-without-building \
      -project FreePlayer.xcodeproj \
      -scheme FreePlayer \
      -configuration Debug \
      -destination "$DEST" \
      2>&1 | tail -80)
    ;;
esac

echo ""
echo "✅ Tests completed."
