#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────
# FreePlayer — macOS Packaging Script
# ──────────────────────────────────────────────────────────
set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# ── Colors ──
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[info]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ ok ]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC}  $*"; }
err()   { echo -e "${RED}[err ]${NC}  $*"; }

echo ""
echo -e "${GREEN}┌──────────────────────────────────────┐${NC}"
echo -e "${GREEN}│  FreePlayer — macOS Packaging        │${NC}"
echo -e "${GREEN}└──────────────────────────────────────┘${NC}"
echo ""

# ── Step 1: Clean previous outputs ──
info "Cleaning previous builds..."
rm -rf dist release
ok "dist/ and release/ removed"

# ── Step 2: Install dependencies ──
info "Checking dependencies..."
if [ ! -d "node_modules" ]; then
  info "Installing dependencies..."
  npm install
fi
ok "Dependencies ready"

# ── Step 3: Build frontend ──
info "Building Vite frontend..."
npx vite build
ok "Frontend built"

# ── Step 4: Package for macOS ──
info "Packaging for macOS (dmg + zip)..."
npx electron-builder --mac

# ── Done ──
echo ""
if [ -d "release" ]; then
  ok "macOS build complete!"
  echo ""
  echo "  Output:"
  for f in release/*.dmg release/*.zip release/mac* 2>/dev/null; do
    if [ -e "$f" ]; then
      echo -e "    ${GREEN}→${NC} $f"
    fi
  done
else
  warn "No release/ directory found — check for errors above"
fi
echo ""
