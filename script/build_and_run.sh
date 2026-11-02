#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-run}"
case "$MODE" in run|--build|--verify|--debug|--logs|--telemetry) ;; *) echo 'Usage: build_and_run.sh [--build|--verify|--debug|--logs|--telemetry]' >&2; exit 2 ;; esac
pkill -x StudSync >/dev/null 2>&1 || true
APP="$HOME/Applications/StudSync.app"
./script/build_app.sh "$APP"
if [[ "$MODE" == --build ]]; then exit 0; fi
case "$MODE" in
  --debug) lldb -- "$APP/Contents/MacOS/StudSync" ;;
  --logs) open -n "$APP"; /usr/bin/log stream --info --style compact --predicate 'process == "StudSync"' ;;
  --telemetry) open -n "$APP"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.gnagster.StudSync"' ;;
  --verify) open -n "$APP"; sleep 2; pgrep -x StudSync >/dev/null ;;
  run) open -n "$APP" ;;
esac
