#!/bin/bash
# Sparkle compares only sparkle:version (CFBundleVersion) to decide whether
# an update is newer. Commit count is monotonic only along one line of
# history — releasing from a branch with fewer commits than the last
# release, or re-tagging the same commit, publishes a build number that
# every installed client silently ignores forever. Fail loudly instead.
# Usage: check-build-monotonic.sh <new-build> <owner/repo>
set -euo pipefail

if [ $# -ne 2 ]; then
    echo "Usage: $0 <new-build> <owner/repo>"
    exit 1
fi

NEW="$1"; REPO="$2"

CURRENT=$(curl -fsSL "https://github.com/${REPO}/releases/latest/download/appcast.xml" 2>/dev/null \
    | sed -n 's/.*<sparkle:version>\([0-9][0-9]*\)<\/sparkle:version>.*/\1/p' | head -1 || true)

if [ -z "$CURRENT" ]; then
    echo "No published appcast found — first release, skipping monotonic check."
    exit 0
fi

if [ "$NEW" -le "$CURRENT" ]; then
    echo "ERROR: new build number ${NEW} is not greater than the published ${CURRENT}."
    echo "       Installed clients would never see this update."
    echo "       (Releasing from a branch with fewer commits than the last release?)"
    exit 1
fi

echo "Build number OK: ${NEW} > ${CURRENT}"
