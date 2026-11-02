#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/repo/script" "$WORK/bin"
cp "$ROOT/script/publish_release.sh" "$WORK/repo/script/"
export EVENTS="$WORK/events"
cat > "$WORK/bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "$1 $2" in
    'release view')
        echo view >> "$EVENTS"
        if [[ "$SCENARIO" == published ]]; then echo false; else echo true; fi ;;
    'release download')
        echo download >> "$EVENTS"
        while [[ "$1" != --dir ]]; do shift; done
        out="$2"; name=StudSync-0.1.0-arm64.zip
        printf fixture > "$out/$name"
        if [[ "$SCENARIO" == corrupt ]]; then
            printf '%064d  %s\n' 0 "$name" > "$out/$name.sha256"
        else
            (cd "$out" && shasum -a 256 "$name" > "$name.sha256")
            if [[ "$SCENARIO" == unsafe-name ]]; then
                sed 's/StudSync-0.1.0-arm64.zip/..\/outside.zip/' "$out/$name.sha256" > "$out/unsafe"
                mv "$out/unsafe" "$out/$name.sha256"
            fi
        fi ;;
    'release upload')
        echo upload >> "$EVENTS"
        if [[ "$SCENARIO" == upload-failure ]]; then exit 1; fi ;;
    'release edit') echo publish >> "$EVENTS" ;;
    *) exit 2 ;;
esac
SH
cat > "$WORK/bin/swift" <<'SH'
#!/usr/bin/env bash
echo resolve >> "$EVENTS"
SH
cat > "$WORK/repo/script/sign_release.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo sign >> "$EVENTS"
if [[ "$SCENARIO" == signing-failure ]]; then exit 1; fi
printf fixture > "$2/appcast.xml"
SH
chmod +x "$WORK/bin/gh" "$WORK/bin/swift" "$WORK/repo/script/sign_release.sh"
export PATH="$WORK/bin:$PATH"
run_case() {
    export SCENARIO="$1"
    : > "$EVENTS"
    result=0
    bash "$WORK/repo/script/publish_release.sh" "${4:-v0.1.0}" > "$WORK/log" 2>&1 || result=$?
    if [[ "$result" != "$2" || "$(tr '\n' ' ' < "$EVENTS")" != "$3" ]]; then
        echo "Release guard failed: $SCENARIO (exit $result, expected $2)." >&2
        cat "$EVENTS" "$WORK/log" >&2
        exit 1
    fi
}
run_case published 1 'view '
run_case corrupt 1 'view download '
run_case unsafe-name 1 'view download '
run_case signing-failure 1 'view download resolve sign '
run_case upload-failure 1 'view download resolve sign upload '
run_case valid 0 'view download resolve sign upload publish '
run_case valid 2 '' invalid-tag
echo 'Release publication guards passed; no real credentials, signing keys or GitHub calls used.'
