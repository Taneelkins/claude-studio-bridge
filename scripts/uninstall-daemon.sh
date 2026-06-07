#!/usr/bin/env bash
# Removes the always-on bridge daemon LaunchAgent.
set -euo pipefail

LABEL="com.claudebridge.daemon"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_NUM="$(id -u)"

launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
echo "Removed daemon '$LABEL'. (Chats fall back to electing an owner among themselves.)"
