#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────
# FreePlayer — Cross-Platform Packaging
# Requires macOS host (for macOS targets).
# Linux & Windows targets are built but may have platform
# limitations (e.g. DMG only buildable on macOS).
# ──────────────────────────────────────────────────────────
set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[info]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ ok ]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC}  $*"; }

PLATFORMS="${1:-mac,win,linux}"

echo ""
echo -e "${GREEN}┌──────────────────────────────────────┐${NC}"
echo -e "${GREEN}│  FreePlayer — Multi-Platform Build   │${NC}"
echo -e "${GREEN}└──────────────────────────────────────┘${NC}"
echo ""

info "Targeting platforms: ${PLATFORMS}"

# ── Clean & build ──
info "Cleaning previous builds..."
rm -rf dist release
ok "dist/ and release/ removed"

info "Building Vite frontend..."
npx vite build
ok "Frontend built"

# ── Package per platform ──
IFS=',' read -ra TARGETS <<< "$PLATFORMS"
for target in "${TARGETS[@]}"; do
  target=$(echo "$target" | xargs)  # trim whitespace
  echo ""
  info "Packaging for ${target}..."
  case "$target" in
    mac|macos|darwin)
      npx electron-builder --mac
      ;;
    win|windows)
      npx electron-builder --win
      ;;
    linux)
      npx electron-builder --linux
      ;;
    *)
      warn "Unknown target: ${target} — skipping"
      ;;
  esac
done

# ── Summary ──
echo ""
ok "All builds complete!"
echo ""
echo "  Output:"
if [ -d "release" ]; then
  find release -type f \( -name "*.dmg" -o -name "*.zip" -o -name "*.exe" -o -name "*.AppImage" -o -name "*.deb" -o -name "*.snap" \) 2>/dev/null | while read -r f; do
    SIZE=$(du -sh "$f" | cut -f1)
    echo -e "    ${GREEN}→${NC} $f  ${YELLOW}(${SIZE})${NC}"
  done
else
  warn "No release/ directory found"
fi
echo ""
