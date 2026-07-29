#!/usr/bin/env bash
# Recompila o Orquestra.app a partir de app/main.swift
set -euo pipefail
cd "$(dirname "$0")"
APP="$HOME/Applications/Orquestra.app"
xcrun swiftc -O -parse-as-library main.swift -o Orquestra
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Orquestra "$APP/Contents/MacOS/Orquestra"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force -s - "$APP"
echo "ok: $APP"
