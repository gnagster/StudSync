#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/bin"
cat > "$scratch/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$2" == graphql ]]; then
    cat "$REVIEW_FIXTURE/threads"
elif [[ "$*" == *'/reviews?'* ]]; then
    cat "$REVIEW_FIXTURE/reviews"
elif [[ "$*" == *'--jq'* ]]; then
    jq -r '.head.sha' "$REVIEW_FIXTURE/pr"
else
    cat "$REVIEW_FIXTURE/pr"
fi
MOCK
chmod +x "$scratch/bin/gh"
export PATH="$scratch/bin:$PATH" REVIEW_FIXTURE="$scratch" GITHUB_EVENT_NAME=pull_request_review GITHUB_REPOSITORY=owner/repo GITHUB_EVENT_PATH="$scratch/event"
echo '{"pull_request":{"number":1,"head":{"sha":"reviewed"}}}' > "$scratch/event"
echo '{"state":"open","draft":false,"head":{"sha":"reviewed"}}' > "$scratch/pr"
echo '[[{"id":1,"user":{"login":"coderabbitai[bot]","type":"Bot"},"state":"APPROVED","commit_id":"reviewed"}]]' > "$scratch/reviews"
echo '[{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"isResolved":true}]}}}}}]' > "$scratch/threads"
"$ROOT/script/require_review.sh"
reject() {
    if "$ROOT/script/require_review.sh" > "$scratch/log" 2>&1; then
        echo "Unexpected review authorization: $1" >&2; exit 1
    fi
}
cp "$scratch/reviews" "$scratch/approved"
for field in '.state = "COMMENTED"' '.state = "CHANGES_REQUESTED"' '.state = "DISMISSED"' '.commit_id = "older"' '.user.login = "someone"' '.user.type = "User"'; do
    jq "map(map($field))" "$scratch/approved" > "$scratch/reviews"
    reject "$field"
done
echo '[]' > "$scratch/reviews"; reject 'missing review'
# A newer request-changes on another page supersedes an older approval.
jq '.[1] = [ (.[0][0] | .id = 2 | .state = "CHANGES_REQUESTED") ]' "$scratch/approved" > "$scratch/reviews"
reject 'newer review on another page'
cp "$scratch/approved" "$scratch/reviews"
cp "$scratch/threads" "$scratch/resolved"
jq '.[1] = .[0] | .[1].data.repository.pullRequest.reviewThreads.nodes[0].isResolved = false' "$scratch/resolved" > "$scratch/threads"
reject 'unresolved thread on another page'
echo '[{"errors":[{"message":"denied"}]}]' > "$scratch/threads"; reject 'missing GraphQL data'
cp "$scratch/resolved" "$scratch/threads"
echo '{"state":"open","draft":false,"head":{"sha":"new"}}' > "$scratch/pr"; reject 'new head'
echo '{"state":"closed","draft":false,"head":{"sha":"reviewed"}}' > "$scratch/pr"; reject 'closed PR'
GITHUB_EVENT_NAME=push "$ROOT/script/require_review.sh"
echo 'Review gate regressions passed.'
