#!/usr/bin/env bash
set -euo pipefail
# master and scheduled scans do not need a PR review.
[[ "${GITHUB_EVENT_NAME:-}" == pull_request_review ]] || exit 0
number="$(jq -er '.pull_request.number' "$GITHUB_EVENT_PATH")"
expected="$(jq -er '.pull_request.head.sha' "$GITHUB_EVENT_PATH")"
base="$(jq -er '.pull_request.base.sha' "$GITHUB_EVENT_PATH")"
repo="${GITHUB_REPOSITORY:?}"
pr="$(gh api "repos/$repo/pulls/$number")"
jq -e --arg sha "$expected" --arg base "$base" '.state == "open" and .draft == false and .head.sha == $sha and .base.sha == $base' <<< "$pr" > /dev/null
reviews="$(gh api --paginate --slurp "repos/$repo/pulls/$number/reviews?per_page=100")"
jq -e --arg sha "$expected" '
  [ .[][] | select(.user.login == "coderabbitai[bot]" and .user.type == "Bot") ]
  | max_by(.id) | .state == "APPROVED" and .commit_id == $sha
' <<< "$reviews" > /dev/null
comments="$(gh api --paginate --slurp "repos/$repo/issues/$number/comments?per_page=100")"
jq -e --arg sha "$expected" '
  [ .[][] | select(.user.login == "chatgpt-codex-connector[bot]" and .user.type == "Bot")
    | select(.body | contains("<!-- codex-review-state:v1 ")) ]
  | max_by(.id) | .body
  | capture("<!-- codex-review-state:v1 (?<state>[^\\r\\n]+) -->").state | fromjson
  | (.code_review | .status == "completed" and .commit_sha == $sha
      and .has_any_findings == false and .has_unresolved_findings == false)
    and (.security_review | .status == null or
      (.status == "completed" and .commit_sha == $sha
       and .has_any_findings == false and .has_unresolved_findings == false))
' <<< "$comments" > /dev/null
threads="$(gh api graphql --paginate --slurp -F owner="${repo%/*}" -F name="${repo#*/}" -F number="$number" -f query='
query($owner:String!, $name:String!, $number:Int!, $endCursor:String) {
  repository(owner:$owner, name:$name) {
    pullRequest(number:$number) {
      reviewThreads(first:100, after:$endCursor) {
        nodes { isResolved }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}')"
jq -e 'length > 0 and all(.[]; .data.repository.pullRequest.reviewThreads.nodes != null and all(.data.repository.pullRequest.reviewThreads.nodes[]; .isResolved == true))' <<< "$threads" > /dev/null
# Do not authorize a different head if the branch changed during the queries.
gh api "repos/$repo/pulls/$number" --jq '.head.sha' | grep -Fxq "$expected"
echo "Codex completed cleanly and CodeRabbit approved $expected; all review conversations are resolved."
