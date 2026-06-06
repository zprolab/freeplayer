#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────
# FreePlayer — Clean Build Artifacts
# ──────────────────────────────────────────────────────────
set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; NC='\033[0m'
info() { echo -e "${CYAN}[info]${NC}  $*"; }
ok()   { echo -e "${GREEN}[ ok ]${NC}  $*"; }

echo ""
info "Cleaning build artifacts..."

DIRS=("dist" "release" "node_modules/.cache" "node_modules/.vite")
for d in "${DIRS[@]}"; do
  if [ -d "$d" ]; then
    rm -rf "$d"
    ok "Removed $d"
  fi
done

# Clean macOS junk files
find . -name ".DS_Store" -delete 2>/dev/null || true

ok "Clean complete."
echo ""
