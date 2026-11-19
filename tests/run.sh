#!/bin/bash
# Compiles the AppKit-free model (Sources/Appearance.swift) with the checks in
# tests/main.swift and runs them. Exit is non-zero on any failure.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${TMPDIR:-/tmp}/claude-swipe-tests"
swiftc -swift-version 5 Sources/Appearance.swift tests/main.swift -o "$OUT"
"$OUT"
