#!/usr/bin/env bash
set -euo pipefail
# On a master push, report tested=true only when the pushed tree is byte-identical to the head of
# the merged PR and PR CI passed the native job on that head. Any doubt runs the full tests.
tested=false
report() { echo "tested=$tested" >> "${GITHUB_OUTPUT:?}"; echo "Tree already passed PR CI: $tested${1:+ ($1)}"; exit 0; }
[[ "${GITHUB_EVENT_NAME:-}" == push && "${GITHUB_REF:-}" == refs/heads/master ]] || report 'not a master push'
repo="${GITHUB_REPOSITORY:?}"
sha="${GITHUB_SHA:?}"
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || report 'invalid commit'
pulls="$(gh api "repos/$repo/commits/$sha/pulls")" || report 'pull lookup failed'
head="$(jq -er --arg sha "$sha" '[.[] | select(.merged_at != null and .merge_commit_sha == $sha and .base.ref == "master")] | if length == 1 then .[0].head.sha else empty end' <<< "$pulls")" || report 'no unique merged PR'
[[ "$head" =~ ^[0-9a-f]{40}$ ]] || report 'invalid PR head'
pushed_tree="$(git rev-parse --verify "$sha^{tree}")" || report 'pushed tree unavailable'
head_tree="$(gh api "repos/$repo/git/commits/$head" --jq '.tree.sha')" || report 'PR head tree unavailable'
[[ "$pushed_tree" == "$head_tree" ]] || report 'merged tree differs from PR head'
runs="$(gh api "repos/$repo/actions/workflows/ci.yml/runs?event=pull_request&head_sha=$head&status=success&per_page=100")" || report 'run lookup failed'
for run in $(jq -r '.workflow_runs[].id' <<< "$runs"); do
    jobs="$(gh api "repos/$repo/actions/runs/$run/jobs?filter=latest&per_page=100")" || continue
    if jq -e '[.jobs[] | select(.name == "Native tests and app bundle" and .conclusion == "success")] | length == 1' <<< "$jobs" > /dev/null; then
        tested=true; report "PR CI run $run"
    fi
done
report 'no passing native PR job for that head'
