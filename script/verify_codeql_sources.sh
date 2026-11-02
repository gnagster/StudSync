#!/usr/bin/env bash
set -euo pipefail
archive="${STUDSYNC_CODEQL_DATABASE:?}/src.zip"
entries="$(mktemp)"
sources="$(mktemp)"
trap 'rm -f "$entries" "$sources"' EXIT
unzip -Z1 "$archive" > "$entries" || exit 1
find Sources \( -type f -o -type l \) -name '*.swift' -print0 > "$sources" || exit 1
count=0
while IFS= read -r -d '' source; do
    absolute="$(realpath "$source")" || exit 1
    # ZIP's line listing cannot safely represent newline-containing source names.
    if [[ "$absolute" == *$'\n'* ]] || ! grep -Fxq -- "${absolute#/}" "$entries"; then
        echo "Missing or unsupported first-party Swift source: $source" >&2
        exit 1
    fi
    count=$((count + 1))
done < "$sources"
if [[ "$count" -eq 0 ]]; then
    echo 'No first-party Swift sources found.' >&2
    exit 1
fi
echo "All $count first-party Swift sources are present in the CodeQL archive."
