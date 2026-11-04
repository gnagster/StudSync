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
elif [[ "$*" == *'/comments?'* ]]; then
    cat "$REVIEW_FIXTURE/comments"
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
echo '{"pull_request":{"number":1,"head":{"sha":"reviewed"},"base":{"sha":"base"}}}' > "$scratch/event"
echo '{"state":"open","draft":false,"head":{"sha":"reviewed"},"base":{"sha":"base"}}' > "$scratch/pr"
echo '[[{"id":1,"user":{"login":"coderabbitai[bot]","type":"Bot"},"state":"APPROVED","commit_id":"reviewed"}]]' > "$scratch/reviews"
echo '[{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"isResolved":true}]}}}}}]' > "$scratch/threads"
jq -n --arg body '<!-- codex-review-state:v1 {"code_review":{"status":"completed","commit_sha":"reviewed","has_any_findings":false,"has_unresolved_findings":false}} -->' '[[{id:1,user:{login:"chatgpt-codex-connector[bot]",type:"Bot"},body:$body}]]' > "$scratch/comments"
"$ROOT/script/require_review.sh"
reject() {
    if "$ROOT/script/require_review.sh" > "$scratch/log" 2>&1; then
        echo "Unexpected review authorization: $1" >&2; exit 1
    fi
}
cp "$scratch/comments" "$scratch/clean"
for replacement in 'in_progress' 'older' 'true' 'null'; do
    case "$replacement" in
        in_progress) filter='map(map(.body |= sub("completed"; "in_progress")))' ;;
        older) filter='map(map(.body |= sub("reviewed"; "older")))' ;;
        true) filter='map(map(.body |= gsub("false"; "true")))' ;;
        null) filter='map(map(.body |= gsub("false"; "null")))' ;;
    esac
    jq "$filter" "$scratch/clean" > "$scratch/comments"
    reject "Codex $replacement"
done
echo '[]' > "$scratch/comments"; reject 'missing Codex summary'
jq 'map(map(.user.login = "someone"))' "$scratch/clean" > "$scratch/comments"; reject 'spoofed Codex summary'
jq '.[1] = [(.[0][0] | .id = 2 | .body = "<!-- codex-review-state:v1 invalid -->")]' "$scratch/clean" > "$scratch/comments"; reject 'malformed latest Codex summary on another page'
cp "$scratch/clean" "$scratch/comments"
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
echo '{"state":"open","draft":false,"head":{"sha":"new"},"base":{"sha":"base"}}' > "$scratch/pr"; reject 'new head'
echo '{"state":"closed","draft":false,"head":{"sha":"reviewed"},"base":{"sha":"base"}}' > "$scratch/pr"; reject 'closed PR'
echo '{"state":"open","draft":true,"head":{"sha":"reviewed"},"base":{"sha":"base"}}' > "$scratch/pr"; reject 'draft PR'
echo '{"state":"open","draft":false,"head":{"sha":"reviewed"},"base":{"sha":"changed"}}' > "$scratch/pr"; reject 'changed base'
GITHUB_EVENT_NAME=push "$ROOT/script/require_review.sh"
echo 'Review gate regressions passed.'
