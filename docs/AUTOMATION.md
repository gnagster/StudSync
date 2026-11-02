# Development and review

Use owner-started runs and existing owner-configured automation; do not create or change development schedules without an explicit request. Subscription limits stop work; never fall back to an OpenAI API key.

Multiple focused PRs may stay open. Independent changes use separate branches. At the start of each run, inspect existing PRs: merge only those with finished current-head Codex review, passing required CI, and handled comments. Fix or reject findings as appropriate; do not wait for pending checks just to merge later in the same run. Newly created or updated PRs stay open until the next run. Do not queue auto-merge to merge while the agent is idle.

Codex suggestions are not mandatory. The agent judges whether they improve correctness, security, or intended behavior, then either commits/pushes a tested fix or records a concrete rejection reason in the conversation. Resolve conversations only after handling the finding. A new push requires new review/checks; never weaken checks or create no-op pushes.

The owner configured the existing automatic review integration to review each push. Development agents can implement fixes and merge eligible PRs using GitHub tools. No additional local reviewer, security scheduler, custom status publisher, merge bot, or OpenAI API job is needed. GitHub authors cannot formally approve their own PRs.

Use the versioned Python/Swift CodeQL workflow (advanced setup). Python-only default setup is off because it rejects uploads from the versioned workflow. Master requires Python tests, native tests/app build, both CodeQL jobs, and resolved conversations. Python tests run on macOS because reference security tests verify ACL removal. CI does not prove a review occurred: verify the latest-head review and comment decisions under `AGENTS.md` before merging, without bypassing protections.
