#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
VERSION="${1:?Usage: sign_release.sh version release-directory}"
OUT="${2:?Provide a release directory}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then exit 2; fi
OUT="$(cd "$OUT" && pwd)"
TOOLS="$PWD/.build/artifacts/sparkle/Sparkle/bin"
ARCHIVE="$OUT/StudSync-$VERSION-arm64.zip"
"$TOOLS/generate_appcast" --account com.gnagster.StudSync.updates --maximum-deltas 0 \
    --download-url-prefix "https://github.com/gnagster/StudSync/releases/download/v$VERSION/" \
    --link https://github.com/gnagster/StudSync "$OUT"
xmllint --noout "$OUT/appcast.xml"
swift script/verify_update.swift "$ARCHIVE" "$OUT/appcast.xml" config/Updates.plist "https://github.com/gnagster/StudSync/releases/download/v$VERSION/StudSync-$VERSION-arm64.zip"
echo 'Release archive signed and appcast generated.'
