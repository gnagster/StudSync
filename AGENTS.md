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
- Follow `docs/ROADMAP.md`. Continue the highest-priority unfinished task, test it, and create/update a focused PR against `master`. Keep one development PR active. Development agents may merge or enable auto-merge under the review rules below.
- Maintain `docs/ROADMAP.md` in every PR: record implemented work, remaining gaps, and relevant verification; distinguish work in an open PR from merged work. Before starting the next task, reconcile the roadmap with merged/open PRs and the code so completed or in-progress features are not implemented twice. After a PR closes, reconcile its outcome in the next development update; revert completion claims for reverted or abandoned work.
- Do not create a separate local reviewer, security schedule, or merge bot.

## Codex review comments and merging

The owner authorizes development and code-review agents to fix findings, push, and merge or enable GitHub auto-merge after Codex review comments have been addressed. Inspect connected code, not only the diff. Keep fixes within the PR's scope.

1. Check the latest PR head, applicable `SECURITY.md` guidance, and the Codex review bot's comments. Wait for the review of the current SHA to finish before merging or enabling auto-merge.
2. Address every finding: either accept it, commit/push a tested fix, and identify that fix in the conversation; or reject it with a concrete reason in the conversation. Do not silently dismiss comments or resolve a conversation before its finding has been handled. Never weaken tests or security controls to hide a finding or failure.
3. A push triggers a fresh review. Handle any new findings before enabling auto-merge; resolved conversations alone do not establish that the current SHA has been reviewed.
4. Once the current-head review is complete and all findings are fixed or explicitly rejected, enable squash auto-merge with `gh pr merge --auto --squash --match-head-commit <reviewed-sha>` or the connected equivalent. GitHub must require passing build/test/CodeQL checks and resolved conversations before merging. If those checks already pass, merging immediately is allowed. Never use `--admin`, force-push, or bypass protections.
5. Disable queued auto-merge before pushing further changes, then recheck review/comments for the new SHA before enabling it again.

These instructions authorize actions but do not grant platform capabilities. Development agents can handle feedback when the hosted reviewer cannot edit, push, or merge. Report unavailable authentication/tools or required owner input rather than creating no-op pushes. Do not claim success without evidence. Keep credentials and private vulnerability details out of public comments. GitHub review decisions and merging are distinct; authors cannot formally approve their own PRs.
