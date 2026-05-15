#!/bin/bash
# Cuts a new release: builds the .app, zips it, signs the zip with Sparkle's
# EdDSA key, generates appcast.xml, tags the commit, and creates a GitHub
# release with both the zip AND appcast.xml as assets. Installed clients
# fetch the appcast via GitHub's `releases/latest/download/appcast.xml`
# redirect, so we never commit the appcast to main.
#
# Usage: ./release.sh <version> [build]
#   version: e.g. 1.0.1 (CFBundleShortVersionString — what users see)
#   build:   monotonic integer (CFBundleVersion — what Sparkle compares)
#            Defaults to the count of git commits, so it always increases.
#
# One-time setup:
#   1. brew install --cask sparkle      # provides generate_keys / sign_update
#   2. Run `generate_keys` once. Paste the public key into build-app.sh
#      (SU_PUBLIC_ED_KEY). The private key stays in your Keychain.
#   3. gh auth login                     # so this script can create releases

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <version> [build]"
    echo "Example: $0 1.0.1"
    exit 1
fi

VERSION="$1"
BUILD="${2:-$(git rev-list --count HEAD)}"
APP_NAME="DynamicPomodoro"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZIP_NAME="${APP_NAME}-${VERSION}.zip"
ZIP_PATH="${SCRIPT_DIR}/dist/${ZIP_NAME}"
APPCAST_PATH="${SCRIPT_DIR}/dist/appcast.xml"
REPO="BGSoares/dynamic-pomodoro"
FEED_URL="https://github.com/${REPO}/releases/latest/download/appcast.xml"

# Locate sign_update — bundled inside Sparkle.framework when Sparkle is on
# disk via Homebrew Cask. Falls back to the SPM-resolved framework so this
# works on a fresh checkout too.
SIGN_UPDATE=$(command -v sign_update || true)
if [ -z "$SIGN_UPDATE" ]; then
    SIGN_UPDATE=$(find /Applications -name sign_update 2>/dev/null | head -1)
fi
if [ -z "$SIGN_UPDATE" ]; then
    SIGN_UPDATE=$(find "${SCRIPT_DIR}/.build" -name sign_update 2>/dev/null | head -1)
fi
if [ -z "$SIGN_UPDATE" ]; then
    echo "ERROR: sign_update not found. Install Sparkle: brew install --cask sparkle"
    exit 1
fi

# Refuse to release with a dirty tree — easy footgun.
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "ERROR: working tree is dirty. Commit or stash first."
    exit 1
fi

echo "==> Building ${APP_NAME} v${VERSION} (build ${BUILD})..."
"${SCRIPT_DIR}/build-app.sh" "$VERSION" "$BUILD"

# Zip the .app bundle as Sparkle expects (top-level entry is the .app)
mkdir -p "${SCRIPT_DIR}/dist"
rm -f "$ZIP_PATH"
echo "==> Zipping /Applications/${APP_NAME}.app -> ${ZIP_PATH}..."
(cd /Applications && ditto -c -k --keepParent --sequesterRsrc "${APP_NAME}.app" "$ZIP_PATH")

echo "==> Signing zip with EdDSA key..."
SIG_OUTPUT=$("$SIGN_UPDATE" "$ZIP_PATH")
# sign_update prints e.g. `sparkle:edSignature="…" length="…"`
ED_SIGNATURE=$(echo "$SIG_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
LENGTH=$(echo "$SIG_OUTPUT" | sed -n 's/.*length="\([^"]*\)".*/\1/p')
if [ -z "$ED_SIGNATURE" ] || [ -z "$LENGTH" ]; then
    echo "ERROR: sign_update output unexpected: $SIG_OUTPUT"
    exit 1
fi

PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v${VERSION}/${ZIP_NAME}"

# Generate appcast.xml. Sparkle accepts arbitrary additional <item> entries
# but the standard implementation only needs the latest — clients pick the
# highest sparkle:version they understand. Keeping a single item simplifies
# the file; add prior entries by hand if you want release notes history.
cat > "$APPCAST_PATH" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Dynamic Pomodoro</title>
        <link>${FEED_URL}</link>
        <description>Updates for Dynamic Pomodoro</description>
        <language>en</language>
        <item>
            <title>Version ${VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:version>${BUILD}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <enclosure
                url="${DOWNLOAD_URL}"
                length="${LENGTH}"
                type="application/octet-stream"
                sparkle:edSignature="${ED_SIGNATURE}" />
        </item>
    </channel>
</rss>
EOF

echo "==> Wrote appcast.xml to ${APPCAST_PATH}"

echo "==> Tagging v${VERSION}..."
git tag -a "v${VERSION}" -m "Release v${VERSION}"

echo "==> Pushing tag..."
git push origin "v${VERSION}"

echo "==> Creating GitHub release with zip + appcast.xml as assets..."
gh release create "v${VERSION}" "$ZIP_PATH" "$APPCAST_PATH" \
    --repo "$REPO" \
    --title "v${VERSION}" \
    --notes "Auto-update release. Existing installs will pick this up via Sparkle."

echo ""
echo "Done. v${VERSION} is live. Installed clients will see the update on their"
echo "next check (default: 24h, or via 'Check for Updates…' in the menu)."
echo "The latest appcast.xml is served at:"
echo "  ${FEED_URL}"
