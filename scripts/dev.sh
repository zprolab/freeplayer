#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────
# FreePlayer — Development Quick Start
# ──────────────────────────────────────────────────────────
set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'

echo ""
echo -e "${GREEN}┌──────────────────────────────────────┐${NC}"
echo -e "${GREEN}│  FreePlayer — Dev Mode               │${NC}"
echo -e "${GREEN}└──────────────────────────────────────┘${NC}"
echo ""

# Check node_modules
if [ ! -d "node_modules" ]; then
  echo -e "${CYAN}[info]${NC}  Installing dependencies..."
  npm install
fi

echo -e "${CYAN}[info]${NC}  Starting Vite + Electron..."
echo -e "  Vite  → http://localhost:5173"
echo -e "  Press ${GREEN}Ctrl+C${NC} to stop"
echo ""

npm run dev
