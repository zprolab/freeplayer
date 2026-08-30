#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="FreePlayer"
APP_BUNDLE="$ROOT_DIR/shell/build/FreePlayer.app"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
(cd "$ROOT_DIR" && pnpm build >/dev/null)
(cd "$ROOT_DIR" && cmake -S shell -B shell/build -G Ninja -DCMAKE_BUILD_TYPE=Debug >/dev/null)
(cd "$ROOT_DIR" && cmake --build shell/build >/dev/null)
(cd "$ROOT_DIR" && bash scripts/bundle.sh >/dev/null)

case "$MODE" in
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
  --debug|debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
  --logs|logs)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'process == "FreePlayer"'
    ;;
  --telemetry|telemetry)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.zprolab.FreePlayer"'
    ;;
  --verify|verify)
    /usr/bin/open -n "$APP_BUNDLE"
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *) echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac
