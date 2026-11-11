#!/usr/bin/env bash
set -euo pipefail
# Runs `swift test` before a push unless every pushed ref only changes allowlisted documentation.
# Hosted CI stays authoritative; this catches failures before a review and CI round trip.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(git rev-parse --show-toplevel)"
zero=0000000000000000000000000000000000000000
needed=false
while read -r local_ref local_sha remote_ref remote_sha; do
    [[ "$local_sha" == "$zero" ]] && continue # Branch deletion.
    base="$remote_sha"
    if [[ "$base" == "$zero" ]]; then
        base="$(git merge-base "$local_sha" origin/master 2>/dev/null || true)"
    fi
    # The classifier compares against HEAD; any other pushed commit is tested unconditionally.
    if [[ -z "$base" || "$local_sha" != "$(git rev-parse HEAD)" ]]; then needed=true; break; fi
    output="$(mktemp)"
    if GITHUB_EVENT_NAME=pull_request STUDSYNC_BASE_SHA="$base" GITHUB_OUTPUT="$output" "$SCRIPT_DIR/swift_scan_scope.sh" > /dev/null 2>&1 \
        && grep -Fxq 'scan=false' "$output"; then
        rm -f "$output"
    else
        rm -f "$output"; needed=true; break
    fi
done
if [[ "$needed" == true ]]; then
    echo 'pre-push: running swift test (documentation-only pushes skip this).'
    swift test
fi
