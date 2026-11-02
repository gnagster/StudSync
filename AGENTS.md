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
- Follow `docs/ROADMAP.md`. Continue the highest-priority unfinished task, test it, and create/update a focused PR against `master`. Multiple development PRs may remain open. Put independent changes in separate branches and focused PRs; coordinate overlapping changes rather than implementing the same feature twice. Follow the automatic developer cycle below when asked to start the developer.
- Maintain `docs/ROADMAP.md` in every PR: record implemented work, remaining gaps, and relevant verification; distinguish work in an open PR from merged work. Before starting the next task, reconcile the roadmap with merged/open PRs and the code so completed or in-progress features are not implemented twice. After a PR closes, reconcile its outcome in the next development update; revert completion claims for reverted or abandoned work.
- Do not create a separate local reviewer, security schedule, or merge bot.

## Roadmap reconciliation and ownership

Before choosing a roadmap task, and again after merging a PR:

1. Refresh remote refs with `git fetch --prune origin` and read `origin/master:docs/ROADMAP.md` as the merged baseline. A checked-out branch's roadmap can be older or contain unmerged claims; never use it alone.
2. Overlay open PRs by inspecting their descriptions, changed files and relevant diffs/code. Match actual scope to roadmap items. An open implementation reserves its scope: continue that PR or choose independent work instead of duplicating it.
3. List local/remote branches and worktrees. For plausible overlapping work without an open PR, inspect its diff, uncommitted work and handoff, and check merged/closed PR history. A branch name alone proves neither active work nor completion; old branches can survive squash merges. Do not overwrite or discard work to resolve uncertainty. Record the uncertainty and defer overlapping work while continuing independent tasks.
4. Record each queued item's status as **Planned**, **In progress**, or **Merged**, with its PR link or, before a PR exists, its branch/worktree and next step. Mark only surviving merged scope as Merged; keep unimplemented portions Planned. Reconcile reverted/abandoned work with the actual code before reopening it.
5. Reconcile roadmap conflicts from that baseline, PR outcomes and code rather than blindly combining checkboxes from different branches. Update the roadmap in the focused PR. If remote/PR information is unavailable, report the missing evidence and do not assume an overlapping task is free.

## Automatic developer cycle

When instructed to start the automatic developer, execute this cycle in the current run; do not create or change a schedule unless explicitly requested.

1. Apply the roadmap reconciliation and ownership procedure above, then reconcile unfinished conversation tasks with that combined state and issues. Continue still-valid unfinished work first; do not recreate completed or abandoned work. Critical correctness/security failures take priority over features. Record blockers and continue independent work rather than letting a blocked task stall the entire run.
2. Inspect existing PRs for failed checks, conflicts, and unhandled Codex comments. Evaluate suggestions using the connected code, tests, and product scope. Accept useful findings with tested fixes, or reject unsuitable suggestions with a concrete reason in their conversations. Push fixes and leave updated PRs for the next run.
3. Merge eligible PRs from earlier runs under the rules below. After a confirmed merge, delete its branch only if no other PR, worktree, or unfinished work depends on it. Reconcile remaining PRs with the changed master; updated heads need fresh review/checks.
4. Address issues and maintenance needs, prioritizing bugs, security/Dependabot findings, regressions, and CI failures. Check for an existing implementation or PR before starting another fix.
5. Develop the next clearly scoped unfinished roadmap item, test it, and create/update a focused PR. Continue with additional independently actionable items on their own branches. Do not start overlapping implementations or duplicate work already in open PRs.
6. Maintain the roadmap and affected documentation in each PR, recording implementation, verification, open-PR versus merged status, blockers, and next steps. Save reviewable progress so another run can resume without reconstructing the conversation.
7. Repeat from step 1 while useful actionable work and sufficient allowance remain. Stop when only external checks/reviews or required owner input remain, tools/authentication block progress, or a usage limit is reached. Preserve a clean handoff before an apparent limit. Do not busy-wait, create no-op pushes, or invent unnecessary work to consume allowance. When the roadmap is complete, maintain existing functionality and act on concrete findings rather than inventing new features.

Do not overlap developer runs in the same checkout or branch. Check ownership before editing and coordinate/defer conflicting work. Multiple open PRs do not authorize simultaneous conflicting writes.

## Review decisions and merging

- Review comments are suggestions, not mandatory changes. Decide independently whether each improves correctness, security, or intended behavior. Record a tested fix committed/pushed to the PR or a concrete rejection reason before resolving its conversation. Never weaken tests or security controls to hide a failure.
- Merge only an earlier-run PR whose current-head Codex review has finished, all findings are handled, required build/test/CodeQL checks pass, and required conversations are resolved. Verify the head has not changed and use `gh pr merge --squash --match-head-commit <reviewed-sha>` or the connected equivalent. Never use `--admin`, force-push, or bypass protections.
- PRs created or updated in this run stay open until the next run even if checks finish quickly. Do not wait for CI/review to merge afterward in the same run. Do not queue auto-merge while idle; disable queued auto-merge before updating a PR. A new SHA needs fresh review/checks; resolved older conversations do not prove it was reviewed.
- Notify only meaningful completion, persistent failure, or required owner input; stay quiet on unchanged/non-actionable state.

These instructions authorize actions but do not grant platform capabilities. Development agents can handle feedback when the hosted reviewer cannot edit, push, or merge. Report unavailable authentication/tools or required owner input rather than creating no-op pushes. Do not claim success without evidence. Keep credentials and private vulnerability details out of public comments. GitHub review decisions and merging are distinct; authors cannot formally approve their own PRs.
