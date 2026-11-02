#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
TAG="${1:?Usage: publish_release.sh vMAJOR.MINOR.PATCH}"
if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then exit 2; fi
REPO=gnagster/StudSync
if [[ "$(gh release view "$TAG" --repo "$REPO" --json isDraft --jq .isDraft)" != true ]]; then exit 1; fi
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
NAME="StudSync-${TAG#v}-arm64.zip"
gh release download "$TAG" --repo "$REPO" --pattern "$NAME" --pattern "$NAME.sha256" --dir "$OUT"
read -r expected filename < "$OUT/$NAME.sha256"
if [[ ! "$expected" =~ ^[0-9a-fA-F]{64}$ || "$filename" != "$NAME" ]]; then exit 1; fi
actual="$(shasum -a 256 "$OUT/$NAME")"
if [[ "${actual%% *}" != "$expected" ]]; then exit 1; fi
swift package resolve
./script/sign_release.sh "${TAG#v}" "$OUT"
gh release upload "$TAG" "$OUT/appcast.xml" --repo "$REPO"
gh release edit "$TAG" --repo "$REPO" --draft=false --latest
