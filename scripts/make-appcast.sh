#!/bin/bash
# Writes the single-item Sparkle appcast. Shared by release.sh and the CI
# release workflow so the XML template lives in exactly one place.
# Usage: make-appcast.sh <version> <build> <ed-signature> <length> <repo> <output-path>
set -euo pipefail

if [ $# -ne 6 ]; then
    echo "Usage: $0 <version> <build> <ed-signature> <length> <owner/repo> <output-path>"
    exit 1
fi

VERSION="$1"; BUILD="$2"; ED_SIGNATURE="$3"; LENGTH="$4"; REPO="$5"; OUT="$6"

PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v${VERSION}/DynamicPomodoro-${VERSION}.zip"
FEED_URL="https://github.com/${REPO}/releases/latest/download/appcast.xml"

cat > "$OUT" <<EOF
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

echo "Wrote ${OUT} (version ${VERSION}, build ${BUILD})"
