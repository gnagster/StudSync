# StudSync agent instructions

StudSync is a native Swift/SwiftUI menu-bar app for Universität Göttingen Stud.IP files in ordinary Finder folders. Personal Apple Silicon use comes first. Python remains a tested reference during migration.

## Development

- Use Ponytail: make the smallest complete change, reuse existing code and platform APIs, and avoid speculative abstractions.
- Use the Build macOS Apps skills for native work and GitHub tools or `gh` for repository operations.
- Read `SECURITY.md` for authentication, networking, files, persistence, and workflow changes.
- Build/run: `./script/build_and_run.sh`. Verify: `./script/verify.sh`.
- Keep networking/sync in StudSyncCore and presentation in StudSyncApp. Native code must not depend on Python.
- Add focused regression tests for nontrivial changes; keep existing checks passing.
- Never use OpenAI API credentials or API-billed Codex Actions. Use the owner's ChatGPT subscription; GitHub CI runs conventional tools only.
- Follow `docs/ROADMAP.md`. Continue the highest-priority unfinished task, test it, and create/update a focused PR against `master`. Multiple development PRs may remain open. Put independent changes in separate branches and focused PRs; coordinate overlapping changes rather than implementing the same feature twice. Development agents may merge under the review rules below.
- Maintain `docs/ROADMAP.md` in every PR: record implemented work, remaining gaps, and relevant verification; distinguish work in an open PR from merged work. Before starting the next task, reconcile the roadmap with merged/open PRs and the code so completed or in-progress features are not implemented twice. After a PR closes, reconcile its outcome in the next development update; revert completion claims for reverted or abandoned work.
- Do not create a separate local reviewer, security schedule, or merge bot.

## Codex review comments and merging

The owner authorizes development and code-review agents to evaluate review feedback, fix findings, push, and merge eligible PRs. Inspect connected code, not only the diff. Keep fixes within the PR's scope.

1. At the start of each run, inspect existing PRs, the current head SHA, Codex review comments, and required CI. Merge eligible PRs whose checks and current-head review have already finished; otherwise continue useful development without waiting for them.
2. Review comments are suggestions, not mandatory changes. Decide whether each suggestion improves correctness, security, or the intended product behavior. Accept useful findings with a tested fix committed/pushed to the PR and identify the fix in the conversation. Reject unsuitable suggestions with a concrete reason in the conversation. Do not silently dismiss comments or resolve conversations before making and recording that decision. Never weaken tests or security controls to hide a failure.
3. Merge only when the current-head Codex review has finished, all comments are handled, required build/test/CodeQL checks pass, and required conversations are resolved. Use `gh pr merge --squash --match-head-commit <reviewed-sha>` or the connected equivalent. Never use `--admin`, force-push, or bypass protections.
4. Do not wait for CI/review just to merge immediately afterward. PRs created or updated during this run remain open for inspection and merging or further fixes at the next run, often several hours later. Do not queue auto-merge to merge them while the agent is idle; disable any existing queued auto-merge before updating a PR.
5. A push triggers fresh review and checks. Re-evaluate the new SHA on the next run; resolved conversations on an older SHA do not establish that the new one has been reviewed.

These instructions authorize actions but do not grant platform capabilities. Development agents can handle feedback when the hosted reviewer cannot edit, push, or merge. Report unavailable authentication/tools or required owner input rather than creating no-op pushes. Do not claim success without evidence. Keep credentials and private vulnerability details out of public comments. GitHub review decisions and merging are distinct; authors cannot formally approve their own PRs.
