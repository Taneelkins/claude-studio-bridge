#!/usr/bin/env bash
# Installs the always-on bridge daemon as a macOS LaunchAgent:
# starts at login, restarts on crash, and permanently owns the Studio port so
# the connection never drops when Claude Code chats open/close.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NODE="$(command -v node)"
LABEL="com.claudebridge.daemon"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
ENTRY="$ROOT/bridge/dist/daemon.js"
LOG="$ROOT/bridge/daemon.log"
UID_NUM="$(id -u)"

[ -f "$ENTRY" ] || { echo "error: $ENTRY missing — run: (cd bridge && npm run build)"; exit 1; }
[ -n "$NODE" ] || { echo "error: node not found on PATH"; exit 1; }

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$NODE</string>
    <string>$ENTRY</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
EOF
echo "Wrote $PLIST"
echo "  node:  $NODE"
echo "  entry: $ENTRY"

# Reload cleanly (works on both modern and older launchctl).
launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID_NUM" "$PLIST" 2>/dev/null || launchctl load -w "$PLIST"

echo "Loaded daemon '$LABEL'. Logs: $LOG"
