# Development and review

Development runs are started manually by the owner. The proposed five-hour schedule was never saved, and the owner explicitly instructed that it must not be created. Never add a replacement scheduler. Subscription limits stop work; never fall back to an OpenAI API key.

The developer follows the roadmap, verifies changes, and creates/updates PRs. The existing Codex Automatic review integration is configured by the owner to review every push. Development and review agents may fix findings, test, and push. Every Codex finding must be accepted with a tested fix committed/pushed to the PR, or explicitly rejected with a reason in its conversation. After review of the current SHA is complete and all comments are handled, either agent may enable squash auto-merge. GitHub then merges when required CI and conversation resolution pass; if they already pass, the merge may be immediate.

There is no additional local reviewer, Codex Security deployment, custom status publisher, or merge workflow. CodeQL and Dependabot are conventional GitHub services, not OpenAI API jobs.

Use the versioned Python/Swift CodeQL workflow (advanced setup). GitHub's Python-only default setup was switched off because it rejects uploads from the versioned workflow. Master requires the standard Python tests, native tests/app build, and both CodeQL jobs; no custom review status is introduced. Python tests run on macOS because the reference security suite checks macOS ACL removal.

## Platform boundary

Repository instructions do not grant tools or permissions to a hosted review integration. Codex Automatic review posts review feedback; arbitrary editing/pushing/merging during automatic review is not a verified capability here. A development agent with the required GitHub tools can implement fixes and merge under `AGENTS.md`; unavailable hosted write capabilities do not require a separate reviewer or merge bot. Formal self-approval is not possible when development and review use the same GitHub account.

Required CI blocks broken builds, but does not itself prove a Codex review occurred. Agents must check the current-head review and comment dispositions before enabling auto-merge. Enabling repository auto-merge alone does not implement this review loop.

Master also requires resolved review conversations. Wait for the latest commit's review to finish and handle its findings before enabling auto-merge: CI can pass while review is still running. Disable queued auto-merge before pushing further changes and repeat the review/comment check for the new SHA.
