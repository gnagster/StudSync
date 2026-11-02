#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT="$PWD"
WORK="$(mktemp -d)"
SERVER_PID=""
cleanup() {
    if [[ -n "$SERVER_PID" ]]; then kill "$SERVER_PID" 2>/dev/null || true; fi
    for pidfile in "$WORK"/*/pid; do
        if [[ -f "$pidfile" ]]; then
            pid="$(cat "$pidfile")"
            if [[ "$pid" =~ ^[0-9]+$ ]] && ps -p "$pid" -o comm= | grep -q '/UpdateFixture$'; then kill "$pid" 2>/dev/null || true; fi
        fi
    done
    rm -rf "$WORK"
}
trap cleanup EXIT
FRAMEWORK="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
TOOLS="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
clang -fobjc-arc -Wno-incompatible-pointer-types -F "$(dirname "$FRAMEWORK")" -framework Cocoa -framework Sparkle \
    -Wl,-rpath,@executable_path/../Frameworks tests/UpdateIntegration/Fixture.m -o "$WORK/UpdateFixture"
swiftc tests/UpdateIntegration/Server.swift -o "$WORK/server"
# This ephemeral synthetic key never reads or replaces the production Keychain key.
PUBLIC_KEY="$(swift tests/UpdateIntegration/Key.swift "$WORK/fixture-key")"
cat > "$WORK/trust.plist" <<PLIST
<?xml version="1.0"?><plist version="1.0"><dict><key>SUPublicEDKey</key><string>$PUBLIC_KEY</string></dict></plist>
PLIST
for mode in valid invalid interrupted; do
    CASE="$WORK/$mode"
    mkdir -p "$CASE/web" "$CASE/installed"
    "$WORK/server" "$CASE/web" "$CASE/port" "$mode" > "$CASE/server.log" 2>&1 &
    SERVER_PID=$!
    for i in {1..100}; do [[ -s "$CASE/port" ]] && break; sleep 0.1; done
    PORT="$(cat "$CASE/port")"
    for version in 1 2; do
        if [[ "$version" == 1 ]]; then APP="$CASE/installed/UpdateFixture.app"; else APP="$CASE/web/UpdateFixture.app"; fi
        mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks"
        cp "$WORK/UpdateFixture" "$APP/Contents/MacOS/UpdateFixture"
        ditto --norsrc --noextattr "$FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
        chmod -R u+w "$APP/Contents/Frameworks"
        cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>UpdateFixture</string>
<key>CFBundleIdentifier</key><string>com.gnagster.StudSync.UpdateFixture.$(basename "$WORK").$mode</string>
<key>CFBundleName</key><string>UpdateFixture</string><key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>$version</string><key>CFBundleShortVersionString</key><string>0.0.$version</string>
<key>LSUIElement</key><true/><key>LSMinimumSystemVersion</key><string>15.0</string>
<key>SUFeedURL</key><string>http://127.0.0.1:$PORT/appcast.xml</string><key>SUPublicEDKey</key><string>$PUBLIC_KEY</string>
<key>SUVerifyUpdateBeforeExtraction</key><true/><key>SUEnableAutomaticChecks</key><false/>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
<key>FixtureResult</key><string>$CASE/result</string><key>FixturePID</key><string>$CASE/pid</string>
</dict></plist>
PLIST
        xattr -cr "$APP"
        codesign --force --sign - "$APP" >/dev/null 2>&1
    done
    ditto -c -k --sequesterRsrc --keepParent "$CASE/web/UpdateFixture.app" "$CASE/web/update.zip"
    SIGNATURE="$("$TOOLS/sign_update" --ed-key-file "$WORK/fixture-key" -p "$CASE/web/update.zip")"
    if [[ "$mode" == invalid ]]; then
        if [[ "${SIGNATURE:0:1}" == A ]]; then SIGNATURE="B${SIGNATURE:1}"; else SIGNATURE="A${SIGNATURE:1}"; fi
    fi
    SIZE="$(stat -f %z "$CASE/web/update.zip")"
    cat > "$CASE/web/appcast.xml" <<XML
<?xml version="1.0"?><rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>Fixture</title><item><title>Fixture 2</title><sparkle:version>2</sparkle:version><sparkle:shortVersionString>0.0.2</sparkle:shortVersionString><enclosure url="http://127.0.0.1:$PORT/update.zip" sparkle:edSignature="$SIGNATURE" length="$SIZE" type="application/octet-stream"/></item></channel></rss>
XML
    if [[ "$mode" == invalid ]]; then
        if swift script/verify_update.swift "$CASE/web/update.zip" "$CASE/web/appcast.xml" "$WORK/trust.plist" "http://127.0.0.1:$PORT/update.zip"; then
            echo 'Invalid update signature accepted by release verifier.' >&2; exit 1
        fi
    else
        swift script/verify_update.swift "$CASE/web/update.zip" "$CASE/web/appcast.xml" "$WORK/trust.plist" "http://127.0.0.1:$PORT/update.zip"
        if swift script/verify_update.swift "$CASE/web/update.zip" "$CASE/web/appcast.xml" "$WORK/trust.plist" 'https://unexpected.invalid/update.zip'; then
            echo 'Unexpected download URL accepted by release verifier.' >&2; exit 1
        fi
        printf damaged > "$CASE/truncated.zip"
        if swift script/verify_update.swift "$CASE/truncated.zip" "$CASE/web/appcast.xml" "$WORK/trust.plist" "http://127.0.0.1:$PORT/update.zip"; then
            echo 'Truncated archive accepted by release verifier.' >&2; exit 1
        fi
    fi
    open -g -n "$CASE/installed/UpdateFixture.app"
    for i in {1..600}; do [[ -s "$CASE/result" ]] && break; sleep 0.1; done
    RESULT="$(cat "$CASE/result" 2>/dev/null || echo timeout)"
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$CASE/installed/UpdateFixture.app/Contents/Info.plist")"
    codesign --verify --deep --strict "$CASE/installed/UpdateFixture.app"
    if [[ "$mode" == valid ]]; then
        [[ "$RESULT" == installed && "$VERSION" == 2 ]] || exit 1
    else
        [[ "$RESULT" == error && "$VERSION" == 1 ]] || exit 1
    fi
    echo "Sparkle $mode update passed (result=$RESULT, installed version=$VERSION)."
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    SERVER_PID=""
done
