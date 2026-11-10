#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
VERSION="${1:?Usage: package_release.sh version build output-directory}"
BUILD="${2:?Provide a positive build number}"
OUT="${3:?Provide an output directory}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$BUILD" =~ ^[1-9][0-9]*$ ]]; then
    echo 'Release packaging requires major.minor.patch and a positive build number.' >&2
    exit 2
fi
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
NAME="StudSync-$VERSION-arm64.zip"
if [[ -e "$OUT/$NAME" || -e "$OUT/$NAME.sha256" ]]; then
    echo 'Release output already exists; choose an empty output directory.' >&2
    exit 1
fi
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
require() {
    local label="$1"; shift
    if ! "$@"; then
        printf 'Release check failed: %s (%s)\n' "$label" "$*" >&2
        exit 1
    fi
}
./script/build_app.sh "$STAGING/StudSync.app" "$VERSION" "$BUILD"
ditto -c -k --sequesterRsrc --keepParent "$STAGING/StudSync.app" "$STAGING/$NAME"
ditto -x -k "$STAGING/$NAME" "$STAGING/unpacked"
APP="$STAGING/unpacked/StudSync.app"
plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict "$APP"
require executable test -x "$APP/Contents/MacOS/StudSync"
require icon test -s "$APP/Contents/Resources/AppIcon.icns"
require 'Panel logo' test -s "$APP/Contents/Resources/StudSync_StudSyncApp.bundle/ClassicFold.png"
require 'Menu bar logo' test -s "$APP/Contents/Resources/StudSync_StudSyncApp.bundle/MenuBarLogo.png"
require architecture test "$(lipo -archs "$APP/Contents/MacOS/StudSync")" = arm64
require CFBundleIdentifier test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" = com.gnagster.StudSync
require CFBundleShortVersionString test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" = "$VERSION"
require CFBundleVersion test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")" = "$BUILD"
require LSMinimumSystemVersion test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")" = 15.0
require 'English localization' test -s "$APP/Contents/Resources/StudSync_StudSyncApp.bundle/en.lproj/Localizable.strings"
require 'German localization' test -s "$APP/Contents/Resources/StudSync_StudSyncApp.bundle/de.lproj/Localizable.strings"
require 'Sparkle framework' test -x "$APP/Contents/Frameworks/Sparkle.framework/Sparkle"
require SUFeedURL test "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$APP/Contents/Info.plist")" = https://github.com/gnagster/StudSync/releases/latest/download/appcast.xml
public_key="$(plutil -extract SUPublicEDKey raw -o - config/Updates.plist)"
require 'Update trust anchor' test -n "$public_key"
require SUPublicEDKey test "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist")" = "$public_key"
require SUVerifyUpdateBeforeExtraction test "$(plutil -extract SUVerifyUpdateBeforeExtraction raw -o - "$APP/Contents/Info.plist")" = true
require SUEnableAutomaticChecks test "$(plutil -extract SUEnableAutomaticChecks raw -o - "$APP/Contents/Info.plist")" = false
require SUShowReleaseNotes test "$(plutil -extract SUShowReleaseNotes raw -o - "$APP/Contents/Info.plist")" = false
require SUAutomaticallyUpdate test "$(plutil -extract SUAutomaticallyUpdate raw -o - "$APP/Contents/Info.plist")" = false
if ! otool -L "$APP/Contents/MacOS/StudSync" | grep -Fq '@rpath/Sparkle.framework/Versions/B/Sparkle'; then
    echo 'Release check failed: Sparkle linkage' >&2
    exit 1
fi
for license in StudSync SwiftSoup Sparkle; do
    require "$license license" test -s "$APP/Contents/Resources/Licenses/$license.txt"
done
mv "$STAGING/$NAME" "$OUT/$NAME"
(cd "$OUT" && shasum -a 256 "$NAME" > "$NAME.sha256" && shasum -a 256 -c "$NAME.sha256")
echo "Verified release archive: $OUT/$NAME"
