#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
APP="${1:?Usage: build_app.sh /absolute/path/StudSync.app [version] [build]}"
VERSION="${2:-0.1.0}"
BUILD="${3:-1}"
if [[ "$APP" != /*.app || ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$BUILD" =~ ^[1-9][0-9]*$ ]]; then
    echo "Expected an absolute .app path, numeric major.minor.patch version, and positive build number." >&2
    exit 2
fi
swift build --arch arm64 -c release
BIN_DIR="$(swift build --arch arm64 -c release --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/StudSync" "$APP/Contents/MacOS/StudSync"
cp "$ROOT_DIR/Sources/StudSyncApp/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
for resource in "$BIN_DIR"/*.bundle; do
    if [[ -d "$resource" ]]; then cp -R "$resource" "$APP/Contents/Resources/"; fi
done
mkdir -p "$APP/Contents/Resources/Licenses"
install -m 644 UNLICENSE "$APP/Contents/Resources/Licenses/StudSync.txt"
install -m 644 .build/checkouts/SwiftSoup/LICENSE "$APP/Contents/Resources/Licenses/SwiftSoup.txt"
install -m 644 .build/checkouts/Sparkle/LICENSE "$APP/Contents/Resources/Licenses/Sparkle.txt"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>StudSync</string>
<key>CFBundleIdentifier</key><string>com.gnagster.StudSync</string>
<key>CFBundleName</key><string>StudSync</string>
<key>CFBundleDisplayName</key><string>StudSync</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>de</string></array>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c 'Merge config/Updates.plist' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Frameworks"
ditto --norsrc --noextattr .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework"
# Immutable package artifacts need writable copies to remove Finder metadata.
chmod -R u+w "$APP/Contents/Frameworks"
xattr -cr "$APP"
# Preserve Sparkle's vendor signatures on its framework and helper processes.
codesign --force --sign - --identifier com.gnagster.StudSync "$APP"
codesign --verify --deep --strict "$APP"
