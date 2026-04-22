#!/bin/bash
# Builds DynamicPomodoro.app and installs it to /Applications.
# Usage: ./build-app.sh
# Requirements: Xcode Command Line Tools (xcode-select --install)

set -e

APP_NAME="DynamicPomodoro"
BUNDLE_ID="com.personal.dynamic-pomodoro"
APP_DIR="/Applications/${APP_NAME}.app"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Building release binary..."
cd "$SCRIPT_DIR"
swift build -c release 2>&1

BINARY=".build/arm64-apple-macosx/release/${APP_NAME}"
# Intel Macs produce a different path
if [ ! -f "$BINARY" ]; then
    BINARY=".build/x86_64-apple-macosx/release/${APP_NAME}"
fi
if [ ! -f "$BINARY" ]; then
    # Generic fallback
    BINARY=$(find .build -name "$APP_NAME" -type f | grep release | head -1)
fi

if [ ! -f "$BINARY" ]; then
    echo "ERROR: Could not find release binary. Run 'swift build -c release' manually to debug."
    exit 1
fi

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "$BINARY" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

cat > "${APP_DIR}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>Dynamic Pomodoro</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSUserNotificationAlertStyle</key>
    <string>alert</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# Copy app icon
ICON_SRC="${SCRIPT_DIR}/Sources/DynamicPomodoro/Resources/AppIcon.icns"
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "${APP_DIR}/Contents/Resources/AppIcon.icns"
else
    echo "Warning: AppIcon.icns not found — run: swift generate-icon.swift"
fi

# Copy the bundled activities.json resource so the app can find it
RESOURCES_SRC=$(find .build -path "*/DynamicPomodoro_DynamicPomodoro.bundle/Contents/Resources" -type d 2>/dev/null | head -1)
if [ -n "$RESOURCES_SRC" ]; then
    cp "${RESOURCES_SRC}/activities.json" "${APP_DIR}/Contents/Resources/"
else
    # Fallback: copy directly from source
    cp "${SCRIPT_DIR}/Sources/DynamicPomodoro/Resources/activities.json" "${APP_DIR}/Contents/Resources/"
fi

echo "Installing to /Applications..."
echo "(You may be prompted for your password)"

echo ""
echo "Done! Dynamic Pomodoro installed to /Applications."
echo "Launch it from Spotlight (⌘Space → Dynamic Pomodoro) or from /Applications."
echo "It will appear in the menu bar."
