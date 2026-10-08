#!/usr/bin/env bash
# Builds the Studio plugin into your local Roblox Plugins folder so Studio
# auto-loads it. Re-run after editing anything under plugin/src.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGINS_DIR="${ROBLOX_PLUGINS_DIR:-$HOME/Documents/Roblox/Plugins}"
OUT="$PLUGINS_DIR/TaruTools.rbxm"

# Resolve a runnable rojo: explicit $ROJO, then PATH, then aftman tool-storage.
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
"$ROJO_BIN" build default.project.json --output "$OUT"

echo "Built plugin -> $OUT"
echo "Restart Roblox Studio (or it will pick this up on next launch)."
