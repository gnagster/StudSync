#!/usr/bin/env bash
set -euo pipefail
# Runs `swift test` before a push unless every pushed ref only changes allowlisted documentation.
# Hosted CI stays authoritative; this catches failures before a review and CI round trip.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(git rev-parse --show-toplevel)"
# Git exports GIT_DIR and friends to hooks; SwiftPM's dependency checkouts must not inherit them.
unset $(git rev-parse --local-env-vars)
zero=0000000000000000000000000000000000000000
needed=false
while read -r local_ref local_sha remote_ref remote_sha; do
    [[ "$local_sha" == "$zero" ]] && continue # Branch deletion.
    # Release tags point at master commits that passed CI; the release workflow tests them again.
    [[ "$local_ref" == refs/tags/* ]] && continue
    # swift test runs on the checkout, so only the checked-out commit can be verified.
    if [[ "$local_sha" != "$(git rev-parse HEAD)" ]]; then
        echo "pre-push: check out $local_ref before pushing it, so swift test runs on the pushed commit." >&2
        exit 1
    fi
    base="$remote_sha"
    if [[ "$base" == "$zero" ]]; then
        base="$(git merge-base "$local_sha" origin/master 2>/dev/null || true)"
    fi
    if [[ -z "$base" ]]; then needed=true; continue; fi
    output="$(mktemp)"
    if GITHUB_EVENT_NAME=pull_request STUDSYNC_BASE_SHA="$base" GITHUB_OUTPUT="$output" "$SCRIPT_DIR/swift_scan_scope.sh" > /dev/null 2>&1 \
        && grep -Fxq 'scan=false' "$output"; then
        rm -f "$output"
    else
        rm -f "$output"; needed=true
    fi
done # Every ref is checked before testing; a multi-ref push cannot slip a non-HEAD branch through.
if [[ "$needed" == true ]]; then
    echo 'pre-push: running swift test (documentation-only pushes skip this).'
    swift test
fi
