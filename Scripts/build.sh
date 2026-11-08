#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${IPHONE_BRIDGE_APP_PATH:-$ROOT/dist/iPhone Bridge.app}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin" "$ROOT/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache"
export SWIFT_MODULECACHE_PATH="$ROOT/.build/module-cache"
clang -fobjc-arc -O2 -mmacosx-version-min=14.0 -framework Foundation -larchive \
  "$ROOT/Sources/DeviceBridge.m" -o "$APP/Contents/Resources/bin/device-bridge"
swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path "$ROOT/.build/module-cache" \
  -parse-as-library "$ROOT/Sources/Models.swift" "$ROOT/Sources/Services.swift" \
  "$ROOT/Sources/Views.swift" "$ROOT/Sources/App.swift" -o "$APP/Contents/MacOS/iPhoneBridge"
cp -f "$ROOT/Vendor/ipatool/bin/ipatool" "$APP/Contents/Resources/bin/ipatool"
chmod 755 "$APP/Contents/Resources/bin/ipatool"
cp "$ROOT/Vendor/ipatool/LICENSE" "$APP/Contents/Resources/ipatool-LICENSE.txt"
if [ -f "$ROOT/Vendor/ipatool/PROVENANCE.json" ]; then cp "$ROOT/Vendor/ipatool/PROVENANCE.json" "$APP/Contents/Resources/ipatool-PROVENANCE.json"; fi
cp "$ROOT/Documentation/Инструкция.md" "$APP/Contents/Resources/Инструкция.md"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"; fi
codesign --force --sign - "$APP/Contents/Resources/bin/device-bridge"
codesign --force --sign - "$APP/Contents/Resources/bin/ipatool"
codesign --force --sign - "$APP"
echo "$APP"
