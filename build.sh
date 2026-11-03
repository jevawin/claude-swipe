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
# Fixed self-signed identity, so macOS keeps the Accessibility permission across rebuilds.
# Falls back to ad-hoc if the certificate is missing.
IDENTITY="ClaudeSwipe Local"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  codesign -s "$IDENTITY" --force "$APP" >/dev/null
else
  codesign -s - --force "$APP" >/dev/null
fi
pkill -x ClaudeSwipe || true
rm -rf "$DEST"
ditto "$APP" "$DEST"
echo "installed $DEST"
if [[ "${1:-}" == "--run" ]]; then
  open "$DEST"
fi
