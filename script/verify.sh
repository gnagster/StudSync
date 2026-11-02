#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
./script/test_workflow_helpers.sh
swift test
./script/test_updates.sh
release_check="$(mktemp -d)"
trap 'rm -rf "$release_check"' EXIT
./script/package_release.sh 0.1.0 1 "$release_check"
git diff --check
