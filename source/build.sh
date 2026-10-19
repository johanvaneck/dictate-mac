#!/bin/bash
# Builds, signs and installs Dictate into ~/Applications. Run from this folder.
set -euo pipefail
A="$HOME/Applications/Dictate.app"
pkill -x Dictate 2>/dev/null || true
mkdir -p "$A/Contents/MacOS"
cp Info.plist "$A/Contents/Info.plist"
swiftc -O main.swift -o "$A/Contents/MacOS/Dictate"
codesign --force --sign - -i local.dictate -r='designated => identifier "local.dictate"' "$A"
codesign -dr - "$A" 2>&1 | tail -1
tccutil reset Accessibility local.dictate || true
tccutil reset ListenEvent local.dictate || true
open "$A"
echo "Built and launched $A"
