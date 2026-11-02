#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE="${1:?Provide the verified release ZIP}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/repo/script" "$WORK/repo/config"
cp "$ROOT/script/package_release.sh" "$WORK/repo/script/"
cp "$ROOT/config/Updates.plist" "$WORK/repo/config/"
ditto -x -k "$ARCHIVE" "$WORK/original"
PLIST="$WORK/original/StudSync.app/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
cat > "$WORK/repo/script/build_app.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
ditto --norsrc --noextattr "$FIXTURE_APP" "$1"
SH
chmod +x "$WORK/repo/script/build_app.sh"
export FIXTURE_APP="$WORK/original/StudSync.app"
bash "$WORK/repo/script/package_release.sh" "$VERSION" "$BUILD" "$WORK/control" > "$WORK/log" 2>&1
for key in CFBundleShortVersionString CFBundleIdentifier SUVerifyUpdateBeforeExtraction; do
    export FIXTURE_APP="$WORK/$key/StudSync.app"
    mkdir -p "$(dirname "$FIXTURE_APP")"
    ditto --norsrc --noextattr "$WORK/original/StudSync.app" "$FIXTURE_APP"
    case "$key" in
        CFBundleShortVersionString) value=invalid-version ;;
        CFBundleIdentifier) value=com.example.invalid ;;
        SUVerifyUpdateBeforeExtraction) value=false ;;
    esac
    chmod u+w "$FIXTURE_APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :$key $value" "$FIXTURE_APP/Contents/Info.plist"
    xattr -cr "$FIXTURE_APP"
    codesign --force --sign - "$FIXTURE_APP" > "$WORK/sign.log" 2>&1
    codesign --verify --deep --strict "$FIXTURE_APP"
    if bash "$WORK/repo/script/package_release.sh" "$VERSION" "$BUILD" "$WORK/out-$key" > "$WORK/log" 2>&1; then
        echo "Packager accepted invalid $key." >&2; exit 1
    fi
    if [[ -e "$WORK/out-$key/StudSync-$VERSION-arm64.zip" ]]; then
        echo 'Rejected bundle escaped into release output.' >&2; exit 1
    fi
done
echo 'Signed bundles with invalid version, identity and update trust settings were rejected.'
