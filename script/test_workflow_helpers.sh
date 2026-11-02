#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/repo/Sources" "$scratch/repo/docs" "$scratch/db"
cd "$scratch/repo"
git init -q
git config user.name Fixture
git config user.email fixture@example.invalid
echo '// Fixture' > Sources/Test.swift
echo 'Fixture' > README.md
git add .
git commit -qm baseline
base="$(git rev-parse HEAD)"
scope() {
    : > "$scratch/output"
    GITHUB_EVENT_NAME=pull_request STUDSYNC_BASE_SHA="$base" GITHUB_OUTPUT="$scratch/output" "$ROOT/script/swift_scan_scope.sh"
    grep -Fxq "scan=$1" "$scratch/output"
}
scope true # Empty diffs must fail toward extraction.
: > "$scratch/output"
GITHUB_EVENT_NAME=push GITHUB_OUTPUT="$scratch/output" "$ROOT/script/swift_scan_scope.sh"
grep -Fxq 'scan=true' "$scratch/output"
echo 'Updated' >> README.md
echo 'Notes' > 'docs/Überblick notes.md'
echo 'Agent instructions' > AGENTS.md
echo 'Security instructions' > SECURITY.md
git add .; git commit -qm docs
scope false
: > "$scratch/output"
GITHUB_EVENT_NAME=push STUDSYNC_BASE_SHA="$base" GITHUB_OUTPUT="$scratch/output" "$ROOT/script/swift_scan_scope.sh"
grep -Fxq 'scan=false' "$scratch/output"
echo 'Bundled resource' > Sources/help.md
git add .; git commit -qm resource
scope true
git rm -q Sources/help.md; git commit -qm remove-resource
echo 'Unknown input' > 'unknown input'
git add .; git commit -qm input
scope true
git rm -q 'unknown input'; git commit -qm remove
base="$(git rev-parse HEAD)"
git mv Sources/Test.swift docs/moved.md
git commit -qm rename
scope true
if GITHUB_EVENT_NAME=pull_request STUDSYNC_BASE_SHA=invalid GITHUB_OUTPUT="$scratch/output" "$ROOT/script/swift_scan_scope.sh" > "$scratch/error" 2>&1; then exit 1; fi
if GITHUB_EVENT_NAME=pull_request STUDSYNC_BASE_SHA=0000000000000000000000000000000000000000 GITHUB_OUTPUT="$scratch/output" "$ROOT/script/swift_scan_scope.sh" > "$scratch/error" 2>&1; then exit 1; fi

echo '// Fixture' > Sources/Test.swift
absolute="$(realpath Sources/Test.swift)"
mkdir -p "$scratch/zip$(dirname "$absolute")"
cp Sources/Test.swift "$scratch/zip$absolute"
(cd "$scratch/zip" && zip -qr "$scratch/db/src.zip" .)
STUDSYNC_CODEQL_DATABASE="$scratch/db" "$ROOT/script/verify_codeql_sources.sh"
echo '// Missing from archive' > Sources/Missing.swift
if STUDSYNC_CODEQL_DATABASE="$scratch/db" "$ROOT/script/verify_codeql_sources.sh" > "$scratch/error" 2>&1; then exit 1; fi
rm Sources/Missing.swift Sources/Test.swift
if STUDSYNC_CODEQL_DATABASE="$scratch/db" "$ROOT/script/verify_codeql_sources.sh" > "$scratch/error" 2>&1; then exit 1; fi
if STUDSYNC_CODEQL_DATABASE="$scratch/absent" "$ROOT/script/verify_codeql_sources.sh" > "$scratch/error" 2>&1; then exit 1; fi
echo 'Workflow helper regressions passed.'
