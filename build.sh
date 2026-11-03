#!/bin/bash
# Builds build/ClaudeSwipe.app and installs it to ~/Applications.
# The login item points at the installed copy, so always run that one.
# Pass --run to (re)launch it after installing.
set -euo pipefail
cd "$(dirname "$0")"
APP=build/ClaudeSwipe.app
DEST="$HOME/Applications/ClaudeSwipe.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -parse-as-library Sources/App.swift \
  -o "$APP/Contents/MacOS/ClaudeSwipe" -framework AppKit -framework SwiftUI -framework Carbon
cp recent_chats.py "$APP/Contents/Resources/"
cp Info.plist "$APP/Contents/"
codesign -s - --force "$APP" >/dev/null
pkill -x ClaudeSwipe || true
rm -rf "$DEST"
ditto "$APP" "$DEST"
echo "installed $DEST"
if [[ "${1:-}" == "--run" ]]; then
  open "$DEST"
fi
