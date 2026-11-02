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
./script/build_app.sh "$STAGING/StudSync.app" "$VERSION" "$BUILD"
ditto -c -k --sequesterRsrc --keepParent "$STAGING/StudSync.app" "$STAGING/$NAME"
ditto -x -k "$STAGING/$NAME" "$STAGING/unpacked"
APP="$STAGING/unpacked/StudSync.app"
plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict "$APP"
[[ -x "$APP/Contents/MacOS/StudSync" ]] || exit 1
[[ -s "$APP/Contents/Resources/AppIcon.icns" ]] || exit 1
[[ "$(lipo -archs "$APP/Contents/MacOS/StudSync")" == arm64 ]] || exit 1
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" == com.gnagster.StudSync ]] || exit 1
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$VERSION" ]] || exit 1
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")" == "$BUILD" ]] || exit 1
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")" == 15.0 ]] || exit 1
[[ -s "$APP/Contents/Resources/StudSync_StudSyncApp.bundle/en.lproj/Localizable.strings" ]] || exit 1
[[ -s "$APP/Contents/Resources/StudSync_StudSyncApp.bundle/de.lproj/Localizable.strings" ]] || exit 1
[[ -x "$APP/Contents/Frameworks/Sparkle.framework/Sparkle" ]] || exit 1
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$APP/Contents/Info.plist")" == https://github.com/gnagster/StudSync/releases/latest/download/appcast.xml ]] || exit 1
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist")" == "$(plutil -extract SUPublicEDKey raw -o - config/Updates.plist)" ]] || exit 1
[[ "$(plutil -extract SUVerifyUpdateBeforeExtraction raw -o - "$APP/Contents/Info.plist")" == true ]] || exit 1
[[ "$(plutil -extract SUEnableAutomaticChecks raw -o - "$APP/Contents/Info.plist")" == false ]] || exit 1
[[ "$(plutil -extract SUAutomaticallyUpdate raw -o - "$APP/Contents/Info.plist")" == false ]] || exit 1
otool -L "$APP/Contents/MacOS/StudSync" | grep -Fq '@rpath/Sparkle.framework/Versions/B/Sparkle'
for license in StudSync SwiftSoup LRUCache SwiftAtomics Sparkle; do
    [[ -s "$APP/Contents/Resources/Licenses/$license.txt" ]] || exit 1
done
mv "$STAGING/$NAME" "$OUT/$NAME"
(cd "$OUT" && shasum -a 256 "$NAME" > "$NAME.sha256" && shasum -a 256 -c "$NAME.sha256")
echo "Verified release archive: $OUT/$NAME"
