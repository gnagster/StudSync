#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
./script/test_workflow_helpers.sh
swift test
./script/build_and_run.sh --build
git diff --check
