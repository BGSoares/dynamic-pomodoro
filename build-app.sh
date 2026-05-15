#!/bin/bash
# Builds DynamicPomodoro.app and installs it to /Applications.
# Usage: ./build-app.sh [version] [build]
#   version: CFBundleShortVersionString (default: 1.0)
#   build:   CFBundleVersion (default: 1)
# Requirements: Xcode Command Line Tools (xcode-select --install)

set -e

APP_NAME="DynamicPomodoro"
BUNDLE_ID="com.personal.dynamic-pomodoro"
APP_DIR="/Applications/${APP_NAME}.app"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

VERSION="${1:-1.0}"
BUILD="${2:-1}"

# Sparkle appcast URL — Sparkle fetches this at startup (and on demand) to
# discover new versions. Points at GitHub's `releases/latest/download/`
# redirect so the URL is stable: each release uploads a fresh appcast.xml
# as an asset, and GitHub transparently serves the latest one here. No
# committed-to-main copy, no GitHub Pages.
FEED_URL="https://github.com/BGSoares/dynamic-pomodoro/releases/latest/download/appcast.xml"

# Sparkle EdDSA public key. Generated once via `generate_keys` (private key
# stays in your Keychain — never check it in). Paste the public key here.
# An empty value disables update verification, which Sparkle treats as a
# hard error — leaving it empty also leaves you defenceless against a
# tampered zip, so fill it in before publishing any release.
SU_PUBLIC_ED_KEY="${SU_PUBLIC_ED_KEY:-}"

echo "Building release binary (v${VERSION} build ${BUILD})..."
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
mkdir -p "${APP_DIR}/Contents/Frameworks"

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
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSUserNotificationAlertStyle</key>
    <string>alert</string>
    <key>NSCalendarsUsageDescription</key>
    <string>Dynamic Pomodoro mirrors your break timer to a calendar of your choice so the end time syncs to your iPhone and Apple Watch.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Dynamic Pomodoro mirrors your break timer to a calendar of your choice so the end time syncs to your iPhone and Apple Watch.</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>SUFeedURL</key>
    <string>${FEED_URL}</string>
    <key>SUPublicEDKey</key>
    <string>${SU_PUBLIC_ED_KEY}</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUScheduledCheckInterval</key>
    <integer>86400</integer>
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

# Bundle Sparkle.framework. SPM links against the framework but doesn't copy
# it into our app bundle (Xcode normally handles that via a build phase).
# Prefer the release-config copy SPM materialises alongside the binary;
# fall back to the XCFramework slice in .build/artifacts.
SPARKLE_FRAMEWORK=$(dirname "$BINARY")/Sparkle.framework
if [ ! -d "$SPARKLE_FRAMEWORK" ]; then
    SPARKLE_FRAMEWORK=$(find .build/artifacts -path "*macos-arm64*/Sparkle.framework" -type d 2>/dev/null | head -1)
fi
if [ ! -d "$SPARKLE_FRAMEWORK" ]; then
    SPARKLE_FRAMEWORK=$(find .build -name "Sparkle.framework" -type d 2>/dev/null | head -1)
fi
if [ ! -d "$SPARKLE_FRAMEWORK" ]; then
    echo "ERROR: Sparkle.framework not found in .build — auto-update will not work."
    echo "       Ensure the Sparkle SPM dependency is resolved (swift package resolve)."
    exit 1
fi
echo "Embedding Sparkle.framework from ${SPARKLE_FRAMEWORK}..."
cp -R "$SPARKLE_FRAMEWORK" "${APP_DIR}/Contents/Frameworks/"

# `swift build` only emits `@loader_path` as an rpath, so dyld looks for
# `@rpath/Sparkle.framework/...` next to the binary in Contents/MacOS/ and
# never inside Contents/Frameworks/ where we just copied it. Add the
# standard app-bundle Frameworks rpath before signing — adding it after
# would invalidate the signature.
install_name_tool -add_rpath @executable_path/../Frameworks \
    "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# Ad-hoc code-signing so Gatekeeper lets Sparkle relaunch the app after an
# update install. Without this, the relaunched binary can hit "killed: 9"
# on Apple Silicon (the kernel rejects unsigned ARM64 mach-o on relaunch).
# Sign helpers and framework first, then the outer bundle (top-down would
# invalidate inner signatures).
echo "Ad-hoc code-signing bundle..."
codesign --force --options runtime --sign - \
    "${APP_DIR}/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc" 2>/dev/null || true
codesign --force --options runtime --sign - \
    "${APP_DIR}/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc" 2>/dev/null || true
codesign --force --options runtime --sign - \
    "${APP_DIR}/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" 2>/dev/null || true
codesign --force --options runtime --sign - \
    "${APP_DIR}/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app" 2>/dev/null || true
codesign --force --options runtime --sign - \
    "${APP_DIR}/Contents/Frameworks/Sparkle.framework"
codesign --force --options runtime \
    --entitlements "${SCRIPT_DIR}/Entitlements.plist" \
    --sign - "${APP_DIR}"

if [ -z "$SU_PUBLIC_ED_KEY" ]; then
    echo ""
    echo "WARNING: SU_PUBLIC_ED_KEY is empty. Auto-update will refuse to install"
    echo "         signed appcasts. Generate keys before your first release:"
    echo "           $(dirname "$SPARKLE_FRAMEWORK")/../Resources/generate_keys"
    echo "         …or via Homebrew: brew install --cask sparkle"
fi

echo ""
echo "Done! Dynamic Pomodoro v${VERSION} (build ${BUILD}) installed to /Applications."
echo "Launch it from Spotlight (⌘Space → Dynamic Pomodoro) or from /Applications."
echo "It will appear in the menu bar."
