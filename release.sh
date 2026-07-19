#!/bin/bash
# Cuts a new release: builds the .app, zips it, signs the zip with Sparkle's
# EdDSA key, then creates a GitHub release with both the zip and a fresh
# appcast.xml as assets. Sparkle clients discover the appcast via the
# `releases/latest/download/appcast.xml` redirect, so there's no copy on
# main and no GitHub Pages needed. Same pattern Lede uses. Requires the
# repo to be public — `releases/latest/download/` 404s on private repos.
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

set -euo pipefail

if [ -z "${1:-}" ]; then
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
    SIGN_UPDATE=$(find /Applications -name sign_update -print -quit 2>/dev/null)
fi
if [ -z "$SIGN_UPDATE" ]; then
    SIGN_UPDATE=$(find "${SCRIPT_DIR}/.build" -name sign_update -print -quit 2>/dev/null)
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

# Refuse to publish a build number Sparkle clients would ignore.
"${SCRIPT_DIR}/scripts/check-build-monotonic.sh" "$BUILD" "$REPO"

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

# Write appcast.xml into dist/. We attach it as a release asset (the
# `releases/latest/download/appcast.xml` redirect is what installed clients
# hit), so it never gets committed to main.
"${SCRIPT_DIR}/scripts/make-appcast.sh" "$VERSION" "$BUILD" "$ED_SIGNATURE" "$LENGTH" "$REPO" "$APPCAST_PATH"

echo "==> Tagging v${VERSION}..."
git tag -a "v${VERSION}" -m "Release v${VERSION}"

echo "==> Pushing tag..."
git push origin "v${VERSION}"

echo "==> Creating GitHub release with zip + appcast..."
gh release create "v${VERSION}" "$ZIP_PATH" "$APPCAST_PATH" \
    --repo "$REPO" \
    --title "v${VERSION}" \
    --notes "Auto-update release. Existing installs will pick this up via Sparkle."

echo ""
echo "Done. v${VERSION} is live. Installed clients will see the update on their"
echo "next check (default: 24h, or via 'Check for Updates…' in the menu)."
echo "The appcast is served at:"
echo "  ${FEED_URL}"
