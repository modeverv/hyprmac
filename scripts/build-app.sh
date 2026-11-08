#!/bin/bash
# Builds build/HyprMac.app (menu bar app, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

# Swift 6.x's default "swiftbuild" backend fails on some CLT-only setups; native works everywhere.
swift build -c release --build-system native 2>&1 | grep -v "has been deprecated" || true
BIN="$(swift build -c release --build-system native --show-bin-path 2>/dev/null)/hyprmac"
[ -x "$BIN" ] || { echo "build failed"; exit 1; }

APP=build/HyprMac.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/HyprMac"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>dev.local.hyprmac</string>
    <key>CFBundleName</key><string>HyprMac</string>
    <key>CFBundleExecutable</key><string>HyprMac</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - --identifier dev.local.hyprmac "$APP" >/dev/null
echo "built $APP"
