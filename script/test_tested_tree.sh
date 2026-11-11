#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/bin" "$scratch/repo"
cat > "$scratch/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ ! -e "$TREE_FIXTURE/fail" ]] || exit 1
case "$2" in
    */pulls) cat "$TREE_FIXTURE/pulls" ;;
    */git/commits/*) cat "$TREE_FIXTURE/head_tree" ;;
    */workflows/ci.yml/runs*) cat "$TREE_FIXTURE/runs" ;;
    */jobs*) cat "$TREE_FIXTURE/jobs" ;;
    *) exit 1 ;;
esac
MOCK
chmod +x "$scratch/bin/gh"
cd "$scratch/repo"
git init -q
git config user.name Fixture
git config user.email fixture@example.invalid
echo 'Fixture' > file
git add .; git commit -qm merged
sha="$(git rev-parse HEAD)"
tree="$(git rev-parse HEAD^{tree})"
head=1111111111111111111111111111111111111111
export PATH="$scratch/bin:$PATH" TREE_FIXTURE="$scratch" GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/master GITHUB_REPOSITORY=owner/repo GITHUB_SHA="$sha" GITHUB_OUTPUT="$scratch/output"
jq -n --arg sha "$sha" --arg head "$head" '[{merged_at:"now",merge_commit_sha:$sha,base:{ref:"master"},head:{sha:$head}}]' > "$scratch/pulls"
echo "$tree" > "$scratch/head_tree"
echo '{"workflow_runs":[{"id":7}]}' > "$scratch/runs"
echo '{"jobs":[{"name":"Native tests and app bundle","conclusion":"success"}]}' > "$scratch/jobs"
expect() {
    : > "$scratch/output"
    "$ROOT/script/pr_tested_tree.sh" > "$scratch/log"
    if ! grep -Fxq "tested=$1" "$scratch/output"; then
        echo "Expected tested=$1: $2" >&2; cat "$scratch/log" >&2; exit 1
    fi
}
expect true 'identical tree with a passing native PR job'
cp "$scratch/jobs" "$scratch/passing"
echo '{"jobs":[{"name":"Native tests and app bundle","conclusion":"skipped"}]}' > "$scratch/jobs"; expect false 'skipped native job'
echo '{"jobs":[{"name":"Native tests and app bundle","conclusion":"failure"}]}' > "$scratch/jobs"; expect false 'failed native job'
cp "$scratch/passing" "$scratch/jobs"
echo '{"workflow_runs":[]}' > "$scratch/runs"; expect false 'no PR run'
echo '{"workflow_runs":[{"id":7}]}' > "$scratch/runs"
echo 2222222222222222222222222222222222222222 > "$scratch/head_tree"; expect false 'different tree'
echo "$tree" > "$scratch/head_tree"
cp "$scratch/pulls" "$scratch/merged"
echo '[]' > "$scratch/pulls"; expect false 'no merged PR'
jq '.[0].merge_commit_sha = "other"' "$scratch/merged" > "$scratch/pulls"; expect false 'PR merged as another commit'
jq '.[0].base.ref = "feature"' "$scratch/merged" > "$scratch/pulls"; expect false 'PR into another branch'
jq '.[0].merged_at = null' "$scratch/merged" > "$scratch/pulls"; expect false 'unmerged PR'
jq '. + .' "$scratch/merged" > "$scratch/pulls"; expect false 'ambiguous PRs'
cp "$scratch/merged" "$scratch/pulls"
touch "$scratch/fail"; expect false 'API failure'
rm "$scratch/fail"
GITHUB_EVENT_NAME=pull_request expect false 'pull request event'
GITHUB_REF=refs/heads/feature expect false 'other branch push'
expect true 'restored fixture'
echo 'Tested-tree regressions passed.'
