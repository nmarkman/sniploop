#!/bin/bash
# Builds the SwiftPM executable, wraps it in a .app bundle, embeds gifski, signs ad-hoc.
set -e
cd "$(dirname "$0")"

APP="Sniploop.app"
RES="$APP/Contents/Resources"
BIN_DIR="$APP/Contents/MacOS"
CONFIG="${1:-debug}"   # pass "release" for an optimized build

echo "Building ($CONFIG)..."
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Sniploop"

rm -rf "$APP"
mkdir -p "$BIN_DIR" "$RES"
cp "$BIN" "$BIN_DIR/Sniploop"

# Embed gifski (from Homebrew) so the export step can shell out to it.
if command -v gifski >/dev/null 2>&1; then
    cp "$(command -v gifski)" "$RES/gifski"
else
    echo "WARNING: gifski not found on PATH; GIF export will fail. Run: brew install gifski"
fi

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
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>com.nickmarkman.sniploop</string>
            <key>CFBundleURLSchemes</key><array><string>sniploop</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Prefer a stable self-signed identity so the Screen Recording grant survives rebuilds.
# (Ad-hoc signing mints a new identity each build, which invalidates the TCC grant.)
# Falls back to ad-hoc when the identity isn't present (e.g. on someone else's machine).
# Create the identity once via Keychain Access (Certificate Assistant) or the commands in docs.
SIGN_ID="${SNIPLOOP_SIGN_ID:-Sniploop Dev}"
if ! security find-identity -p codesigning | grep -q "$SIGN_ID"; then
    SIGN_ID="-"
fi
codesign --force --sign "$SIGN_ID" "$RES/gifski" >/dev/null 2>&1 || true
codesign --force --deep --sign "$SIGN_ID" "$APP" >/dev/null 2>&1 || true
echo "Built $APP (signing identity: $SIGN_ID)"
