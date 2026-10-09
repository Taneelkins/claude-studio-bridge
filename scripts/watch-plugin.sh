#!/usr/bin/env bash
# Rebuilds the Studio plugin into your Plugins folder every time a file under
# plugin/ changes. Leave it running while you develop.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGINS_DIR="${ROBLOX_PLUGINS_DIR:-$HOME/Documents/Roblox/Plugins}"
OUT="$PLUGINS_DIR/TaruTools.rbxm"

ROJO_BIN="${ROJO:-}"
if [[ -z "$ROJO_BIN" ]]; then
  if command -v rojo >/dev/null 2>&1; then
    ROJO_BIN="rojo"
  else
    ROJO_BIN="$(ls "$HOME"/.aftman/tool-storage/rojo-rbx/rojo/*/rojo 2>/dev/null | head -1 || true)"
  fi
fi
[[ -n "$ROJO_BIN" ]] || { echo "error: rojo not found (set \$ROJO to its path)"; exit 1; }

mkdir -p "$PLUGINS_DIR"
cd "$ROOT/plugin"
echo "Watching plugin/ -> $OUT (Ctrl+C to stop)"
exec "$ROJO_BIN" build default.project.json --output "$OUT" --watch
