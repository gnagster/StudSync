#!/usr/bin/env bash
set -euo pipefail
scan=true
if [[ "${GITHUB_EVENT_NAME:-}" == pull_request || "${GITHUB_EVENT_NAME:-}" == pull_request_review || ( "${GITHUB_EVENT_NAME:-}" == push && -n "${STUDSYNC_BASE_SHA:-}" && "$STUDSYNC_BASE_SHA" != 0000000000000000000000000000000000000000 ) ]]; then
    if [[ ! "${STUDSYNC_BASE_SHA:-}" =~ ^[0-9a-fA-F]{40}$ ]]; then exit 2; fi
    paths="$(mktemp)"
    trap 'rm -f "$paths"' EXIT
    # Include both sides of renames so moving code into docs cannot skip extraction.
    diff_base="$STUDSYNC_BASE_SHA"
    if [[ "${GITHUB_EVENT_NAME:-}" == pull_request_review ]]; then
        # The checked-out merge ref can lag the event base; compare with its own first parent.
        git rev-parse --verify --quiet HEAD^2 > /dev/null || exit 1
        diff_base="$(git rev-parse --verify HEAD^1)" || exit 1
    fi
    git diff --no-renames --name-only -z "$diff_base" HEAD -- > "$paths" || exit 1
    if [[ -s "$paths" ]]; then
        scan=false
        while IFS= read -r -d '' path; do
            case "$path" in README.md|AGENTS.md|SECURITY.md|docs/*.md) ;;
                *) scan=true; break ;;
            esac
        done < "$paths"
    fi
fi
echo "scan=$scan" >> "${GITHUB_OUTPUT:?}"
echo "Swift scan required: $scan"
