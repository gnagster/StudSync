#!/usr/bin/env bash
set -euo pipefail
scan=true
if [[ "${GITHUB_EVENT_NAME:-}" == pull_request || ( "${GITHUB_EVENT_NAME:-}" == push && -n "${STUDSYNC_BASE_SHA:-}" && "$STUDSYNC_BASE_SHA" != 0000000000000000000000000000000000000000 ) ]]; then
    if [[ ! "${STUDSYNC_BASE_SHA:-}" =~ ^[0-9a-fA-F]{40}$ ]]; then exit 2; fi
    paths="$(mktemp)"
    trap 'rm -f "$paths"' EXIT
    # Include both sides of renames so moving code into docs cannot skip extraction.
    git diff --no-renames --name-only -z "$STUDSYNC_BASE_SHA" HEAD -- > "$paths" || exit 1
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
