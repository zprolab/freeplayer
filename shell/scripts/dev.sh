#!/bin/bash
# FreePlayer shell — dev pipeline
# Starts vite (if needed) and launches the shell against the dev server.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if ! curl -s -o /dev/null http://localhost:5173 2>/dev/null; then
  echo "[dev] starting vite..."
  (cd "$ROOT" && nohup node_modules/.bin/vite > /tmp/fp-vite.log 2>&1 &)
  for i in $(seq 1 30); do
    curl -s -o /dev/null http://localhost:5173 2>/dev/null && break
    sleep 1
  done
fi

make -C "$ROOT/shell" -s
echo "[dev] launching FreePlayerShell..."
exec "$ROOT/shell/build/FreePlayerShell"
