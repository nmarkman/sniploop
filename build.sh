#!/bin/bash
# Builds Sniploop.swift into a minimal .app bundle (no Xcode).
# The bundle matters: macOS attaches Screen Recording permission to a real .app,
# not to a bare terminal binary.
set -e
cd "$(dirname "$0")"

APP="Sniploop.app"
BIN_DIR="$APP/Contents/MacOS"

rm -rf "$APP"
mkdir -p "$BIN_DIR"

echo "Compiling..."
swiftc -O -swift-version 5 Sniploop.swift -o "$BIN_DIR/Sniploop" \
    -framework Cocoa -framework ScreenCaptureKit

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Sniploop</string>
    <key>CFBundleIdentifier</key><string>com.nickmarkman.sniploop</string>
    <key>CFBundleName</key><string>Sniploop</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>12.3</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so TCC keeps a stable identity across rebuilds.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
